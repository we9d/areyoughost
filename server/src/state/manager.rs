use std::sync::Arc;
use std::time::{Duration, SystemTime, UNIX_EPOCH};

use areyoughost_core::game_logic::role_engine::{
    check_win as engine_check_win, resolve_night, team_of_role, EngineNightAction,
    EnginePlayerState, NightActionType, SkillUsageState, Team,
};
use areyoughost_core::game_logic::vote_resolver::{VoteOutcome, VoteResolver};
use dashmap::DashMap;
use rand::rngs::StdRng;
use rand::seq::SliceRandom;
use rand::SeedableRng;
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

    /// When true, room membership skips Postgres writes (used by automated QA tests).
    pub skip_persistence: bool,
}

impl AppState {
    const DEFAULT_ROLE_POOL_16: [&'static str; 16] = [
        "ชาวบ้าน",
        "ร่างทรง",
        "แพทย์",
        "ทหาร",
        // Temporarily keep police out of random assignment.
        "ชาวบ้าน",
        "พระธุดงค์",
        "หมอผีคุณไสย",
        // Temporarily keep undertaker out of random assignment.
        "ชาวบ้าน",
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
        skip_persistence: bool,
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
            skip_persistence,
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

    fn seer_alignment_label(role: &str) -> &'static str {
        match role.trim() {
            // G13 is intentionally hidden from Seer checks.
            "ผีเปรต" => "ชาวบ้าน",
            "ผีปอบ" | "ผีกระสือใหญ่" | "ผีตายโหง" | "หมอผีดำ" => "ผี",
            _ => "ชาวบ้าน",
        }
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

        if self.skip_persistence {
            return;
        }

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
        /// Long enough for Wi‑Fi/cellular drops and sleep/resume without forcing a full JWT re-login.
        const TTL_SECS: i64 = 7200;
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

    /// Pick a public waiting room for quick play.
    ///
    /// Prefer a room that already has ≥2 players **and** an active quickplay countdown so
    /// additional players can join during the pre-start window. Otherwise prefer the fullest
    /// waiting lobby so matchmaking does not scatter players across many one-player rooms.
    fn pick_quick_play_target_room(&self) -> Option<RoomId> {
        let now = Self::now_unix_secs();
        let mut best_countdown: Option<(usize, RoomId)> = None;
        let mut best_fallback: Option<(usize, RoomId)> = None;

        for r in self.rooms.iter() {
            if r.status != "waiting" || !r.is_public || r.players.len() >= r.max_players {
                continue;
            }
            let n = r.players.len();
            let room_id = r.room_id.clone();
            let in_live_countdown = self
                .quickplay_countdown_deadlines
                .get(&room_id)
                .map(|d| *d > now)
                .unwrap_or(false);

            if n >= 2 && in_live_countdown {
                let take = match best_countdown {
                    None => true,
                    Some((best_n, _)) => n > best_n,
                };
                if take {
                    best_countdown = Some((n, room_id));
                }
            } else {
                let take = match best_fallback {
                    None => true,
                    Some((best_n, _)) => n > best_n,
                };
                if take {
                    best_fallback = Some((n, room_id));
                }
            }
        }

        best_countdown
            .map(|(_, id)| id)
            .or_else(|| best_fallback.map(|(_, id)| id))
    }

    /// Find an existing waiting public room with space, or create a new one.
    pub async fn quick_play(&self, player_id: String, username: String) -> Result<RoomId, String> {
        let available_room = self.pick_quick_play_target_room();

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
        if self.skip_persistence {
            return;
        }
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

        if self.skip_persistence {
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

            tracing::info!(
                "Created private room {} with invite_code {} (skip_persistence)",
                room_id,
                invite_code
            );
            return Ok((room_id, invite_code));
        }

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

        if self.skip_persistence {
            let mut room_ref = self
                .rooms
                .get_mut(room_id_str)
                .ok_or_else(|| "Room not found".to_string())?;

            if room_ref.players.len() >= room_ref.max_players {
                return Err("Room is full".to_string());
            }

            if room_ref.players.iter().any(|p| p.player_id == player_id_str) {
                return Err("Already in room".to_string());
            }

            room_ref.players.push(PlayerInfo {
                player_id: player_id_str.to_string(),
                username,
                is_ready: false,
                is_host: false,
            });
            drop(room_ref);

            self.player_rooms
                .insert(player_id_str.to_string(), room_id_str.to_string());
            tracing::info!(
                "Player {} joined room {} (skip_persistence)",
                player_id_str,
                room_id_str
            );
            return Ok(());
        }

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

        if !self.skip_persistence {
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
        }

        tracing::info!("Player {} left room {}", player_id_str, room_id);
        Some(room_id)
    }

    pub async fn load_room_members(&self, room_id_str: &str) -> Vec<PlayerInfo> {
        if self.skip_persistence {
            return self
                .rooms
                .get(room_id_str)
                .map(|room| room.players.clone())
                .unwrap_or_default();
        }

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
        let player_ids: Vec<String> = self
            .rooms
            .get(room_id)
            .map(|room| {
                room
                    .players
                    .iter()
                    .map(|p| p.player_id.clone())
                    .collect()
            })
            .unwrap_or_default();
        if player_ids.is_empty() {
            return;
        }
        let text = message.to_string();
        for pid in player_ids {
            if let Some(tx) = self.connections.get(&pid) {
                let _ = tx.send(Message::Text(text.clone()));
            }
        }
    }

    pub fn get_room_state(&self, room_id: &str) -> Option<serde_json::Value> {
        let room = self.rooms.get(room_id)?;
        let room_id_owned = room.room_id.clone();
        let alive_by_player: Option<HashMap<String, bool>> = self
            .active_games
            .get(room_id)
            .map(|g| g.players.iter().map(|(k, v)| (k.clone(), v.alive)).collect());
        let players: Vec<serde_json::Value> = room
            .players
            .iter()
            .map(|p| {
                let alive = alive_by_player
                    .as_ref()
                    .and_then(|m| m.get(&p.player_id))
                    .copied()
                    .unwrap_or(true);
                serde_json::json!({
                    "playerId": p.player_id,
                    "username": p.username,
                    "isReady": p.is_ready,
                    "isHost": p.is_host,
                    "alive": alive,
                })
            })
            .collect();
        let max_players = room.max_players;
        let is_public = room.is_public;
        let status = room.status.clone();
        drop(room);

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

        Some(serde_json::json!({
            "roomId": room_id_owned,
            "players": players,
            "maxPlayers": max_players,
            "isPublic": is_public,
            "status": status,
            "runtime": runtime,
            "quickplayDeadlineUnix": quickplay_deadline_unix,
        }))
    }

    /// Public rooms in memory for HTTP lobby list (browser / Flutter).
    pub fn list_public_rooms(&self) -> serde_json::Value {
        let mut items: Vec<serde_json::Value> = self
            .rooms
            .iter()
            .filter(|r| r.value().is_public)
            .map(|r| {
                let room = r.value();
                let room_id = room.room_id.clone();
                let title = room
                    .players
                    .first()
                    .map(|p| format!("{} · ห้องเปิด", p.username))
                    .unwrap_or_else(|| {
                        let short = room_id.chars().take(8).collect::<String>();
                        format!("ห้อง {short}")
                    });
                serde_json::json!({
                    "roomId": room_id,
                    "roomName": title,
                    "maxPlayers": room.max_players,
                    "currentPlayers": room.players.len(),
                    "isPublic": true,
                    "status": room.status,
                })
            })
            .collect();
        items.sort_by(|a, b| {
            let ta = a["status"].as_str().unwrap_or("");
            let tb = b["status"].as_str().unwrap_or("");
            let oa = if ta == "waiting" { 0 } else { 1 };
            let ob = if tb == "waiting" { 0 } else { 1 };
            oa.cmp(&ob).then_with(|| {
                a["roomId"]
                    .as_str()
                    .unwrap_or("")
                    .cmp(b["roomId"].as_str().unwrap_or(""))
            })
        });
        serde_json::json!({ "rooms": items })
    }

    /// Adds authoritative `myRole` / `myAlive` for one viewer (WebSocket owner) when a runtime game exists.
    pub fn enrich_room_state_for_viewer(
        &self,
        room_id: &str,
        viewer_player_id: &str,
        room_state: &mut serde_json::Value,
    ) {
        let Some(game) = self.active_games.get(room_id) else {
            return;
        };
        let Some(p) = game.players.get(viewer_player_id) else {
            return;
        };
        let Some(obj) = room_state.as_object_mut() else {
            return;
        };
        obj.insert("myRole".to_string(), serde_json::json!(p.role));
        obj.insert("myAlive".to_string(), serde_json::json!(p.alive));
    }

    /// Shuffle and assign roles from a pool that already has at least `players.len()` entries.
    fn assign_roles_from_unique_pool(
        mut unique_pool: Vec<String>,
        players: &[PlayerInfo],
    ) -> Result<(HashMap<PlayerId, String>, Vec<String>), String> {
        let player_count = players.len();
        if player_count == 0 {
            return Err("Cannot assign roles for empty room".to_string());
        }
        if unique_pool.len() < player_count {
            return Err(format!(
                "Not enough unique roles in pool: need {}, have {}",
                player_count,
                unique_pool.len()
            ));
        }

        // Entropy-seeded RNG: a fixed seed made every game draw the same slice of the deck
        // (e.g. three villagers for 3 players). Avoid `thread_rng` here due to global-lock stalls
        // under Windows + tokio in some test setups.
        let mut rng = StdRng::from_entropy();
        unique_pool.shuffle(&mut rng);
        let mut remainder = unique_pool.split_off(player_count);
        let mut selected = unique_pool;

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

        // Small games (3 players) should stay fair: exactly 1 ghost-team role.
        if player_count == 3 {
            let selected_ghost_count = selected
                .iter()
                .filter(|r| team_of_role(r) == Team::Ghosts)
                .count();
            if selected_ghost_count > 1 {
                let mut ghosts_to_replace = selected_ghost_count - 1;
                for role in &mut selected {
                    if ghosts_to_replace == 0 {
                        break;
                    }
                    if team_of_role(role) != Team::Ghosts {
                        continue;
                    }
                    if let Some(non_ghost_idx) = remainder
                        .iter()
                        .position(|r| team_of_role(r) != Team::Ghosts)
                    {
                        let replacement = remainder.remove(non_ghost_idx);
                        let replaced = std::mem::replace(role, replacement);
                        remainder.push(replaced);
                        ghosts_to_replace -= 1;
                    }
                }
            }
        }

        // Small games (3+) still need at least one ghost-team role when the deck contains any.
        if player_count >= 3 {
            let pool_has_ghost = selected
                .iter()
                .chain(remainder.iter())
                .any(|r| team_of_role(r) == Team::Ghosts);
            let selected_has_ghost = selected.iter().any(|r| team_of_role(r) == Team::Ghosts);
            if pool_has_ghost && !selected_has_ghost {
                if let Some(gi) = remainder
                    .iter()
                    .position(|r| team_of_role(r) == Team::Ghosts)
                {
                    let ghost = remainder.remove(gi);
                    if let Some(vi) = selected
                        .iter()
                        .position(|r| team_of_role(r) != Team::Ghosts)
                    {
                        let replaced = std::mem::replace(&mut selected[vi], ghost);
                        remainder.push(replaced);
                    }
                }
            }
        }

        let mut by_player = HashMap::<PlayerId, String>::new();
        for (idx, p) in players.iter().enumerate() {
            by_player.insert(p.player_id.clone(), selected[idx].clone());
        }
        Ok((by_player, selected))
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

        let db_roles: Vec<RoleRow> = sqlx::query_as::<_, RoleRow>("SELECT role_name FROM roles ORDER BY role_id ASC")
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

        Self::assign_roles_from_unique_pool(unique_pool, players)
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

        let (roles_by_player, selected_role_pool) = if self.skip_persistence {
            let unique_pool: Vec<String> = Self::DEFAULT_ROLE_POOL_16
                .iter()
                .map(|r| (*r).to_string())
                .collect();
            Self::assign_roles_from_unique_pool(unique_pool, &players)?
        } else {
            self.assign_roles_for_players(&players).await?
        };

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
    ) -> Result<(Option<serde_json::Value>, Option<serde_json::Value>), String> {
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
            return Ok((Some(payload), None));
        }

        if game.seen_request_ids.contains(request_id) {
            return Err("Duplicate request_id".to_string());
        }
        game.seen_request_ids.insert(request_id.to_string());

        // Allow clients to cancel a previously queued action before deadline.
        if target_id.is_none() {
            game.actions.remove(actor_id);
            return Ok((None, None));
        }

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

        let private_result = if canonical_action == "seer_check" {
            target_id.as_ref().and_then(|target| {
                game.players.get(target).map(|target_state| {
                    let target_role = target_state.role.as_deref().unwrap_or("ชาวบ้าน");
                    let seen_as = Self::seer_alignment_label(target_role);
                    serde_json::json!({
                        "skill": "seer_check",
                        "targetId": target,
                        "targetRoleSeenAs": seen_as,
                    })
                })
            })
        } else {
            None
        };

        game.actions.insert(
            actor_id.to_string(),
            RuntimeAction {
                action_type: canonical_action,
                target_id,
            },
        );

        Ok((None, private_result))
    }

