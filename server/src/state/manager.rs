use std::sync::Arc;
use std::time::{Duration, SystemTime, UNIX_EPOCH};

use areyoughost_core::game_logic::role_engine::{
    check_win as engine_check_win, resolve_night, EngineNightAction, EnginePlayerState,
    NightActionType, SkillUsageState,
};
use areyoughost_core::game_logic::vote_resolver::{VoteOutcome, VoteResolver};
use dashmap::DashMap;
use rand::seq::SliceRandom;
use sqlx::PgPool;
use std::collections::{HashMap, HashSet, VecDeque};
use tokio::sync::{mpsc, Mutex};
use axum::extract::ws::Message;
use serde::Serialize;

pub type PlayerId = String;
pub type RoomId = String;

#[derive(Clone, Debug, Serialize, PartialEq, Eq)]
pub enum RuntimePhase {
    Lobby,
    Night,
    Day,
    Voting,
    End,
}

#[derive(Clone, Debug)]
pub struct RuntimePlayerState {
    pub alive: bool,
    pub role: Option<String>,
}

#[derive(Clone, Debug)]
pub struct RuntimeAction {
    pub action_type: String,
    pub target_id: Option<String>,
}

#[derive(Clone, Debug)]
pub struct RuntimeGame {
    pub room_id: RoomId,
    pub phase: RuntimePhase,
    pub day_no: u32,
    pub night_no: u32,
    pub players: HashMap<PlayerId, RuntimePlayerState>,
    pub actions: HashMap<PlayerId, RuntimeAction>,
    pub votes: HashMap<PlayerId, PlayerId>,
    pub skill_usage: HashMap<PlayerId, SkillUsageState>,
    pub karma_targets: HashMap<PlayerId, PlayerId>,
    pub seen_request_ids: HashSet<String>,
    pub phase_started_at: i64,
    pub phase_deadline_at: i64,
}

// ─────────────────────────────────────────
// In-memory game state (unchanged)
// ─────────────────────────────────────────

#[derive(Clone, Debug, Serialize)]
pub struct PlayerInfo {
    pub player_id: PlayerId,
    pub username: String,
    pub is_ready: bool,
    pub is_host: bool,
}

#[derive(Clone, Debug)]
pub struct Room {
    pub room_id: RoomId,
    pub players: Vec<PlayerInfo>,
    pub max_players: usize,
    pub is_public: bool,
    pub status: String, // "waiting" | "playing"
}

// ─────────────────────────────────────────
// AppState — shared across all handlers
// ─────────────────────────────────────────

pub struct AppState {
    // Postgres connection pool (Supabase)
    pub db: PgPool,

    // JWT secret (from JWT_SECRET env var)
    pub jwt_secret: String,

    // Active WebSocket connections: player_id → tx channel
    pub connections: DashMap<PlayerId, mpsc::UnboundedSender<Message>>,

    // Which room each player is in
    pub player_rooms: DashMap<PlayerId, RoomId>,

    // In-memory rooms
    pub rooms: DashMap<RoomId, Room>,

    // Matchmaking queue (FIFO)
    pub queue: Mutex<VecDeque<PlayerId>>,

    // Invite code → room_id (for private rooms)
    pub invites: DashMap<String, RoomId>,

    // Runtime authoritative game state by room
    pub active_games: DashMap<RoomId, RuntimeGame>,
    pub day_phase_secs: u64,
    pub night_phase_secs: u64,
    pub voting_phase_secs: u64,

    // Reconnect resume token management
    /// resume_token -> (player_id, expires_at_unix_secs)
    pub resume_tokens: DashMap<String, (PlayerId, i64)>,
    pub player_resume_tokens: DashMap<PlayerId, String>,

    // Pending disconnect deadlines (unix timestamp in seconds)
    pub pending_disconnects: DashMap<PlayerId, i64>,

    // Grace period for reconnect before removing player from room
    pub reconnect_grace_secs: u64,

    // Quick play countdown deadline per room (unix seconds)
    pub quickplay_countdown_deadlines: DashMap<RoomId, i64>,
}

impl AppState {
    const DEFAULT_ROLE_POOL_16: [&'static str; 16] = [
        "ชาวบ้าน",
        "ร่างทรง",
        "แพทย์",
        "ทหาร",
        "ตำรวจ",
        "พระธุดงค์",
        "หมอผีคุณไสย",
        "สัปเหร่อ",
        "ผีปอบ",
        "ผีกระสือใหญ่",
        "ผีตายโหง",
        "ผีเปรต",
        "หมอผีดำ",
        "ฆาตกรต่อเนื่อง",
        "คนดวงซวย",
        "เจ้ากรรมนายเวร",
    ];

    pub fn new(
        db: PgPool,
        jwt_secret: String,
        reconnect_grace_secs: u64,
        day_phase_secs: u64,
        night_phase_secs: u64,
        voting_phase_secs: u64,
    ) -> Arc<Self> {
        Arc::new(Self {
            db,
            jwt_secret,
            connections: DashMap::new(),
            player_rooms: DashMap::new(),
            rooms: DashMap::new(),
            queue: Mutex::new(VecDeque::new()),
            invites: DashMap::new(),
            active_games: DashMap::new(),
            day_phase_secs,
            night_phase_secs,
            voting_phase_secs,
            resume_tokens: DashMap::new(),
            player_resume_tokens: DashMap::new(),
            pending_disconnects: DashMap::new(),
            reconnect_grace_secs,
            quickplay_countdown_deadlines: DashMap::new(),
        })
    }

    fn now_unix_secs() -> i64 {
        SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap_or(Duration::from_secs(0))
            .as_secs() as i64
    }

    fn canonical_night_action_for_role(role: &str, raw_action: &str) -> Option<String> {
        let normalized = raw_action.trim().to_lowercase();
        let role = role.trim();
        let mapped = match normalized.as_str() {
            // Canonical engine action ids (must echo as-is for night resolver)
            "ghost_kill"
            | "serial_kill"
            | "seer_check"
            | "police_check"
            | "aura_check"
            | "doctor_protect"
            | "soldier_guard"
            | "dark_protect"
            | "dark_curse"
            | "witch_revive"
            | "witch_poison" => Some(normalized.clone()),
            "pass" | "skip" => Some("pass".to_string()),
            // Legacy generic kill
            "kill" => {
                if role == "ฆาตกรต่อเนื่อง" {
                    Some("serial_kill".to_string())
                } else {
                    Some("ghost_kill".to_string())
                }
            }
            _ => None,
        };
        if mapped.is_some() {
            return mapped;
        }

        // Thai skill labels from UI
        let thai = raw_action.trim();
        match thai {
            "ข้าม" => Some("pass".to_string()),
            "สกิลตาวิเศษ" => Some("seer_check".to_string()),
            // Current mobile client resolves police compare locally and does not submit action.
            // Keep mapping for forward compatibility, but police should not block phase progression.
            "สกิลสอบสวน" => Some("police_check".to_string()),
            "สกิลตรวจออร่า" => Some("aura_check".to_string()),
            "สกิลปกป้อง" | "สกิลคุ้มครอง" => {
                if role == "ทหาร" {
                    Some("soldier_guard".to_string())
                } else {
                    Some("doctor_protect".to_string())
                }
            }
            "สกิลยืนแทน" => Some("soldier_guard".to_string()),
            "สกิลปกป้องผี" => Some("dark_protect".to_string()),
            "สกิลสาปพูดไม่ได้" => Some("dark_curse".to_string()),
            "สกิลชุบชีวิต" => Some("witch_revive".to_string()),
            "สกิลคุณไสยฆ่า" => Some("witch_poison".to_string()),
            "สกิลฆ่าเดี่ยว" => Some("serial_kill".to_string()),
            "สกิลลอบสังหาร" => Some("ghost_kill".to_string()),
            _ => None,
        }
    }

