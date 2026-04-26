use std::sync::Arc;
use std::time::{Duration, SystemTime, UNIX_EPOCH};

use areyoughost_core::game_logic::vote_resolver::{VoteOutcome, VoteResolver};
use dashmap::DashMap;
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
}

impl AppState {
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
        })
    }

    fn now_unix_secs() -> i64 {
        SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap_or(Duration::from_secs(0))
            .as_secs() as i64
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

        // No available room — create a new public one
        let room_id = self.create_room(player_id, username, 16).await
            .map_err(|e| format!("Failed to create room: {}", e))?;
        Ok(room_id)
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

        let room_id_uuid = uuid::Uuid::new_v4();
        let room_id = room_id_uuid.to_string();
        let mut players = Vec::new();
        
        // Peek/pop the matched players
        let mut matched_uuids = Vec::new();
        for i in 0..min_players.min(queue.len()) {
            if let Some(player_id_str) = queue.pop_front() {
                if let Ok(p_uuid) = uuid::Uuid::parse_str(&player_id_str) {
                    matched_uuids.push((p_uuid, player_id_str.clone(), format!("Player{}", i + 1), i == 0));
                }
            }
        }

        if matched_uuids.is_empty() {
            return None;
        }

        let host_uuid = matched_uuids[0].0;

        // 1. Insert into rooms table
        if let Err(e) = sqlx::query(
            "INSERT INTO rooms (room_id, owner_id, room_name, max_players, is_public, room_type, room_status) 
             VALUES ($1, $2, $3, $4, $5, $6, $7)"
        )
        .bind(room_id_uuid)
        .bind(host_uuid)
        .bind(format!("Matchmaking Room"))
        .bind(16) // default max
        .bind(true)
        .bind("MATCHMAKING")
        .bind("WAITING")
        .execute(&self.db)
        .await
        {
            tracing::error!("matchmaking room insert failed: {}", e);
            return None;
        }

        // 2. Insert all matched players into room_members
        for (p_uuid, p_id_str, username, is_host) in matched_uuids {
            if let Err(e) = sqlx::query(
                "INSERT INTO room_members (room_id, player_id, member_status) 
                 VALUES ($1, $2, $3)"
            )
            .bind(room_id_uuid)
            .bind(p_uuid)
            .bind("JOINED")
            .execute(&self.db)
            .await
            {
                tracing::error!("matchmaking member insert failed: {}", e);
                continue;
            }

            players.push(PlayerInfo {
                player_id: p_id_str.clone(),
                username,
                is_ready: false,
                is_host,
            });
            self.player_rooms.insert(p_id_str, room_id.clone());
        }

        let room = Room {
            room_id: room_id.clone(),
            players,
            max_players: 16,
            is_public: true,
            status: "waiting".to_string(),
        };

        self.rooms.insert(room_id.clone(), room);
        tracing::info!("Created matchmaking room {} with {} players", room_id, min_players);
        Some(room_id)
    }

    // ─── Room helpers ─────────────────────────────────────────────

    pub async fn create_room(&self, host_id_str: String, username: String, max_players: usize) -> Result<RoomId, String> {
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
        .bind("PUBLIC")
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
                })
            });

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
            })
        })
    }

    pub fn start_game(&self, room_id: &str, host_id: &str) -> Result<serde_json::Value, String> {
        let mut room = self
            .rooms
            .get_mut(room_id)
            .ok_or_else(|| "Room not found".to_string())?;

        if room.status != "waiting" {
            return Err("Room is not in waiting state".to_string());
        }

        let host_ok = room
            .players
            .iter()
            .find(|p| p.player_id == host_id)
            .map(|p| p.is_host)
            .unwrap_or(false);
        if !host_ok {
            return Err("Only host can start game".to_string());
        }

        if room.players.len() < 2 {
            return Err("Need at least 2 players to start".to_string());
        }
        if room.players.len() > 16 {
            return Err("Max 16 players".to_string());
        }

        let mut runtime_players = HashMap::new();
        for p in &room.players {
            runtime_players.insert(
                p.player_id.clone(),
                RuntimePlayerState {
                    alive: true,
                    role: None,
                },
            );
        }

        let now = Self::now_unix_secs();
        let game = RuntimeGame {
            room_id: room.room_id.clone(),
            phase: RuntimePhase::Night,
            day_no: 1,
            night_no: 1,
            players: runtime_players,
            actions: HashMap::new(),
            votes: HashMap::new(),
            seen_request_ids: HashSet::new(),
            phase_started_at: now,
            phase_deadline_at: now + self.night_phase_secs as i64,
        };

        room.status = "playing".to_string();
        self.active_games.insert(room_id.to_string(), game);

        Ok(serde_json::json!({
            "roomId": room_id,
            "phase": RuntimePhase::Night,
            "dayNo": 1,
            "nightNo": 1
        }))
    }

    pub fn submit_action(
        &self,
        room_id: &str,
        actor_id: &str,
        request_id: &str,
        action_type: &str,
        target_id: Option<String>,
    ) -> Result<(), String> {
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

        if let Some(ref target) = target_id {
            if !game.players.contains_key(target) {
                return Err("Invalid target player".to_string());
            }
        }

        game.actions.insert(
            actor_id.to_string(),
            RuntimeAction {
                action_type: action_type.to_string(),
                target_id,
            },
        );

        Ok(())
    }

    pub fn submit_vote(
        &self,
        room_id: &str,
        voter_id: &str,
        request_id: &str,
        target_id: &str,
    ) -> Result<(), String> {
        let mut game = self
            .active_games
            .get_mut(room_id)
            .ok_or_else(|| "No active game for room".to_string())?;

        if game.phase != RuntimePhase::Voting {
            return Err("vote allowed only during voting phase".to_string());
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
        Ok(())
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

        let host_ok = room
            .players
            .iter()
            .find(|p| p.player_id == host_id)
            .map(|p| p.is_host)
            .unwrap_or(false);
        if !host_ok {
            return Err("Only host can advance phase".to_string());
        }

        let (payload, _) = self.advance_phase_internal(&mut game)?;
        Ok(payload)
    }

    fn advance_phase_internal(
        &self,
        game: &mut RuntimeGame,
    ) -> Result<(serde_json::Value, Option<String>), String> {
        let mut eliminated: Option<String> = None;

        match game.phase {
            RuntimePhase::Night => {
                for action in game.actions.values() {
                    if action.action_type.eq_ignore_ascii_case("kill") {
                        if let Some(target) = &action.target_id {
                            if let Some(target_state) = game.players.get_mut(target) {
                                target_state.alive = false;
                                eliminated = Some(target.clone());
                                break;
                            }
                        }
                    }
                }
                game.actions.clear();
                game.phase = RuntimePhase::Day;
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
                game.votes.clear();
                game.night_no += 1;
                game.phase = RuntimePhase::Night;
            }
            RuntimePhase::Lobby | RuntimePhase::End => {
                return Err("Cannot advance phase in current state".to_string());
            }
        }

        let alive_count = game.players.values().filter(|p| p.alive).count();
        if alive_count <= 1 {
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

        Ok((
            serde_json::json!({
                "roomId": game.room_id,
                "phase": game.phase,
                "dayNo": game.day_no,
                "nightNo": game.night_no,
                "eliminatedPlayerId": eliminated,
                "phaseDeadlineAt": game.phase_deadline_at,
            }),
            eliminated,
        ))
    }

    pub fn tick_games(&self) {
        let now = Self::now_unix_secs();
        let mut to_broadcast: Vec<(String, String)> = Vec::new();
        let mut ended_rooms: Vec<String> = Vec::new();

        for mut entry in self.active_games.iter_mut() {
            if entry.phase == RuntimePhase::End || entry.phase_deadline_at > now {
                continue;
            }

            if let Ok((phase_payload, _)) = self.advance_phase_internal(&mut entry) {
                let phase_msg = serde_json::json!({
                    "type": "game.phase_changed",
                    "payload": phase_payload,
                    "req_id": serde_json::Value::Null
                });
                to_broadcast.push((entry.room_id.clone(), phase_msg.to_string()));

                if let Some(room_state) = self.get_room_state(&entry.room_id) {
                    let state_msg = serde_json::json!({
                        "type": "room.state",
                        "payload": room_state,
                        "req_id": serde_json::Value::Null
                    });
                    to_broadcast.push((entry.room_id.clone(), state_msg.to_string()));
                }

                if entry.phase == RuntimePhase::End {
                    ended_rooms.push(entry.room_id.clone());
                }
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
}