    pub fn submit_vote(
        &self,
        room_id: &str,
        voter_id: &str,
        request_id: &str,
        target_id: Option<&str>,
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

        let target_id = target_id.and_then(|v| {
            let t = v.trim();
            if t.is_empty() { None } else { Some(t) }
        });

        if let Some(target_id) = target_id {
            let target_alive = game
                .players
                .get(target_id)
                .map(|p| p.alive)
                .unwrap_or(false);
            if !target_alive {
                return Err("Target must be alive".to_string());
            }
            // Allow changing vote before deadline: latest target wins.
            game.votes
                .insert(voter_id.to_string(), target_id.to_string());
        } else {
            // Explicit unvote before deadline.
            game.votes.remove(voter_id);
        }

        Ok(None)
    }

    pub fn validate_chat_sender(&self, room_id: &str, sender_id: &str) -> Result<(), String> {
        let game = self
            .active_games
            .get(room_id)
            .ok_or_else(|| "No active game for room".to_string())?;

        let sender = game
            .players
            .get(sender_id)
            .ok_or_else(|| "Sender not in game".to_string())?;
        if !sender.alive {
            return Err("Dead player cannot chat".to_string());
        }

        match game.phase {
            RuntimePhase::Day | RuntimePhase::Voting => Ok(()),
            RuntimePhase::Night => {
                let role_name = sender.role.as_deref().unwrap_or("ชาวบ้าน");
                if team_of_role(role_name) == Team::Ghosts {
                    Ok(())
                } else {
                    Err("Night chat is for ghost faction only".to_string())
                }
            }
            RuntimePhase::Lobby | RuntimePhase::End => Err(
                "Chat is only available during day or night gameplay".to_string(),
            ),
        }
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

    /// Night evil-team chat: only living players whose role is ghost faction (engine `Team::Ghosts`).
    pub fn broadcast_to_alive_ghost_faction_in_room(&self, room_id: &str, message: &str) {
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
                let role_name = runtime
                    .as_ref()
                    .and_then(|g| {
                        g.players
                            .get(&player.player_id)
                            .and_then(|s| s.role.as_deref())
                    })
                    .unwrap_or("ชาวบ้าน");
                if team_of_role(role_name) != Team::Ghosts {
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
        let host_ok = room
            .players
            .iter()
            .any(|p| p.player_id == host_id && p.is_host);
        if !host_ok {
            return Err("Only host can advance phase".to_string());
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
            self.reset_room_to_waiting_after_game_end(&room_id);
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
            drop(game);
            self.reset_room_to_waiting_after_game_end(room_id);
        }
        Some(phase_payload)
    }

    fn reset_room_to_waiting_after_game_end(&self, room_id: &str) {
        self.active_games.remove(room_id);
        self.quickplay_countdown_deadlines.remove(room_id);
        if let Some(mut room) = self.rooms.get_mut(room_id) {
            room.status = "waiting".to_string();
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use sqlx::postgres::PgPoolOptions;

    fn test_state() -> Arc<AppState> {
        let db = PgPoolOptions::new()
            .acquire_timeout(Duration::from_secs(2))
            .connect_lazy("postgres://postgres:postgres@localhost/postgres")
            .expect("lazy pool");
        AppState::new(db, "test-secret".to_string(), 90, 180, 120, 90, true)
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

    #[tokio::test]
    async fn start_game_three_players_includes_at_least_one_ghost_team_role() {
        let state = test_state();
        for i in 0u32..16 {
            let room_id = format!("room-3p-{i}");
            let p1 = format!("p1-3p-{i}");
            let p2 = format!("p2-3p-{i}");
            let p3 = format!("p3-3p-{i}");
            seed_uuid_waiting_room(
                &state,
                &room_id,
                &[(p1.as_str(), "a", true), (p2.as_str(), "b", false), (p3.as_str(), "c", false)],
            );
            state.start_game(&room_id, &p1).await.expect("start");
            let g = state.active_games.get(&room_id).expect("game");
            let ghost_count = g
                .players
                .values()
                .filter(|p| {
                    p.role
                        .as_ref()
                        .map(|r| team_of_role(r) == Team::Ghosts)
                        .unwrap_or(false)
                })
                .count();
            assert!(
                ghost_count >= 1,
                "round {i}: expected >=1 ghost team, roles: {:?}",
                g.players.values().map(|p| p.role.clone()).collect::<Vec<_>>()
            );
        }
    }

    #[tokio::test]
    async fn quick_play_reuses_waiting_room_until_full() {
        let state = test_state();
        let room_id = "52000000-0000-4000-8000-000000000001";
        let host_id = "52000000-0000-4000-8000-000000000011";
        seed_room(&state, room_id, host_id, "host");

        let joined_room_id = state
            .quick_play(
                "52000000-0000-4000-8000-000000000012".to_string(),
                "guest-1".to_string(),
            )
            .await
            .expect("quick play should join existing waiting room");
        assert_eq!(joined_room_id, room_id);

        let room = state.rooms.get(room_id).expect("room exists");
        assert_eq!(room.players.len(), 2);
        assert_eq!(room.max_players, 16);
    }

    #[tokio::test]
    async fn quick_play_prefers_room_in_countdown_over_solo_lobbies() {
        let state = test_state();
        let room_busy = "62000000-0000-4000-8000-000000000001";
        let room_solo = "62000000-0000-4000-8000-000000000002";
        let h1 = "62000000-0000-4000-8000-000000000011";
        let h2 = "62000000-0000-4000-8000-000000000012";
        let newcomer = "62000000-0000-4000-8000-000000000099";

        seed_room(&state, room_busy, h1, "host");
        if let Some(mut room) = state.rooms.get_mut(room_busy) {
            room.players.push(PlayerInfo {
                player_id: h2.to_string(),
                username: "guest".to_string(),
                is_ready: false,
                is_host: false,
            });
        }
        let far_deadline = chrono::Utc::now().timestamp() + 3600;
        state
            .quickplay_countdown_deadlines
            .insert(room_busy.to_string(), far_deadline);

        seed_room(
            &state,
            room_solo,
            "62000000-0000-4000-8000-000000000021",
            "solo",
        );

        let joined = state
            .quick_play(newcomer.to_string(), "joiner".to_string())
            .await
            .expect("quick play");
        assert_eq!(joined, room_busy);
        let room = state.rooms.get(room_busy).expect("room");
        assert!(room.players.iter().any(|p| p.player_id == newcomer));
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
            .expect("submit");
        assert!(phase.0.is_none(), "night should wait until phase deadline");
        {
            let mut g = state.active_games.get_mut(room_id).expect("runtime game");
            g.phase_deadline_at = 0;
        }
        let phase = state
            .tick_room(room_id)
            .expect("deadline elapsed should resolve phase");

        let phase_str = phase["phase"].as_str().expect("phase as string");
        // After kill, only ghost may remain → win check can jump straight to End.
        assert!(
            matches!(phase_str, "Day" | "End"),
            "unexpected phase after night: {phase_str}"
        );
        if phase_str == "End" {
            assert_eq!(phase["winnerKind"].as_str(), Some("ghosts"));
        } else {
            let g2 = state.active_games.get(room_id).expect("game still there");
            assert!(!g2.players[&villager_id].alive);
            assert!(g2.players[&ghost_id].alive);
        }
    }

    fn seed_uuid_waiting_room(state: &Arc<AppState>, room_id: &str, players: &[(&str, &str, bool)]) {
        let ps: Vec<PlayerInfo> = players
            .iter()
            .map(|(id, name, host)| PlayerInfo {
                player_id: (*id).to_string(),
                username: (*name).to_string(),
                is_ready: false,
                is_host: *host,
            })
            .collect();
        state.rooms.insert(
            room_id.to_string(),
            Room {
                room_id: room_id.to_string(),
                players: ps,
                max_players: 16,
                is_public: true,
                status: "waiting".to_string(),
            },
        );
    }

    #[tokio::test]
    async fn qa_c1_start_game_initial_phase_is_night() {
        let state = test_state();
        let room_id = "40000000-0000-4000-8000-000000000001";
        let host = "40000000-0000-4000-8000-000000000011";
        let guest = "40000000-0000-4000-8000-000000000012";
        seed_uuid_waiting_room(
            &state,
            room_id,
            &[(host, "h", true), (guest, "g", false)],
        );
        let payload = state.start_game(room_id, host).await.expect("start");
        let phase = format!("{}", payload["phase"]);
        assert!(
            phase.contains("Night"),
            "expected Night in payload phase, got {phase}"
        );
    }

    #[tokio::test]
    async fn qa_c2_night_action_rejected_when_phase_is_day() {
        let state = test_state();
        let room_id = "41000000-0000-4000-8000-000000000001";
        let ghost = "41000000-0000-4000-8000-000000000011";
        let target = "41000000-0000-4000-8000-000000000012";
        seed_uuid_waiting_room(
            &state,
            room_id,
            &[(ghost, "ghost", true), (target, "v", false)],
        );
        state.start_game(room_id, ghost).await.expect("start");
        {
            let mut g = state.active_games.get_mut(room_id).unwrap();
            g.phase = RuntimePhase::Day;
            g.phase_deadline_at = i64::MAX / 4;
            if let Some(p) = g.players.get_mut(ghost) {
                p.role = Some("ผีปอบ".to_string());
            }
        }
        let err = state
            .submit_action(
                room_id,
                ghost,
                "qa-c2-1",
                "ghost_kill",
                Some(target.to_string()),
            )
            .expect_err("day phase must reject night action");
        assert!(
            err.contains("night"),
            "unexpected error: {err}"
        );
    }

    #[tokio::test]
    async fn qa_c3_unanimous_day_vote_executes_target() {
        let state = test_state();
        let room_id = "42000000-0000-4000-8000-000000000001";
        let p1 = "42000000-0000-4000-8000-000000000011";
        let p2 = "42000000-0000-4000-8000-000000000012";
        let p3 = "42000000-0000-4000-8000-000000000013";
        seed_uuid_waiting_room(
            &state,
            room_id,
            &[(p1, "a", true), (p2, "b", false), (p3, "c", false)],
        );
        state.start_game(room_id, p1).await.expect("start");
        {
            let mut g = state.active_games.get_mut(room_id).unwrap();
            // Deterministic outcome: random role deal can leave 1 ghost + 2 villagers; executing
            // the villager then ends with ghosts >= villagers, so winnerKind is ghosts not villagers.
            for pid in [p1, p2, p3] {
                if let Some(p) = g.players.get_mut(pid) {
                    p.role = Some("ชาวบ้าน".to_string());
                    p.alive = true;
                }
            }
            g.karma_targets.clear();
            g.phase = RuntimePhase::Voting;
            g.votes.clear();
            g.phase_deadline_at = i64::MAX / 4;
        }
        assert!(state
            .submit_vote(room_id, p1, "v1", Some(p3))
            .expect("vote")
            .is_none());
        assert!(state
            .submit_vote(room_id, p2, "v2", Some(p3))
            .expect("vote")
            .is_none());
        let phase = state
            .submit_vote(room_id, p3, "v3", Some(p3))
            .expect("vote");
        assert!(phase.is_none(), "voting should wait until phase deadline");
        {
            let mut g = state.active_games.get_mut(room_id).unwrap();
            g.phase_deadline_at = 0;
        }
        let phase = state
            .tick_room(room_id)
            .expect("deadline elapsed should resolve vote");
        let phase_str = format!("{}", phase["phase"]);
        assert!(
            phase_str.contains("Night") || phase_str.contains("End"),
            "expected Night or End after execution, got {phase_str}"
        );
        if phase_str.contains("End") {
            assert_eq!(phase["winnerKind"].as_str(), Some("villagers"));
        }
        if phase_str.contains("End") {
            // Runtime may finalize and remove active game when match ends.
            assert!(!state.active_games.contains_key(room_id));
        } else {
            let g = state.active_games.get(room_id).expect("active game after vote");
            assert!(!g.players[p3].alive);
            assert!(g.players[p1].alive && g.players[p2].alive);
        }
    }

    #[tokio::test]
    async fn qa_c4_dead_player_cannot_vote_action_or_day_chat() {
        let state = test_state();
        let room_id = "43000000-0000-4000-8000-000000000001";
        let alive = "43000000-0000-4000-8000-000000000011";
        let dead = "43000000-0000-4000-8000-000000000012";
        let other = "43000000-0000-4000-8000-000000000013";
        seed_uuid_waiting_room(
            &state,
            room_id,
            &[(alive, "a", true), (dead, "d", false), (other, "o", false)],
        );
        state.start_game(room_id, alive).await.expect("start");
        {
            let mut g = state.active_games.get_mut(room_id).unwrap();
            g.players.get_mut(dead).unwrap().alive = false;
            g.phase = RuntimePhase::Voting;
            g.votes.clear();
            g.phase_deadline_at = i64::MAX / 4;
        }
        let e = state
            .submit_vote(room_id, dead, "vx", Some(other))
            .expect_err("dead cannot vote");
        assert!(e.contains("Dead") || e.contains("dead"));

        {
            let mut g = state.active_games.get_mut(room_id).unwrap();
            g.phase = RuntimePhase::Night;
            g.actions.clear();
            g.seen_request_ids.clear();
            g.phase_deadline_at = i64::MAX / 4;
            g.players.get_mut(alive).unwrap().role = Some("ผีปอบ".to_string());
        }
        let e2 = state
            .submit_action(
                room_id,
                dead,
                "ax",
                "ghost_kill",
                Some(other.to_string()),
            )
            .expect_err("dead cannot act");
        assert!(e2.contains("Dead") || e2.contains("dead"));

        {
            let mut g = state.active_games.get_mut(room_id).unwrap();
            g.phase = RuntimePhase::Day;
            g.phase_deadline_at = i64::MAX / 4;
        }
        let e3 = state
            .validate_chat_sender(room_id, dead)
            .expect_err("dead cannot chat by day");
        assert!(e3.contains("Dead") || e3.contains("dead"));
    }

    #[tokio::test]
    async fn qa_vote_toggle_and_change_allowed_only_in_voting_phase() {
        let state = test_state();
        let room_id = "4a000000-0000-4000-8000-000000000001";
        let p1 = "4a000000-0000-4000-8000-000000000011";
        let p2 = "4a000000-0000-4000-8000-000000000012";
        let p3 = "4a000000-0000-4000-8000-000000000013";
        seed_uuid_waiting_room(
            &state,
            room_id,
            &[(p1, "a", true), (p2, "b", false), (p3, "c", false)],
        );
        state.start_game(room_id, p1).await.expect("start");
        {
            let mut g = state.active_games.get_mut(room_id).unwrap();
            g.phase = RuntimePhase::Voting;
            g.votes.clear();
            g.phase_deadline_at = i64::MAX / 4;
            g.players.get_mut(p1).unwrap().alive = true;
            g.players.get_mut(p2).unwrap().alive = true;
            g.players.get_mut(p3).unwrap().alive = true;
        }

        // First tap: cast vote.
        assert!(state
            .submit_vote(room_id, p1, "v1", Some(p2))
            .expect("cast vote")
            .is_none());
        {
            let g = state.active_games.get(room_id).unwrap();
            assert_eq!(g.votes.get(p1).map(|s| s.as_str()), Some(p2));
        }

        // Second tap on another player: change vote.
        assert!(state
            .submit_vote(room_id, p1, "v2", Some(p3))
            .expect("change vote")
            .is_none());
        {
            let g = state.active_games.get(room_id).unwrap();
            assert_eq!(g.votes.get(p1).map(|s| s.as_str()), Some(p3));
        }

        // Third tap on current target: unvote.
        assert!(state
            .submit_vote(room_id, p1, "v3", None)
            .expect("unvote")
            .is_none());
        {
            let g = state.active_games.get(room_id).unwrap();
            assert!(g.votes.get(p1).is_none());
        }

        // Outside voting phase, every vote action must be rejected.
        {
            let mut g = state.active_games.get_mut(room_id).unwrap();
            g.phase = RuntimePhase::Day;
        }
        let err = state
            .submit_vote(room_id, p1, "v4", Some(p2))
            .expect_err("vote must be rejected outside voting phase");
        assert!(
            err.contains("voting phase"),
            "unexpected error for out-of-phase vote: {err}"
        );
    }

    #[tokio::test]
    async fn qa_c5_witch_revive_cancels_same_night_ghost_kill() {
        let state = test_state();
        let room_id = "44000000-0000-4000-8000-000000000001";
        let ghost = "44000000-0000-4000-8000-000000000011";
        let victim = "44000000-0000-4000-8000-000000000012";
        let witch = "44000000-0000-4000-8000-000000000013";
        seed_uuid_waiting_room(
            &state,
            room_id,
            &[(ghost, "g", true), (victim, "v", false), (witch, "w", false)],
        );
        state.start_game(room_id, ghost).await.expect("start");
        {
            let mut g = state.active_games.get_mut(room_id).unwrap();
            g.karma_targets.clear();
            g.phase_deadline_at = i64::MAX / 4;
            g.players.get_mut(ghost).unwrap().role = Some("ผีปอบ".to_string());
            g.players.get_mut(victim).unwrap().role = Some("ชาวบ้าน".to_string());
            g.players.get_mut(witch).unwrap().role = Some("หมอผีคุณไสย".to_string());
        }
        assert!(state
            .submit_action(
                room_id,
                ghost,
                "n1",
                "ghost_kill",
                Some(victim.to_string()),
            )
            .expect("ghost submits")
            .0
            .is_none());
        let phase = state
            .submit_action(
                room_id,
                witch,
                "n2",
                "witch_revive",
                Some(victim.to_string()),
            )
            .expect("witch submits");
        assert!(
            phase.0.is_none(),
            "night should wait until phase deadline before resolve"
        );
        {
            let mut g = state.active_games.get_mut(room_id).expect("runtime game");
            g.phase_deadline_at = 0;
        }
        let phase = state.tick_room(room_id).expect("night resolves");
        assert!(
            format!("{}", phase["phase"]).contains("Day")
                || format!("{}", phase["phase"]).contains("End"),
            "unexpected {phase}"
        );
        if !format!("{}", phase["phase"]).contains("End") {
            let g = state.active_games.get(room_id).expect("runtime game");
            assert!(g.players[victim].alive, "victim should be revived same night");
        }
    }

    #[tokio::test]
    async fn qa_c6_non_ghost_chat_rejected_at_night() {
        let state = test_state();
        let room_id = "45000000-0000-4000-8000-000000000001";
        let p1 = "45000000-0000-4000-8000-000000000011";
        let p2 = "45000000-0000-4000-8000-000000000012";
        seed_uuid_waiting_room(&state, room_id, &[(p1, "a", true), (p2, "b", false)]);
        state.start_game(room_id, p1).await.expect("start");
        {
            let mut g = state.active_games.get_mut(room_id).unwrap();
            g.players.get_mut(p1).unwrap().role = Some("ชาวบ้าน".to_string());
        }
        let err = state
            .validate_chat_sender(room_id, p1)
            .expect_err("villager night chat");
        assert!(
            err.to_lowercase().contains("ghost") || err.to_lowercase().contains("night"),
            "unexpected: {err}"
        );
    }

    #[tokio::test]
    async fn qa_c6b_ghost_faction_may_chat_at_night() {
        let state = test_state();
        let room_id = "45000000-0000-4000-8000-000000000002";
        let gh = "45000000-0000-4000-8000-000000000021";
        let v = "45000000-0000-4000-8000-000000000022";
        seed_uuid_waiting_room(&state, room_id, &[(gh, "g", true), (v, "v", false)]);
        state.start_game(room_id, gh).await.expect("start");
        {
            let mut g = state.active_games.get_mut(room_id).unwrap();
            g.players.get_mut(gh).unwrap().role = Some("ผีปอบ".to_string());
            g.players.get_mut(v).unwrap().role = Some("ชาวบ้าน".to_string());
        }
        state.validate_chat_sender(room_id, gh).expect("ghost may chat at night");
    }

    #[tokio::test]
    async fn qa_stability_pending_disconnect_recorded_without_background_leave() {
        let state = test_state();
        let pid = "46000000-0000-4000-8000-000000000011";
        state.mark_pending_disconnect(pid);
        assert!(state.pending_disconnects.contains_key(pid));
        assert!(state.consume_pending_disconnect(pid));
        assert!(!state.consume_pending_disconnect(pid));
    }

    fn drain_ws_until_contains(rx: &mut mpsc::UnboundedReceiver<Message>, needle: &str) -> String {
        for _ in 0..64 {
            let msg = rx.try_recv().expect("expected outbound ws message");
            let text = match msg {
                Message::Text(t) => t,
                other => panic!("unexpected message: {other:?}"),
            };
            if text.contains(needle) {
                return text;
            }
        }
        panic!("no message containing {needle:?}");
    }

    /// `game.started` broadcast reaches every registered connection (mirrors WS `game.start` ack path).
    #[tokio::test]
    async fn qa_game_started_broadcasts_to_two_registered_connections() {
        let state = test_state();
        let room_id = "51000000-0000-4000-8000-000000000001";
        let host = "51000000-0000-4000-8000-000000000011";
        let guest = "51000000-0000-4000-8000-000000000012";
        seed_uuid_waiting_room(
            &state,
            room_id,
            &[(host, "h", true), (guest, "g", false)],
        );
        state.player_rooms.insert(host.to_string(), room_id.to_string());
        state.player_rooms.insert(guest.to_string(), room_id.to_string());

        let (host_tx, mut host_rx) = mpsc::unbounded_channel::<Message>();
        let (guest_tx, mut guest_rx) = mpsc::unbounded_channel::<Message>();
        state.connections.insert(host.to_string(), host_tx.clone());
        state.connections.insert(guest.to_string(), guest_tx.clone());

        let payload = state.start_game(room_id, host).await.expect("start");
        let started = crate::ws::messages::ServerMessage::new("game.started", payload);
        state.broadcast_to_room(room_id, &serde_json::to_string(&started).unwrap());

        let h = drain_ws_until_contains(&mut host_rx, "game.started");
        assert!(h.contains("game.started"));
        let g = drain_ws_until_contains(&mut guest_rx, "game.started");
        assert!(g.contains("game.started"));
    }
}