    fn role_has_night_action(role: &str) -> bool {
        matches!(
            role,
            "ร่างทรง"
                | "แพทย์"
                | "ทหาร"
                | "พระธุดงค์"
                | "หมอผีคุณไสย"
                | "ผีปอบ"
                | "ผีกระสือใหญ่"
                | "ผีตายโหง"
                | "ผีเปรต"
                | "หมอผีดำ"
                | "ฆาตกรต่อเนื่อง"
        )
    }

    fn winner_kind_for_phase_end(game: &RuntimeGame) -> Option<&'static str> {
        for (karma_id, target_id) in game.karma_targets.iter() {
            let karma_alive = game.players.get(karma_id).map(|p| p.alive).unwrap_or(false);
            let target_dead = game.players.get(target_id).map(|p| !p.alive).unwrap_or(false);
            if karma_alive && target_dead {
                return Some("karma");
            }
        }
        let mut players = HashMap::<String, EnginePlayerState>::new();
        for (id, p) in game.players.iter() {
            players.insert(
                id.clone(),
                EnginePlayerState {
                    alive: p.alive,
                    role: p.role.clone().unwrap_or_else(|| "ชาวบ้าน".to_string()),
                    cursed_silenced_today: false,
                },
            );
        }
        engine_check_win(&players)
    }

    /// Mark user as disconnected and start grace countdown.
    pub fn mark_pending_disconnect(self: &Arc<Self>, player_id: &str) {
        let deadline = Self::now_unix_secs() + self.reconnect_grace_secs as i64;
        let player_id_owned = player_id.to_string();
        self.pending_disconnects.insert(player_id_owned.clone(), deadline);

        let state = Arc::clone(self);
        tokio::spawn(async move {
            tokio::time::sleep(Duration::from_secs(state.reconnect_grace_secs)).await;

            // If still disconnected and deadline has not been replaced, finalize leave.
            let should_finalize = state
                .pending_disconnects
                .get(&player_id_owned)
                .map(|d| *d <= Self::now_unix_secs())
                .unwrap_or(false);

            if !should_finalize {
                return;
            }

            if state.connections.contains_key(&player_id_owned) {
                return;
            }

            state.pending_disconnects.remove(&player_id_owned);
            if let Some(room_id) = state.leave_room(&player_id_owned).await {
                tracing::info!(
                    "Player {} removed after reconnect grace expired in room {}",
                    player_id_owned,
                    room_id
                );
            }
        });
    }

    /// Returns true when this player reconnects within grace window.
    pub fn consume_pending_disconnect(&self, player_id: &str) -> bool {
        self.pending_disconnects.remove(player_id).is_some()
    }

    pub fn issue_resume_token(&self, player_id: &str) -> String {
        const TTL_SECS: i64 = 600;
        if let Some((_, old_token)) = self.player_resume_tokens.remove(player_id) {
            self.resume_tokens.remove(&old_token);
        }

        let token = uuid::Uuid::new_v4().to_string();
        let exp = Self::now_unix_secs() + TTL_SECS;
        self.resume_tokens
            .insert(token.clone(), (player_id.to_string(), exp));
        self.player_resume_tokens
            .insert(player_id.to_string(), token.clone());
        token
    }

    pub fn consume_resume_token(&self, token: &str) -> Option<PlayerId> {
        let (_, (player_id, exp)) = self.resume_tokens.remove(token)?;
        if Self::now_unix_secs() > exp {
            self.player_resume_tokens.remove(&player_id);
            return None;
        }
        self.player_resume_tokens.remove(&player_id);
        Some(player_id)
    }

    pub async fn get_username(&self, player_id: &str) -> Option<String> {
        #[derive(sqlx::FromRow)]
        struct UserRow {
            username: String,
        }

        sqlx::query_as::<_, UserRow>("SELECT username FROM players WHERE player_id = $1::uuid")
            .bind(player_id)
            .fetch_optional(&self.db)
            .await
            .ok()
            .flatten()
            .map(|r| r.username)
    }

    // ─── Quick Play ───────────────────────────────────────────────

    /// Find an existing waiting public room with space, or create a new one.
    pub async fn quick_play(&self, player_id: String, username: String) -> Result<RoomId, String> {
        // Find an available public waiting room
        let available_room = self.rooms.iter().find(|r| {
            r.status == "waiting" && r.is_public && r.players.len() < r.max_players
        }).map(|r| r.room_id.clone());

        if let Some(room_id) = available_room {
            self.join_room(&room_id, &player_id, username).await?;
            return Ok(room_id);
        }

        // No available room — create a new public/matchmaking one.
        // Some DB snapshots still have older room_type constraints; retry with
        // MATCHMAKING when PUBLIC is rejected by rooms_room_type_check.
        let room_id = match self
            .create_room(player_id.clone(), username.clone(), 16, "PUBLIC")
            .await
        {
            Ok(room_id) => room_id,
            Err(e) if e.contains("rooms_room_type_check") => {
                match self
                    .create_room(player_id.clone(), username.clone(), 16, "MATCHMAKING")
                    .await
                {
                    Ok(room_id) => room_id,
                    Err(retry_err) if retry_err.contains("rooms_room_type_check") => self
                        .create_room(player_id, username, 16, "PRIVATE")
                        .await
                        .map_err(|last_err| {
                            format!(
                                "Failed to create room after PUBLIC->MATCHMAKING->PRIVATE retry: {} (previous: {}, initial: {})",
                                last_err, retry_err, e
                            )
                        })?,
                    Err(retry_err) => {
                        return Err(format!(
                            "Failed to create room after PUBLIC retry: {} (initial: {})",
                            retry_err, e
                        ))
                    }
                }
            }
            Err(e) => return Err(format!("Failed to create room: {}", e)),
        };
        Ok(room_id)
    }

    pub fn schedule_quickplay_start(self: &Arc<Self>, room_id: &str) {
        let room_id = room_id.to_string();
        let (eligible, players_len) = match self.rooms.get(&room_id) {
            Some(room) => (
                room.status == "waiting",
                room.players.len(),
            ),
            None => (false, 0),
        };
        if !eligible {
            return;
        }
        if players_len < 2 {
            self.quickplay_countdown_deadlines.remove(&room_id);
            let cancel_msg = serde_json::json!({
                "type": "mm.countdown_cancelled",
                "payload": { "roomId": room_id }
            });
            self.broadcast_to_room(&room_id, &cancel_msg.to_string());
            return;
        }

        let now = Self::now_unix_secs();
        if let Some(deadline_ref) = self.quickplay_countdown_deadlines.get(&room_id) {
            if *deadline_ref > now {
                let remaining = (*deadline_ref - now).max(0);
                let countdown_msg = serde_json::json!({
                    "type": "mm.countdown",
                    "payload": {
                        "roomId": room_id,
                        "seconds": remaining,
                        "deadlineUnix": *deadline_ref
                    }
                });
                self.broadcast_to_room(&room_id, &countdown_msg.to_string());
                return;
            }
        }

        let deadline = now + 30;
        self.quickplay_countdown_deadlines
            .insert(room_id.clone(), deadline);
        let countdown_msg = serde_json::json!({
            "type": "mm.countdown",
            "payload": {
                "roomId": room_id,
                "seconds": 30,
                "deadlineUnix": deadline
            }
        });
        self.broadcast_to_room(&room_id, &countdown_msg.to_string());

        let state = Arc::clone(self);
        tokio::spawn(async move {
            tokio::time::sleep(Duration::from_secs(30)).await;

            let still_same_deadline = state
                .quickplay_countdown_deadlines
                .get(&room_id)
                .map(|d| *d == deadline)
                .unwrap_or(false);
            if !still_same_deadline {
                return;
            }

            let (host_id, players_len, waiting) = match state.rooms.get(&room_id) {
                Some(room) => {
                    let host = room
                        .players
                        .iter()
                        .find(|p| p.is_host)
                        .map(|p| p.player_id.clone())
                        .or_else(|| room.players.first().map(|p| p.player_id.clone()));
                    (host, room.players.len(), room.status == "waiting")
                }
                None => (None, 0, false),
            };

            if !waiting || players_len < 2 {
                state.quickplay_countdown_deadlines.remove(&room_id);
                let cancel_msg = serde_json::json!({
                    "type": "mm.countdown_cancelled",
                    "payload": { "roomId": room_id }
                });
                state.broadcast_to_room(&room_id, &cancel_msg.to_string());
                return;
            }

            if let Some(host_id) = host_id {
                match state.start_game(&room_id, &host_id).await {
                    Ok(payload) => {
                        state.quickplay_countdown_deadlines.remove(&room_id);
                        let started = serde_json::json!({
                            "type": "game.started",
                            "payload": payload
                        });
                        state.broadcast_to_room(&room_id, &started.to_string());
                        if let Some(room_state) = state.get_room_state(&room_id) {
                            let state_msg = serde_json::json!({
                                "type": "room.state",
                                "payload": room_state
                            });
                            state.broadcast_to_room(&room_id, &state_msg.to_string());
                        }
                    }
                    Err(e) => {
                        state.quickplay_countdown_deadlines.remove(&room_id);
                        let fail_msg = serde_json::json!({
                            "type": "error",
                            "payload": {
                                "code": "GAME_START_FAILED",
                                "message": e
                            }
                        });
                        state.broadcast_to_room(&room_id, &fail_msg.to_string());
                    }
                }
            }
        });
    }

    // ─── Private Room ─────────────────────────────────────────────

    /// Create a private room and return (room_id, invite_code).
    pub async fn create_private_room(
        &self,
        host_id: String,
        username: String,
    ) -> Result<(RoomId, String), String> {
        let room_id_uuid = uuid::Uuid::new_v4();
        let room_id = room_id_uuid.to_string();
        let host_uuid = uuid::Uuid::parse_str(&host_id)
            .map_err(|_| "Invalid host ID format".to_string())?;
        let invite_code = uuid::Uuid::new_v4()
            .to_string()
            .split('-')
            .next()
            .unwrap_or("INVITE")
            .to_uppercase();

        let now = chrono::Utc::now();
        let mut tx = self.db.begin().await
            .map_err(|e| format!("DB Error: {}", e))?;

        sqlx::query(
            "INSERT INTO rooms (room_id, owner_id, room_name, max_players, is_public, room_type, room_status, created_at, updated_at) \
             VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)"
        )
        .bind(room_id_uuid)
        .bind(host_uuid)
        .bind(format!("{}'s Room", username))
        .bind(16i32)
        .bind(false) // is_public (DB column is boolean)
        .bind("PRIVATE")
        .bind("WAITING")
        .bind(now)
        .bind(now)
        .execute(&mut *tx)
        .await
        .map_err(|e| format!("DB Error (insert room): {}", e))?;

        let member_id = uuid::Uuid::new_v4();
        sqlx::query(
            "INSERT INTO room_members (room_member_id, room_id, player_id, member_status, joined_at) \
             VALUES ($1, $2, $3, $4, $5)"
        )
        .bind(member_id)
        .bind(room_id_uuid)
        .bind(host_uuid)
        .bind("JOINED")
        .bind(now)
        .execute(&mut *tx)
        .await
        .map_err(|e| format!("DB Error (insert member): {}", e))?;

        tx.commit().await
            .map_err(|e| format!("DB Error (commit): {}", e))?;

        let room = Room {
            room_id: room_id.clone(),
            players: vec![PlayerInfo {
                player_id: host_id.clone(),
                username,
                is_ready: false,
                is_host: true,
            }],
            max_players: 16,
            is_public: false,
            status: "waiting".to_string(),
        };

        self.rooms.insert(room_id.clone(), room);
        self.player_rooms.insert(host_id, room_id.clone());
        self.invites.insert(invite_code.clone(), room_id.clone());

        tracing::info!("Created private room {} with invite_code {}", room_id, invite_code);
        Ok((room_id, invite_code))
    }

    /// Resolve an invite code to a room_id.
    pub fn resolve_invite(&self, invite_code: &str) -> Option<RoomId> {
        self.invites.get(invite_code).map(|r| r.clone())
    }

    // ─── Matchmaking ──────────────────────────────────────────────

    pub async fn join_queue(&self, player_id: String, _username: String) -> Option<RoomId> {
        {
            let mut queue = self.queue.lock().await;
            if !queue.contains(&player_id) {
                queue.push_back(player_id.clone());
                tracing::info!("Player {} added to queue. Size: {}", player_id, queue.len());
            }
        }
        self.try_match_players(2).await
    }

    async fn try_match_players(&self, min_players: usize) -> Option<RoomId> {
        let mut queue = self.queue.lock().await;

        if queue.len() < min_players {
            return None;
        }

        let mut matched_player_ids = Vec::new();
        for _ in 0..min_players.min(queue.len()) {
            if let Some(player_id_str) = queue.pop_front() {
                matched_player_ids.push(player_id_str);
            }
        }
        drop(queue);

        if matched_player_ids.is_empty() {
            return None;
        }

        let host_id = matched_player_ids[0].clone();
        let host_username = self
            .get_username(&host_id)
            .await
            .unwrap_or_else(|| "Player1".to_string());

        let room_id = match self
            .create_room(host_id.clone(), host_username, 16, "PUBLIC")
            .await
        {
            Ok(room_id) => room_id,
            Err(e) if e.contains("rooms_room_type_check") => {
                match self
                    .create_room(host_id.clone(), "Matchmaking Host".to_string(), 16, "MATCHMAKING")
                    .await
                {
                    Ok(room_id) => room_id,
                    Err(retry_err) if retry_err.contains("rooms_room_type_check") => {
                        match self
                            .create_room(host_id.clone(), "Matchmaking Host".to_string(), 16, "PRIVATE")
                            .await
                        {
                            Ok(room_id) => room_id,
                            Err(last_err) => {
                                tracing::error!(
                                    "matchmaking create_room failed after PUBLIC->MATCHMAKING->PRIVATE retry: {} (previous: {}, initial: {})",
                                    last_err,
                                    retry_err,
                                    e
                                );
                                return None;
                            }
                        }
                    }
                    Err(retry_err) => {
                        tracing::error!(
                            "matchmaking create_room failed after PUBLIC retry: {} (initial: {})",
                            retry_err,
                            e
                        );
                        return None;
                    }
                }
            }
            Err(e) => {
                tracing::error!("matchmaking create_room failed: {}", e);
                return None;
            }
        };

        for player_id in matched_player_ids.into_iter().skip(1) {
            let username = self
                .get_username(&player_id)
                .await
                .unwrap_or_else(|| "Player".to_string());
            if let Err(e) = self.join_room(&room_id, &player_id, username).await {
                tracing::error!("matchmaking join_room failed for {}: {}", player_id, e);
            }
        }

        tracing::info!(
            "Created matchmaking room {} with minimum {} players",
            room_id,
            min_players
        );
        Some(room_id)
    }

    // ─── Room helpers ─────────────────────────────────────────────

    pub async fn create_room(
        &self,
        host_id_str: String,
        username: String,
        max_players: usize,
        room_type: &str,
    ) -> Result<RoomId, String> {
        let room_id_uuid = uuid::Uuid::new_v4();
        let room_id = room_id_uuid.to_string();
        let host_uuid = uuid::Uuid::parse_str(&host_id_str)
            .map_err(|_| "Invalid host ID format".to_string())?;

        let mut tx = self.db.begin().await
            .map_err(|e| format!("DB Error (begin tx): {}", e))?;

        // 1. Insert into rooms (is_public is boolean in Postgres)
        let now = chrono::Utc::now();
        sqlx::query(
            "INSERT INTO rooms (room_id, owner_id, room_name, max_players, is_public, room_type, room_status, created_at, updated_at) 
             VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)"
        )
        .bind(room_id_uuid)
        .bind(host_uuid)
        .bind(format!("{}'s Room", username))
        .bind(max_players as i32)
        .bind(true)
        .bind(room_type)
        .bind("WAITING")
        .bind(now)
        .bind(now)
        .execute(&mut *tx)
        .await
        .map_err(|e| format!("DB Error (insert room): {}", e))?;

        // 2. Insert into room_members (Host is JOINED)
        let room_member_id = uuid::Uuid::new_v4();
        sqlx::query(
            "INSERT INTO room_members (room_member_id, room_id, player_id, member_status, joined_at) 
             VALUES ($1, $2, $3, $4, $5)"
        )
        .bind(room_member_id)
        .bind(room_id_uuid)
        .bind(host_uuid)
        .bind("JOINED")
        .bind(now)
        .execute(&mut *tx)
        .await
        .map_err(|e| format!("DB Error (insert member): {}", e))?;

        tx.commit().await
            .map_err(|e| format!("DB Error (commit tx): {}", e))?;

        let room = Room {
            room_id: room_id.clone(),
            players: vec![PlayerInfo {
                player_id: host_id_str.clone(),
                username,
                is_ready: false,
                is_host: true,
            }],
            max_players,
            is_public: true,
            status: "waiting".to_string(),
        };

        self.rooms.insert(room_id.clone(), room);
        self.player_rooms.insert(host_id_str, room_id.clone());
        tracing::info!("Created and persisted custom room {}", room_id);
        
        Ok(room_id)
    }

    pub async fn join_room(&self, room_id_str: &str, player_id_str: &str, username: String) -> Result<(), String> {
        let room_id_uuid = uuid::Uuid::parse_str(room_id_str)
            .map_err(|_| "Invalid room ID format".to_string())?;
            
        let player_uuid = uuid::Uuid::parse_str(player_id_str)
            .map_err(|_| "Invalid player ID format".to_string())?;

        // 1. Check if room exists in memory
        let mut room_ref = self.rooms.get_mut(room_id_str)
            .ok_or_else(|| "Room not found".to_string())?;

        if room_ref.players.len() >= room_ref.max_players {
            return Err("Room is full".to_string());
        }

        if room_ref.players.iter().any(|p| p.player_id == player_id_str) {
            return Err("Already in room".to_string());
        }

        let mut tx = self.db.begin().await
            .map_err(|e| format!("DB Error (begin tx): {}", e))?;

        // 2. Insert into room_members using ON CONFLICT to handle rejoins
        let now = chrono::Utc::now();
        let member_id = uuid::Uuid::new_v4();
        sqlx::query(
            "INSERT INTO room_members (room_member_id, room_id, player_id, member_status, joined_at) 
             VALUES ($1, $2, $3, $4, $5)
             ON CONFLICT (room_id, player_id) 
             DO UPDATE SET member_status = 'JOINED', joined_at = EXCLUDED.joined_at, left_at = NULL, lost_at = NULL"
        )
        .bind(member_id)
        .bind(room_id_uuid)
        .bind(player_uuid)
        .bind("JOINED")
        .bind(now)
        .execute(&mut *tx)
        .await
        .map_err(|e| format!("DB Error (upsert member): {}", e))?;

        tx.commit().await
            .map_err(|e| format!("DB Error (commit tx): {}", e))?;

        // 3. Update in-memory state
        room_ref.players.push(PlayerInfo {
            player_id: player_id_str.to_string(),
            username,
            is_ready: false,
            is_host: false,
        });

        // Ensure we drop the RefMut before inserting into player_rooms to avoid any potential deadlocks 
        // (though DashMap handles this ok, it's good practice)
        drop(room_ref); 

        self.player_rooms.insert(player_id_str.to_string(), room_id_str.to_string());
        tracing::info!("Player {} joined room {}", player_id_str, room_id_str);

        Ok(())
    }

    pub async fn leave_room(&self, player_id_str: &str) -> Option<RoomId> {
        let room_id = {
            let res = self.player_rooms.remove(player_id_str);
            match res {
                Some((_, id)) => id,
                None => return None,
            }
        };

        if let Some(mut room) = self.rooms.get_mut(&room_id) {
            room.players.retain(|p| p.player_id != player_id_str);
        }

        // Persist leave synchronously so DB state is not silently lost on process/network hiccups.
        if let (Ok(r_uuid), Ok(p_uuid)) =
            (uuid::Uuid::parse_str(&room_id), uuid::Uuid::parse_str(player_id_str))
        {
            if let Err(e) = sqlx::query(
                "UPDATE room_members SET member_status = 'LEFT', left_at = now() 
                 WHERE room_id = $1 AND player_id = $2"
            )
            .bind(r_uuid)
            .bind(p_uuid)
            .execute(&self.db)
            .await
            {
                tracing::error!(
                    "leave_room DB update failed for player={} room={}: {}",
                    player_id_str,
                    room_id,
                    e
                );
            }
        }

        tracing::info!("Player {} left room {}", player_id_str, room_id);
        Some(room_id)
    }

    pub async fn load_room_members(&self, room_id_str: &str) -> Vec<PlayerInfo> {
        let room_uuid = match uuid::Uuid::parse_str(room_id_str) {
            Ok(u) => u,
            Err(_) => return vec![],
        };

        #[derive(sqlx::FromRow)]
        struct MemberRow {
            player_id: uuid::Uuid,
            username: String,
            owner_id: uuid::Uuid,
        }

        let rows = sqlx::query_as::<_, MemberRow>(
            r#"
            SELECT rm.player_id, p.username, r.owner_id
            FROM room_members rm
            JOIN players p ON p.player_id = rm.player_id
            JOIN rooms r ON r.room_id = rm.room_id
            WHERE rm.room_id = $1 AND rm.member_status = 'JOINED'
            ORDER BY rm.joined_at ASC
            "#
        )
        .bind(room_uuid)
        .fetch_all(&self.db)
        .await
        .unwrap_or_default();

        rows.into_iter().map(|r| PlayerInfo {
            player_id: r.player_id.to_string(),
            username: r.username,
            is_ready: false,
            is_host: r.player_id == r.owner_id,
        }).collect()
    }

    pub fn broadcast_to_room(&self, room_id: &str, message: &str) {
        if let Some(room) = self.rooms.get(room_id) {
            for player in &room.players {
                if let Some(tx) = self.connections.get(&player.player_id) {
                    let _ = tx.send(Message::Text(message.to_string()));
                }
            }
        }
    }

    pub fn get_room_state(&self, room_id: &str) -> Option<serde_json::Value> {
        self.rooms.get(room_id).map(|room| {
            let runtime = self.active_games.get(room_id).map(|g| {
                serde_json::json!({
                    "phase": g.phase,
                    "dayNo": g.day_no,
                    "nightNo": g.night_no,
                    "aliveCount": g.players.values().filter(|p| p.alive).count(),
                    "phaseDeadlineAt": g.phase_deadline_at,
                })
            });
            let quickplay_deadline_unix = self
                .quickplay_countdown_deadlines
                .get(room_id)
                .map(|d| *d);

            serde_json::json!({
                "roomId": room.room_id,
                "players": room.players.iter().map(|p| serde_json::json!({
                    "playerId": p.player_id,
                    "username": p.username,
                    "isReady": p.is_ready,
                    "isHost": p.is_host,
                })).collect::<Vec<_>>(),
                "maxPlayers": room.max_players,
                "isPublic": room.is_public,
                "status": room.status,
                "runtime": runtime,
                "quickplayDeadlineUnix": quickplay_deadline_unix,
            })
        })
    }

    async fn assign_roles_for_players(
        &self,
        players: &[PlayerInfo],
    ) -> Result<(HashMap<PlayerId, String>, Vec<String>), String> {
        let player_count = players.len();
        if player_count == 0 {
            return Err("Cannot assign roles for empty room".to_string());
        }

        #[derive(sqlx::FromRow)]
        struct RoleRow {
            role_name: String,
        }

        let db_roles = sqlx::query_as::<_, RoleRow>(
            "SELECT role_name FROM roles ORDER BY role_id ASC"
        )
        .fetch_all(&self.db)
        .await
        .unwrap_or_default();

        let mut unique_pool = Vec::<String>::new();
        let mut seen = HashSet::<String>::new();
        for r in db_roles {
            let role = r.role_name.trim().to_string();
            if role.is_empty() {
                continue;
            }
            if seen.insert(role.clone()) {
                unique_pool.push(role);
            }
        }
        if unique_pool.is_empty() {
            unique_pool = Self::DEFAULT_ROLE_POOL_16
                .iter()
                .map(|r| (*r).to_string())
                .collect();
        }
        if unique_pool.len() < player_count {
            return Err(format!(
                "Not enough unique roles in pool: need {}, have {}",
                player_count,
                unique_pool.len()
            ));
        }

        let mut rng = rand::thread_rng();
        unique_pool.shuffle(&mut rng);
        let mut selected = unique_pool.into_iter().take(player_count).collect::<Vec<_>>();

        // For 2-player test games, force opposite factions to avoid immediate parity end.
        if player_count == 2 {
            let ghost_idx = selected.iter().position(|r| {
                matches!(
                    r.as_str(),
                    "ผีปอบ" | "ผีกระสือใหญ่" | "ผีตายโหง" | "ผีเปรต" | "หมอผีดำ"
                )
            });
            let villager_idx = selected.iter().position(|r| {
                !matches!(
                    r.as_str(),
                    "ผีปอบ" | "ผีกระสือใหญ่" | "ผีตายโหง" | "ผีเปรต" | "หมอผีดำ"
                )
            });
            if ghost_idx.is_none() || villager_idx.is_none() {
                selected = vec!["ชาวบ้าน".to_string(), "ผีปอบ".to_string()];
            }
        }

        let mut by_player = HashMap::<PlayerId, String>::new();
        for (idx, p) in players.iter().enumerate() {
            by_player.insert(p.player_id.clone(), selected[idx].clone());
        }
        Ok((by_player, selected))
    }

    pub async fn start_game(&self, room_id: &str, host_id: &str) -> Result<serde_json::Value, String> {
        let room_snapshot = self
            .rooms
            .get(room_id)
            .ok_or_else(|| "Room not found".to_string())?;

        if room_snapshot.status != "waiting" {
            return Err("Room is not in waiting state".to_string());
        }

        let host_ok = room_snapshot
            .players
            .iter()
            .find(|p| p.player_id == host_id)
            .map(|p| p.is_host)
            .unwrap_or(false);
        if !host_ok {
            return Err("Only host can start game".to_string());
        }

        if room_snapshot.players.len() < 2 {
            return Err("Need at least 2 players to start".to_string());
        }
        if room_snapshot.players.len() > 16 {
            return Err("Max 16 players".to_string());
        }

        let players = room_snapshot.players.clone();
        drop(room_snapshot);

        let (roles_by_player, selected_role_pool) = self.assign_roles_for_players(&players).await?;

        let mut runtime_players = HashMap::new();
        for p in &players {
            runtime_players.insert(
                p.player_id.clone(),
                RuntimePlayerState {
                    alive: true,
                    role: roles_by_player.get(&p.player_id).cloned(),
                },
            );
        }

        let now = Self::now_unix_secs();
        let mut karma_targets = HashMap::<PlayerId, PlayerId>::new();
        for p in &players {
            let role = roles_by_player
                .get(&p.player_id)
                .map(|s| s.as_str())
                .unwrap_or("");
            if role != "เจ้ากรรมนายเวร" {
                continue;
            }
            if let Some(target) = players.iter().find(|candidate| candidate.player_id != p.player_id) {
                karma_targets.insert(p.player_id.clone(), target.player_id.clone());
            }
        }
        let game = RuntimeGame {
            room_id: room_id.to_string(),
            phase: RuntimePhase::Night,
            day_no: 1,
            night_no: 1,
            players: runtime_players,
            actions: HashMap::new(),
            votes: HashMap::new(),
            skill_usage: HashMap::new(),
            karma_targets,
            seen_request_ids: HashSet::new(),
            phase_started_at: now,
            phase_deadline_at: now + self.night_phase_secs as i64,
        };

        if let Some(mut room) = self.rooms.get_mut(room_id) {
            room.status = "playing".to_string();
        }
        self.active_games.insert(room_id.to_string(), game);

        Ok(serde_json::json!({
            "roomId": room_id,
            "phase": RuntimePhase::Night,
            "dayNo": 1,
            "nightNo": 1,
            "phaseDeadlineAt": now + self.night_phase_secs as i64,
            "rolePool": selected_role_pool,
            "rolesByPlayerId": roles_by_player
        }))
    }

    pub fn submit_action(
        &self,
        room_id: &str,
        actor_id: &str,
        request_id: &str,
        action_type: &str,
        target_id: Option<String>,
    ) -> Result<Option<serde_json::Value>, String> {
        let mut game = self
            .active_games
            .get_mut(room_id)
            .ok_or_else(|| "No active game for room".to_string())?;

        if game.phase != RuntimePhase::Night {
            return Err("submit_action allowed only during night".to_string());
        }

        if !game.players.contains_key(actor_id) {
            return Err("Player is not part of this game".to_string());
        }

        if game.phase_deadline_at <= Self::now_unix_secs() {
            let (payload, _) = self.advance_phase_internal(&mut game, "deadline_elapsed_inline")?;
            return Ok(Some(payload));
        }

        if game.seen_request_ids.contains(request_id) {
            return Err("Duplicate request_id".to_string());
        }
        game.seen_request_ids.insert(request_id.to_string());

        let actor_alive = game
            .players
            .get(actor_id)
            .map(|p| p.alive)
            .unwrap_or(false);
        if !actor_alive {
            return Err("Dead player cannot submit action".to_string());
        }

        if game.actions.contains_key(actor_id) {
            return Err("Player already submitted action this night".to_string());
        }

        let actor_role = game
            .players
            .get(actor_id)
            .and_then(|p| p.role.as_deref())
            .unwrap_or("");
        if !Self::role_has_night_action(actor_role) {
            return Err("This role has no active night action".to_string());
        }
        let canonical_action = Self::canonical_night_action_for_role(actor_role, action_type)
            .ok_or_else(|| format!("Unsupported actionType '{}' for role '{}'", action_type, actor_role))?;

        if let Some(ref target) = target_id {
            if !game.players.contains_key(target) {
                return Err("Invalid target player".to_string());
            }
        }

        game.actions.insert(
            actor_id.to_string(),
            RuntimeAction {
                action_type: canonical_action,
                target_id,
            },
        );

        let expected_actors = game
            .players
            .iter()
            .filter(|(_, p)| p.alive)
            .filter(|(_, p)| {
                p.role
                    .as_deref()
                    .map(Self::role_has_night_action)
                    .unwrap_or(false)
            })
            .count();
        if expected_actors > 0 && game.actions.len() >= expected_actors {
            let (payload, _) =
                self.advance_phase_internal(&mut game, "all_actions_submitted")?;
            return Ok(Some(payload));
        }

        Ok(None)
    }

    pub fn submit_vote(
        &self,
        room_id: &str,
        voter_id: &str,
        request_id: &str,
        target_id: &str,
    ) -> Result<Option<serde_json::Value>, String> {
        let mut game = self
            .active_games
            .get_mut(room_id)
            .ok_or_else(|| "No active game for room".to_string())?;

        if game.phase != RuntimePhase::Voting {
            return Err("vote allowed only during voting phase".to_string());
        }

        if game.phase_deadline_at <= Self::now_unix_secs() {
            let (payload, _) = self.advance_phase_internal(&mut game, "deadline_elapsed_inline")?;
            return Ok(Some(payload));
        }

        if game.seen_request_ids.contains(request_id) {
            return Err("Duplicate request_id".to_string());
        }
        game.seen_request_ids.insert(request_id.to_string());

        let voter_alive = game
            .players
            .get(voter_id)
            .map(|p| p.alive)
            .unwrap_or(false);
        if !voter_alive {
            return Err("Dead player cannot vote".to_string());
        }

        let target_alive = game
            .players
            .get(target_id)
            .map(|p| p.alive)
            .unwrap_or(false);
        if !target_alive {
            return Err("Target must be alive".to_string());
        }

        if game.votes.contains_key(voter_id) {
            return Err("Player already voted in this round".to_string());
        }

        game.votes
            .insert(voter_id.to_string(), target_id.to_string());

        let alive_count = game.players.values().filter(|p| p.alive).count();
        if alive_count > 0 && game.votes.len() >= alive_count {
            let (payload, _) = self.advance_phase_internal(&mut game, "all_votes_submitted")?;
            return Ok(Some(payload));
        }

        Ok(None)
    }

    pub fn validate_chat_sender(&self, room_id: &str, sender_id: &str) -> Result<(), String> {
        let game = self
            .active_games
            .get(room_id)
            .ok_or_else(|| "No active game for room".to_string())?;

        if game.phase != RuntimePhase::Day {
            return Err("Global chat allowed only during day".to_string());
        }

        let sender_alive = game
            .players
            .get(sender_id)
            .map(|p| p.alive)
            .unwrap_or(false);
        if !sender_alive {
            return Err("Dead player cannot chat".to_string());
        }

        Ok(())
    }

    pub fn broadcast_to_alive_in_room(&self, room_id: &str, message: &str) {
        if let Some(room) = self.rooms.get(room_id) {
            let runtime = self.active_games.get(room_id);
            for player in &room.players {
                let alive = runtime
                    .as_ref()
                    .and_then(|g| g.players.get(&player.player_id).map(|s| s.alive))
                    .unwrap_or(true);
                if !alive {
                    continue;
                }
                if let Some(tx) = self.connections.get(&player.player_id) {
                    let _ = tx.send(Message::Text(message.to_string()));
                }
            }
        }
    }

    pub fn advance_phase(&self, room_id: &str, host_id: &str) -> Result<serde_json::Value, String> {
        let mut game = self
            .active_games
            .get_mut(room_id)
            .ok_or_else(|| "No active game for room".to_string())?;
        let room = self
            .rooms
            .get(room_id)
            .ok_or_else(|| "Room not found".to_string())?;
        if !room.players.iter().any(|p| p.player_id == host_id) {
            return Err("Player is not part of this room".to_string());
        }

        let (payload, _) = self.advance_phase_internal(&mut game, "host_advanced")?;
        Ok(payload)
    }

    fn advance_phase_internal(
        &self,
        game: &mut RuntimeGame,
        transition_trigger: &str,
    ) -> Result<(serde_json::Value, Option<String>), String> {
        let mut eliminated: Option<String> = None;
        let mut extra_eliminated: Option<String> = None;
        let previous_phase = game.phase.clone();
        let mut night_action_summary = serde_json::json!({
            "totalActions": 0,
            "actionsByType": {},
            "killTargets": [],
            "protected": [],
            "revived": [],
            "transformed": [],
            "cursed": [],
        });

        match game.phase {
            RuntimePhase::Night => {
                let mut engine_players: HashMap<String, EnginePlayerState> = HashMap::new();
                for (pid, state) in game.players.iter() {
                    engine_players.insert(
                        pid.clone(),
                        EnginePlayerState {
                            alive: state.alive,
                            role: state.role.clone().unwrap_or_else(|| "ชาวบ้าน".to_string()),
                            cursed_silenced_today: false,
                        },
                    );
                }

                let mut engine_actions: Vec<EngineNightAction> = Vec::new();
                for (actor_id, action) in game.actions.iter() {
                    let mapped = match action.action_type.to_lowercase().as_str() {
                        "ghost_kill" => Some(NightActionType::GhostKill),
                        "serial_kill" => Some(NightActionType::SerialKill),
                        "seer_check" => Some(NightActionType::SeerCheck),
                        "police_check" => Some(NightActionType::PoliceCheck),
                        "aura_check" => Some(NightActionType::MonkAura),
                        "doctor_protect" | "protect" => Some(NightActionType::DoctorProtect),
                        "soldier_guard" | "guard" => Some(NightActionType::SoldierGuard),
                        "dark_protect" => Some(NightActionType::DarkProtect),
                        "dark_curse" => Some(NightActionType::DarkCurse),
                        "witch_revive" => Some(NightActionType::WitchRevive),
                        "witch_poison" => Some(NightActionType::WitchPoison),
                        "kill" => {
                            let role = game
                                .players
                                .get(actor_id)
                                .and_then(|p| p.role.as_deref())
                                .unwrap_or("");
                            if role == "ฆาตกรต่อเนื่อง" {
                                Some(NightActionType::SerialKill)
                            } else {
                                Some(NightActionType::GhostKill)
                            }
                        }
                        _ => None,
                    };
                    if let Some(action_type) = mapped {
                        engine_actions.push(EngineNightAction {
                            actor_id: actor_id.clone(),
                            action: action_type,
                            target_id: action.target_id.clone(),
                        });
                    }
                }

                let resolution = resolve_night(
                    &mut engine_players,
                    &engine_actions,
                    &mut game.skill_usage,
                );

                for (pid, ep) in engine_players {
                    if let Some(rp) = game.players.get_mut(&pid) {
                        rp.alive = ep.alive;
                        rp.role = Some(ep.role);
                    }
                }
                eliminated = resolution.deaths.first().cloned();
                let total_actions = game.actions.len();
                game.actions.clear();
                game.phase = RuntimePhase::Day;
                game.day_no += 1;
                night_action_summary = serde_json::json!({
                    "totalActions": total_actions,
                    "actionsByType": resolution.actions_by_type,
                    "killTargets": resolution.deaths,
                    "protected": resolution.protected,
                    "revived": resolution.revived,
                    "transformed": resolution.transformed,
                    "cursed": resolution.cursed,
                });
            }
            RuntimePhase::Day => {
                game.phase = RuntimePhase::Voting;
                game.votes.clear();
            }
            RuntimePhase::Voting => {
                match VoteResolver::tally(&game.votes) {
                    VoteOutcome::Execute { victim_id } => {
                        if let Some(v) = game.players.get_mut(&victim_id) {
                            v.alive = false;
                            eliminated = Some(victim_id);
                        }
                    }
                    VoteOutcome::NoExecution => {}
                }
                if let Some(executed_id) = eliminated.clone() {
                    let executed_role = game
                        .players
                        .get(&executed_id)
                        .and_then(|p| p.role.clone())
                        .unwrap_or_default();
                    if executed_role == "ผีตายโหง" {
                        let extra_target = game
                            .players
                            .iter()
                            .find(|(pid, p)| **pid != executed_id && p.alive)
                            .map(|(pid, _)| pid.clone());
                        if let Some(target_id) = extra_target {
                            if let Some(extra) = game.players.get_mut(&target_id) {
                                extra.alive = false;
                                extra_eliminated = Some(target_id.clone());
                            }
                        }
                    }
                }
                game.votes.clear();
                game.night_no += 1;
                game.phase = RuntimePhase::Night;
            }
            RuntimePhase::Lobby | RuntimePhase::End => {
                return Err("Cannot advance phase in current state".to_string());
            }
        }

        let mut engine_players: HashMap<String, EnginePlayerState> = HashMap::new();
        for (pid, state) in game.players.iter() {
            engine_players.insert(
                pid.clone(),
                EnginePlayerState {
                    alive: state.alive,
                    role: state.role.clone().unwrap_or_else(|| "ชาวบ้าน".to_string()),
                    cursed_silenced_today: false,
                },
            );
        }
        let karma_win = game.karma_targets.iter().any(|(karma_id, target_id)| {
            let karma_alive = game.players.get(karma_id).map(|p| p.alive).unwrap_or(false);
            let target_dead = game.players.get(target_id).map(|p| !p.alive).unwrap_or(false);
            karma_alive && target_dead
        });
        if karma_win || engine_check_win(&engine_players).is_some() {
            game.phase = RuntimePhase::End;
        }

        let now = Self::now_unix_secs();
        game.phase_started_at = now;
        game.phase_deadline_at = match game.phase {
            RuntimePhase::Night => now + self.night_phase_secs as i64,
            RuntimePhase::Day => now + self.day_phase_secs as i64,
            RuntimePhase::Voting => now + self.voting_phase_secs as i64,
            RuntimePhase::End | RuntimePhase::Lobby => now,
        };

        let winner_kind = if game.phase == RuntimePhase::End {
            Self::winner_kind_for_phase_end(game)
        } else {
            None
        };

        Ok((
            serde_json::json!({
                "roomId": game.room_id,
                "phase": game.phase,
                "previousPhase": previous_phase,
                "transitionTrigger": transition_trigger,
                "dayNo": game.day_no,
                "nightNo": game.night_no,
                "eliminatedPlayerId": eliminated,
                "extraEliminatedPlayerId": extra_eliminated,
                "nightActionSummary": night_action_summary,
                "phaseDeadlineAt": game.phase_deadline_at,
                "winnerKind": winner_kind,
            }),
            eliminated,
        ))
    }

    pub fn tick_games(&self) {
        let now = Self::now_unix_secs();
        let mut to_broadcast: Vec<(String, String)> = Vec::new();
        let mut ended_rooms: Vec<String> = Vec::new();
        let mut progressed_rooms: Vec<String> = Vec::new();

        for mut entry in self.active_games.iter_mut() {
            if entry.phase == RuntimePhase::End || entry.phase_deadline_at > now {
                continue;
            }

            if let Ok((phase_payload, _)) = self.advance_phase_internal(&mut entry, "deadline_elapsed") {
                let phase_msg = serde_json::json!({
                    "type": "game.phase_changed",
                    "payload": phase_payload,
                    "req_id": serde_json::Value::Null
                });
                to_broadcast.push((entry.room_id.clone(), phase_msg.to_string()));
                progressed_rooms.push(entry.room_id.clone());

                if entry.phase == RuntimePhase::End {
                    ended_rooms.push(entry.room_id.clone());
                }
            }
        }

        // Important: call get_room_state only after iter_mut loop ends.
        // Doing it inside the loop can re-enter active_games while a mutable
        // shard ref is held, causing intermittent deadlocks and frozen phases.
        for room_id in progressed_rooms {
            if let Some(room_state) = self.get_room_state(&room_id) {
                let state_msg = serde_json::json!({
                    "type": "room.state",
                    "payload": room_state,
                    "req_id": serde_json::Value::Null
                });
                to_broadcast.push((room_id, state_msg.to_string()));
            }
        }

        for (room_id, msg) in to_broadcast {
            self.broadcast_to_room(&room_id, &msg);
        }

        for room_id in ended_rooms {
            if let Some(mut room) = self.rooms.get_mut(&room_id) {
                room.status = "ended".to_string();
            }
        }
    }

    pub fn tick_room(&self, room_id: &str) -> Option<serde_json::Value> {
        let now = Self::now_unix_secs();
        let mut game = self.active_games.get_mut(room_id)?;
        if game.phase == RuntimePhase::End || game.phase_deadline_at > now {
            return None;
        }
        let (phase_payload, _) = self
            .advance_phase_internal(&mut game, "deadline_elapsed")
            .ok()?;
        if game.phase == RuntimePhase::End {
            if let Some(mut room) = self.rooms.get_mut(room_id) {
                room.status = "ended".to_string();
            }
        }
        Some(phase_payload)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use sqlx::postgres::PgPoolOptions;

    fn test_state() -> Arc<AppState> {
        let db = PgPoolOptions::new()
            .connect_lazy("postgres://postgres:postgres@localhost/postgres")
            .expect("lazy pool");
        AppState::new(db, "test-secret".to_string(), 90, 180, 120, 90)
    }

    fn seed_room(state: &Arc<AppState>, room_id: &str, host_id: &str, host_name: &str) {
        state.rooms.insert(
            room_id.to_string(),
            Room {
                room_id: room_id.to_string(),
                players: vec![PlayerInfo {
                    player_id: host_id.to_string(),
                    username: host_name.to_string(),
                    is_ready: false,
                    is_host: true,
                }],
                max_players: 16,
                is_public: true,
                status: "waiting".to_string(),
            },
        );
    }

    #[tokio::test]
    async fn start_game_requires_min_two_players() {
        let state = test_state();
        let room_id = "room-min-players";
        let host_id = "host-1";
        seed_room(&state, room_id, host_id, "host");

        let err = state
            .start_game(room_id, host_id)
            .await
            .expect_err("should reject single player start");
        assert!(err.contains("Need at least 2 players"));
    }

    #[tokio::test]
    async fn start_game_requires_host() {
        let state = test_state();
        let room_id = "room-host-check";
        let host_id = "host-1";
        seed_room(&state, room_id, host_id, "host");
        if let Some(mut room) = state.rooms.get_mut(room_id) {
            room.players.push(PlayerInfo {
                player_id: "player-2".to_string(),
                username: "guest".to_string(),
                is_ready: false,
                is_host: false,
            });
        }

        let err = state
            .start_game(room_id, "player-2")
            .await
            .expect_err("non-host should fail");
        assert!(err.contains("Only host can start game"));
    }

    #[tokio::test]
    async fn start_game_sets_room_playing_and_runtime_created() {
        let state = test_state();
        let room_id = "room-start-success";
        let host_id = "host-1";
        seed_room(&state, room_id, host_id, "host");
        if let Some(mut room) = state.rooms.get_mut(room_id) {
            room.players.push(PlayerInfo {
                player_id: "player-2".to_string(),
                username: "guest".to_string(),
                is_ready: false,
                is_host: false,
            });
        }

        let payload = state.start_game(room_id, host_id).await.expect("start game success");
        assert_eq!(payload["roomId"], room_id);
        assert_eq!(payload["nightNo"], 1);
        assert!(state.active_games.contains_key(room_id));

        let room = state.rooms.get(room_id).expect("room exists");
        assert_eq!(room.status, "playing");
    }

    #[test]
    fn canonical_night_action_preserves_engine_ids() {
        assert_eq!(
            AppState::canonical_night_action_for_role("ผีปอบ", "ghost_kill"),
            Some("ghost_kill".to_string())
        );
        assert_eq!(
            AppState::canonical_night_action_for_role("ร่างทรง", "seer_check"),
            Some("seer_check".to_string())
        );
        assert_eq!(
            AppState::canonical_night_action_for_role("ผีปอบ", "pass"),
            Some("pass".to_string())
        );
    }

    /// Smoke: one ghost night kill → Night ends → Day; victim dead (2-player forced villager+ghost).
    #[tokio::test]
    async fn night_submit_ghost_kill_advances_to_day() {
        let state = test_state();
        let room_id = "room-night-smoke";
        let host_id = "host-1";
        seed_room(&state, room_id, host_id, "host");
        if let Some(mut room) = state.rooms.get_mut(room_id) {
            room.players.push(PlayerInfo {
                player_id: "player-2".to_string(),
                username: "guest".to_string(),
                is_ready: false,
                is_host: false,
            });
        }

        state.start_game(room_id, host_id).await.expect("start");

        // Deterministic roles (DB shuffle is not guaranteed in tests).
        let ghost_id = host_id.to_string();
        let villager_id = "player-2".to_string();
        {
            let mut game = state.active_games.get_mut(room_id).expect("runtime game");
            if let Some(p) = game.players.get_mut(&ghost_id) {
                p.role = Some("ผีปอบ".to_string());
                p.alive = true;
            }
            if let Some(p) = game.players.get_mut(&villager_id) {
                p.role = Some("ชาวบ้าน".to_string());
                p.alive = true;
            }
            game.karma_targets.clear();
        }

        let phase = state
            .submit_action(
                room_id,
                &ghost_id,
                "smoke-req-1",
                "ghost_kill",
                Some(villager_id.clone()),
            )
            .expect("submit")
            .expect("night should resolve when required actors submit");

        let phase_str = phase["phase"].as_str().expect("phase as string");
        // After kill, only ghost may remain → win check can jump straight to End.
        assert!(
            matches!(phase_str, "Day" | "End"),
            "unexpected phase after night: {phase_str}"
        );
        let g2 = state.active_games.get(room_id).expect("game still there");
        assert!(!g2.players[&villager_id].alive);
        assert!(g2.players[&ghost_id].alive);
        if phase_str == "End" {
            assert_eq!(phase["winnerKind"].as_str(), Some("ghosts"));
        }
    }
}
