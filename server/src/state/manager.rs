use std::sync::Arc;
use dashmap::DashMap;
use sqlx::PgPool;
use std::collections::VecDeque;
use tokio::sync::Mutex;
use serde::Serialize;
use areyoughost_core::models::GameStatus;
use chrono::prelude::*;
use chrono::Duration;
use uuid::Uuid;

pub type PlayerId = uuid::Uuid;
pub type RoomId = uuid::Uuid;

#[derive(Clone, Debug, Serialize, serde::Deserialize, sqlx::FromRow)]
#[serde(rename_all = "camelCase")]
pub struct CachedRole {
    pub role_id: i32,
    pub role_code: String,
    pub role_name: String,
    pub faction: String,
    pub aura_result: String,
    pub seer_result: String,
    pub description: Option<String>,
    pub min_players: i32,
    pub max_players: i32,
    pub is_unique: bool,
    pub is_enabled: bool,
    pub role_priority: i32,
    pub role_img: Option<String>,
}

#[derive(Clone, Debug, Serialize, serde::Deserialize, sqlx::FromRow)]
#[serde(rename_all = "camelCase")]
pub struct CachedSkill {
    pub skill_id: uuid::Uuid,
    pub skill_code: String,
    pub skill_name: String,
    pub description: Option<String>,
    pub phase_type: String,
    pub target_type: String,
    pub usage_limit: Option<i32>,
    pub can_skip: bool,
    pub is_enabled: bool,
    pub skill_img: Option<String>,
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
    pub owner_id: PlayerId,
    pub players: Vec<PlayerInfo>,
    pub max_players: usize,
    pub room_type: String, // "QUICK" or "PRIVATE"
    pub status: GameStatus,
    pub auto_start_at: Option<chrono::DateTime<chrono::Utc>>,
}

// ─────────────────────────────────────────
// AppState — shared across all handlers
// ─────────────────────────────────────────

pub struct AppState {
    // Postgres connection pool (Supabase)
    pub db: PgPool,

    // JWT secret (from JWT_SECRET env var)
    pub jwt_secret: String,

    // Which room each player is in
    pub player_rooms: DashMap<PlayerId, RoomId>,

    // In-memory rooms
    pub rooms: DashMap<RoomId, Room>,

    // Matchmaking queue (FIFO)
    pub queue: Mutex<VecDeque<PlayerId>>,

    // Global Invites
    pub invites: DashMap<Uuid, Uuid>, 

    // Active Games
    pub games: DashMap<RoomId, areyoughost_core::game_logic::state::GameState>,

    // Cached Game Data
    pub cached_roles: Vec<CachedRole>,
    pub cached_skills: Vec<CachedSkill>,
    pub role_skills: DashMap<i32, Vec<uuid::Uuid>>, // role_id -> [skill_id]

    // Active Sessions (SRS 3.1.4.4 - Session Layer Simulation)
    pub sessions: DashMap<Uuid, PlayerId>,

    // Connection Registry (TCP Split Write Half -> Player)
    pub tx_map: DashMap<PlayerId, tokio::sync::mpsc::UnboundedSender<bytes::Bytes>>,

    // Room Runner Actions (TCP Split Read Half -> Room Runner)
    pub room_tx: DashMap<RoomId, tokio::sync::mpsc::UnboundedSender<crate::game_logic::room_task::RoomAction>>,
}

impl AppState {
    pub async fn new(db: PgPool, jwt_secret: String) -> Arc<Self> {
        let (roles, skills, mapping) = Self::load_roles_and_skills(&db).await.unwrap_or_else(|e| {
            tracing::error!("Failed to load roles: {}", e);
            (vec![], vec![], DashMap::new())
        });

        Arc::new(Self {
            db,
            jwt_secret,
            player_rooms: DashMap::new(),
            rooms: DashMap::new(),
            queue: Mutex::new(VecDeque::new()),
            invites: DashMap::new(),
            games: DashMap::new(),
            cached_roles: roles,
            cached_skills: skills,
            role_skills: mapping,
            sessions: DashMap::new(),
            tx_map: DashMap::new(),
            room_tx: DashMap::new(),
        })
    }

    /// Broadcast a single binary packet to all players currently in the given room.
    pub fn broadcast_to_room(&self, room_id: &RoomId, message: bytes::Bytes) {
        if let Some(room) = self.rooms.get(room_id) {
            for player in &room.players {
                if let Some(tx) = self.tx_map.get(&player.player_id) {
                    // Send to the player's background write task
                    let _ = tx.send(message.clone());
                }
            }
        }
    }

    /// Fetches the room snapshot and pushes RoomStateSync (0x20) to all players in that room.
    pub async fn broadcast_room_state_sync(&self, room_id: &RoomId) {
        if let Some(room_meta) = self.rooms.get(room_id) {
            let sync_payload = areyoughost_core::network::message::RoomStateSync {
                room_id: room_id.clone(),
                participants: room_meta.players.iter().enumerate().map(|(idx, p)| areyoughost_core::network::message::ParticipantInfoDto {
                    player_id: p.player_id.clone(),
                    username: p.username.clone(),
                    is_online: true,
                    is_alive: true, // simplified for lobby state
                    seat_number: (idx + 1) as i32,
                }).collect(),
                alive_count: room_meta.players.len() as u32,
            };
            
            if let Ok(msg) = areyoughost_core::network::message::Message::from_json(
                areyoughost_core::network::message::MessageType::RoomStateSync, 
                &sync_payload
            ) {
                self.broadcast_to_room(room_id, msg.to_bytes());
            }
        }
    }

    async fn load_roles_and_skills(db: &PgPool) -> Result<(Vec<CachedRole>, Vec<CachedSkill>, DashMap<i32, Vec<uuid::Uuid>>), sqlx::Error> {
        let roles = sqlx::query_as::<_, CachedRole>(
            "SELECT role_id, role_code, role_name, faction, aura_result, seer_result, description, 
                    min_players, max_players, is_unique, is_enabled, role_priority, role_img 
             FROM roles WHERE is_enabled = true"
        )
        .fetch_all(db).await?;

        let skills = sqlx::query_as::<_, CachedSkill>(
            "SELECT skill_id, skill_code, skill_name, description, phase_type, target_type, 
                    usage_limit, can_skip, is_enabled, skill_img 
             FROM skills WHERE is_enabled = true"
        )
        .fetch_all(db).await?;

        let mapping = DashMap::new();
        let maps = sqlx::query("SELECT role_id, skill_id FROM role_skills")
            .fetch_all(db).await?;
        for m in maps {
            let r_id: i32 = sqlx::Row::get(&m, "role_id");
            let s_id: uuid::Uuid = sqlx::Row::get(&m, "skill_id");
            mapping.entry(r_id).or_insert_with(Vec::new).push(s_id);
        }

        Ok((roles, skills, mapping))
    }

    pub async fn cleanup_stale_rooms(db: &PgPool) -> Result<(), sqlx::Error> {
        sqlx::query("UPDATE rooms SET room_status = 'CLOSED', updated_at = now() WHERE room_status IN ('WAITING', 'LOCKED')")
            .execute(db)
            .await?;
        Ok(())
    }

    // ─── Quick Play ───────────────────────────────────────────────

    /// Find an existing waiting public room with space, or create a new one.
    pub async fn quick_play(self: Arc<Self>, player_id: PlayerId, username: String) -> Result<RoomId, String> {
        if let Some(room_id) = self.player_rooms.get(&player_id) {
            return Ok(room_id.clone());
        }

        let mut tx = self.db.begin().await
            .map_err(|e| format!("DB Error (begin tx): {}", e))?;

        #[derive(sqlx::FromRow)]
        struct RoomRow {
            room_id: uuid::Uuid,
        }

        let room_row = sqlx::query_as::<_, RoomRow>(
            "WITH target_room AS (
                SELECT r.room_id 
                FROM rooms r 
                LEFT JOIN room_members rm ON r.room_id = rm.room_id AND rm.member_status = 'JOINED'
                WHERE r.room_status = 'WAITING' AND r.room_type = 'QUICK' 
                GROUP BY r.room_id, r.max_players
                HAVING COUNT(rm.player_id) < r.max_players 
                LIMIT 1
             )
             SELECT room_id FROM rooms WHERE room_id = (SELECT room_id FROM target_room)
             FOR UPDATE SKIP LOCKED"
        )
        .fetch_optional(&mut *tx)
        .await
        .map_err(|e| format!("DB Error (select room): {}", e))?;

        if let Some(row) = room_row {
            let room_id = row.room_id;
            if self.rooms.contains_key(&room_id) {
                tx.commit().await.ok();
                self.join_room(&room_id, &player_id, username).await?;
                return Ok(room_id);
            }
        }

        tx.rollback().await.ok();
        let room_id = self.create_room(player_id, username, 16).await
            .map_err(|e| format!("Failed to create room: {}", e))?;
        Ok(room_id)
    }

    // ─── Private Room ─────────────────────────────────────────────

    /// Create a private room and return (room_id, invite_code).
    pub async fn create_private_room(self: Arc<Self>, host_id: PlayerId, username: String) -> Result<(RoomId, String), String> {
        let room_id = uuid::Uuid::new_v4();
        let invite_code_raw = uuid::Uuid::new_v4();
        let invite_code = invite_code_raw
            .to_string()
            .split('-')
            .next()
            .unwrap_or("INVITE")
            .to_uppercase();

        let mut tx = self.db.begin().await
            .map_err(|e| format!("DB Error: {}", e))?;

        let auto_start = Utc::now() + Duration::seconds(120);

        sqlx::query(
            "INSERT INTO rooms (room_id, owner_id, room_name, max_players, room_type, room_status, auto_start_at, created_at, updated_at) \
             VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)"
        )
        .bind(room_id)
        .bind(host_id)
        .bind(format!("{}'s Room", username))
        .bind(16i32)
        .bind("PRIVATE") 
        .bind("WAITING")
        .bind(auto_start)
        .bind(chrono::Utc::now())
        .bind(chrono::Utc::now())
        .execute(&mut *tx)
        .await
        .map_err(|e| format!("DB Error (insert room): {}", e))?;

        let m_uuid = uuid::Uuid::new_v4();

        sqlx::query(
            "INSERT INTO room_members (room_member_id, room_id, player_id, member_status, joined_at) \
             VALUES ($1, $2, $3, $4, $5)"
        )
        .bind(m_uuid)
        .bind(room_id)
        .bind(host_id)
        .bind("JOINED")
        .bind(chrono::Utc::now())
        .execute(&mut *tx)
        .await
        .map_err(|e| format!("DB Error (insert member): {}", e))?;

        tx.commit().await
            .map_err(|e| format!("DB Error (commit): {}", e))?;

        let room = Room {
            room_id: room_id,
            owner_id: host_id,
            players: vec![PlayerInfo {
                player_id: host_id,
                username,
                is_ready: false,
                is_host: true,
            }],
            max_players: 16,
            room_type: "PRIVATE".to_string(),
            status: GameStatus::Waiting,
            auto_start_at: Some(auto_start),
        };

        self.rooms.insert(room_id, room);
        self.player_rooms.insert(host_id, room_id);
        self.invites.insert(invite_code_raw, room_id);

        tracing::info!("Created private room {} with invite_code {}", room_id, invite_code);
        Ok((room_id, invite_code))
    }

    /// Resolve an invite code to a room_id.
    pub fn resolve_invite(&self, invite_code: &str) -> Option<RoomId> {
        let code = Uuid::parse_str(invite_code).ok()?;
        self.invites.get(&code).map(|r| *r)
    }

    // ─── Matchmaking ──────────────────────────────────────────────

    pub async fn join_queue(self: Arc<Self>, player_id: PlayerId, _username: String) -> Option<RoomId> {
        {
            let mut queue = self.queue.lock().await;
            if !queue.contains(&player_id) {
                queue.push_back(player_id);
                tracing::info!("Player {} added to queue. Size: {}", player_id, queue.len());
            }
        }
        self.try_match_players(2).await
    }

    async fn try_match_players(self: Arc<Self>, min_players: usize) -> Option<RoomId> {
        let mut queue = self.queue.lock().await;

        if queue.len() < min_players {
            return None;
        }

        let room_id_uuid = uuid::Uuid::new_v4();
        let mut players = Vec::new();
        
        // Peek/pop the matched players
        let mut matched_uuids = Vec::new();
        for i in 0..min_players.min(queue.len()) {
            if let Some(p_uuid) = queue.pop_front() {
                matched_uuids.push((p_uuid, format!("Player{}", i + 1), i == 0));
            }
        }

        if matched_uuids.is_empty() {
            return None;
        }

        let host_uuid = matched_uuids[0].0;

        // 1. Insert into rooms table
        let auto_start = chrono::Utc::now() + chrono::Duration::seconds(120);
        let _ = sqlx::query(
            "INSERT INTO rooms (room_id, owner_id, room_name, max_players, room_type, room_status, auto_start_at) 
             VALUES ($1, $2, $3, $4, $5, $6, $7)"
        )
        .bind(room_id_uuid)
        .bind(host_uuid)
        .bind(format!("Matchmaking Room"))
        .bind(16) // default max
        .bind("QUICK") // room_type
        .bind("WAITING")
        .bind(auto_start)
        .execute(&self.db)
        .await;

        // 2. Insert all matched players into room_members
        for (i, (p_uuid, username, is_host)) in matched_uuids.iter().enumerate() {
            let _ = sqlx::query(
                "INSERT INTO room_members (room_member_id, room_id, player_id, member_status, joined_at) 
                 VALUES ($1, $2, $3, $4, $5)"
            )
            .bind(uuid::Uuid::new_v4())
            .bind(room_id_uuid)
            .bind(p_uuid)
            .bind("JOINED")
            .bind(chrono::Utc::now())
            .execute(&self.db)
            .await;

            players.push(PlayerInfo {
                player_id: *p_uuid,
                username: username.clone(),
                is_ready: false,
                is_host: *is_host,
            });
            self.player_rooms.insert(*p_uuid, room_id_uuid);
        }

        let room = Room {
            room_id: room_id_uuid,
            owner_id: host_uuid,
            players,
            max_players: 16,
            room_type: "QUICK".to_string(),
            status: GameStatus::Waiting,
            auto_start_at: Some(auto_start),
        };

        self.rooms.insert(room_id_uuid, room);
        tracing::info!("Created matchmaking room {} with {} players", room_id_uuid, min_players);
        
        let r_id_spawn = room_id_uuid;
        let state = self.clone();
        tokio::spawn(async move {
            tokio::time::sleep(tokio::time::Duration::from_secs(120)).await;
            let _ = state.execute_start_game(r_id_spawn).await;
        });
        
        Some(room_id_uuid)
    }

    // ─── Room helpers ─────────────────────────────────────────────

    pub async fn create_room(self: Arc<Self>, host_id: PlayerId, username: String, max_players: usize) -> Result<RoomId, sqlx::Error> {
        let room_id = uuid::Uuid::new_v4();
        let mut tx = self.db.begin().await?;

        let auto_start = chrono::Utc::now() + chrono::Duration::seconds(120);

        sqlx::query(
            "INSERT INTO rooms (room_id, owner_id, room_name, max_players, room_type, room_status, auto_start_at, created_at, updated_at) 
             VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)"
        )
        .bind(room_id)
        .bind(host_id)
        .bind(format!("{}'s Room", username))
        .bind(max_players as i32)
        .bind("QUICK") 
        .bind("WAITING")
        .bind(auto_start)
        .bind(chrono::Utc::now())
        .bind(chrono::Utc::now())
        .execute(&mut *tx)
        .await?;

        let m_uuid = uuid::Uuid::new_v4();
        sqlx::query(
            "INSERT INTO room_members (room_member_id, room_id, player_id, member_status, joined_at) 
             VALUES ($1, $2, $3, $4, $5)"
        )
        .bind(m_uuid)
        .bind(room_id)
        .bind(host_id)
        .bind("JOINED")
        .bind(chrono::Utc::now())
        .execute(&mut *tx)
        .await?;

        tx.commit().await?;

        let room = Room {
            room_id: room_id,
            owner_id: host_id,
            players: vec![PlayerInfo {
                player_id: host_id,
                username,
                is_ready: false,
                is_host: true, 
            }],
            max_players,
            room_type: "QUICK".to_string(),
            status: GameStatus::Waiting,
            auto_start_at: Some(auto_start),
        };

        self.rooms.insert(room_id, room);
        self.player_rooms.insert(host_id, room_id);
        tracing::info!("Created and persisted public waiting room {}", room_id);
        
        let r_id_spawn = room_id;
        let state = self.clone();
        tokio::spawn(async move {
            tokio::time::sleep(tokio::time::Duration::from_secs(120)).await;
            let _ = state.execute_start_game(r_id_spawn).await;
        });

        Ok(room_id)
    }

    pub async fn join_room(self: Arc<Self>, room_id: &RoomId, player_id: &PlayerId, username: String) -> Result<(), String> {
        let mut room_ref = self.rooms.get_mut(room_id)
            .ok_or_else(|| "Room not found".to_string())?;

        if room_ref.status != GameStatus::Waiting {
            return Err("Room match has already started".to_string());
        }

        if room_ref.players.len() >= room_ref.max_players {
            return Err("Room is full".to_string());
        }

        if room_ref.players.iter().any(|p| p.player_id == *player_id) {
            return Err("Already in room".to_string());
        }

        let mut tx = self.db.begin().await
            .map_err(|e| format!("DB Error (begin tx): {}", e))?;

        let m_uuid = uuid::Uuid::new_v4();

        sqlx::query(
            "INSERT INTO room_members (room_member_id, room_id, player_id, member_status, joined_at) 
             VALUES ($1, $2, $3, $4, $5)
             ON CONFLICT (room_id, player_id) 
             DO UPDATE SET member_status = 'JOINED', joined_at = EXCLUDED.joined_at, left_at = NULL, lost_at = NULL"
        )
        .bind(m_uuid)
        .bind(room_id)
        .bind(player_id)
        .bind("JOINED")
        .bind(chrono::Utc::now())
        .execute(&mut *tx)
        .await
        .map_err(|e| format!("DB Error (upsert member): {}", e))?;

        tx.commit().await
            .map_err(|e| format!("DB Error (commit tx): {}", e))?;

        room_ref.players.push(PlayerInfo {
            player_id: *player_id,
            username,
            is_ready: false,
            is_host: false,
        });

        drop(room_ref); 

        self.player_rooms.insert(*player_id, *room_id);
        tracing::info!("Player {} joined room {}", player_id, room_id);

        let should_start = {
             let r = self.rooms.get(room_id).unwrap();
             r.room_type == "QUICK" && r.players.len() >= r.max_players && r.status == GameStatus::Waiting
        };

        if should_start {
            tracing::info!("Room {} is full (16/16). Auto-starting immediately.", room_id);
            let r_id = *room_id;
            let state = self.clone();
            
            tokio::spawn(async move {
                let _ = state.execute_start_game(r_id).await;
            });
        }

        Ok(())
    }

    pub async fn leave_room(&self, player_id: &PlayerId) -> Option<RoomId> {
        let room_id = {
            let entry = self.player_rooms.remove(player_id)?;
            entry.1
        };

        if let Some(mut room) = self.rooms.get_mut(&room_id) {
            room.players.retain(|p| p.player_id != *player_id);
            if room.players.is_empty() {
                drop(room);
                self.rooms.remove(&room_id);
            }
        }

        let db_pool = self.db.clone();
        let p_id = *player_id;
        let r_id = room_id;
        tokio::spawn(async move {
            let _ = sqlx::query(
                "UPDATE room_members SET member_status = 'LEFT', left_at = now() WHERE room_id = $1 AND player_id = $2"
            )
            .bind(r_id)
            .bind(p_id)
            .execute(&db_pool)
            .await;
        });

        tracing::info!("Player {} left room {}", player_id, room_id);
        
        // Broadcast update to remaining players
        if let Some(_state) = self.get_room_state(&room_id) {
            // self.broadcast_to_room(&room_id, &msg); // Legacy WS broadcast removed
            tracing::debug!("Room update ready (waiting for TCP broadcast integration)");
        }

        Some(room_id)
    }

    pub async fn load_room_members(&self, room_id: &RoomId) -> Vec<PlayerInfo> {
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
        .bind(room_id)
        .fetch_all(&self.db)
        .await
        .unwrap_or_default();

        rows.into_iter().map(|r| PlayerInfo {
            player_id: r.player_id,
            username: r.username,
            is_ready: false,
            is_host: r.player_id == r.owner_id,
        }).collect()
    }

    pub fn get_room_state(&self, room_id: &RoomId) -> Option<serde_json::Value> {
        self.rooms.get(room_id).map(|room| {
            let mut payload = serde_json::json!({
                "roomId": room.room_id,
                "ownerId": room.owner_id,
                "players": room.players.iter().map(|p| serde_json::json!({
                    "playerId": p.player_id,
                    "username": p.username,
                    "isReady": p.is_ready,
                    "isHost": p.is_host,
                })).collect::<Vec<_>>(),
                "maxPlayers": room.max_players,
                "roomType": room.room_type,
                "status": room.status,
                "autoStartAt": room.auto_start_at,
            });

            // If game is active, overlay current phase and timer
            if let Some(game) = self.games.get(room_id) {
                if let Some(obj) = payload.as_object_mut() {
                    obj.insert("currentPhase".to_string(), serde_json::json!(game.phase_machine.current_phase));
                    obj.insert("phaseEndTime".to_string(), serde_json::json!(game.phase_machine.phase_end_time));
                }
            }

            payload
        })
    }

    // ─── Game Management ──────────────────────────────────────────
    pub async fn start_game(self: Arc<Self>, host_id: &PlayerId, room_id: &RoomId) -> Result<serde_json::Value, String> {
        let room_ref = self.rooms.get_mut(room_id)
            .ok_or_else(|| "Room not found".to_string())?;

        let is_host = room_ref.players.iter()
            .any(|p| p.player_id == *host_id && p.is_host);

        if !is_host {
            return Err("Only the host can start the game".to_string());
        }

        if room_ref.status != GameStatus::Waiting {
            return Err("Game has already started or room is invalid".to_string());
        }

        if room_ref.players.len() < 2 {
            return Err("Not enough players to start the game (minimum 2 required)".to_string());
        }
        drop(room_ref);

        let state_val = self.execute_start_game(
            *room_id,
        ).await.map_err(|e| e.to_string())?;

        Ok(state_val)
    }

    pub async fn execute_start_game(
        self: Arc<Self>,
        room_id: RoomId,
    ) -> Result<serde_json::Value, String> {
        let res = sqlx::query(
            "UPDATE rooms SET room_status = 'LOCKED', updated_at = now() 
             WHERE room_id = $1 AND room_status = 'WAITING'"
        )
        .bind(room_id)
        .execute(&self.db)
        .await
        .map_err(|e| format!("DB Error (execute_start_game lock): {}", e))?;

        if res.rows_affected() == 0 {
            return Err("Game already starting or room is invalid (DB lock failed)".to_string());
        }

        let mut room_ref = match self.rooms.get_mut(&room_id) {
            Some(r) => r,
            None => return Err("Room not found in memory".to_string()),
        };

        room_ref.status = GameStatus::Starting;
        
        let mut players_initial_data = Vec::new();
        for p in &room_ref.players {
            players_initial_data.push((p.player_id, p.username.clone()));
        }

        use rand::seq::SliceRandom;
        let mut rng = rand::thread_rng();
        let player_count = players_initial_data.len();
        
        let role_pool: Vec<areyoughost_core::game_logic::roles::Role> = self.cached_roles.iter()
            .map(|cr| {
                let mut r = areyoughost_core::game_logic::roles::Role::new(
                    areyoughost_core::game_logic::roles::RoleType::from_role_id(cr.role_id)
                );
                r.role_code  = cr.role_code.clone();
                r.name       = cr.role_name.clone();
                r.aura_result= cr.aura_result.clone();
                r.seer_result= cr.seer_result.clone();
                r.description= cr.description.clone().unwrap_or_default();
                r.faction = match cr.faction.as_str() {
                    "VILLAGER" => areyoughost_core::game_logic::roles::Faction::Villager,
                    "GHOST"    => areyoughost_core::game_logic::roles::Faction::Ghost,
                    _          => areyoughost_core::game_logic::roles::Faction::Special,
                };
                r
            })
            .collect();
            
        let mut assigned_roles = Vec::new();
        let mut ghosts: Vec<_> = role_pool.iter()
            .filter(|r| r.faction == areyoughost_core::game_logic::roles::Faction::Ghost)
            .cloned()
            .collect();
        let mut others: Vec<_> = role_pool.iter()
            .filter(|r| r.faction != areyoughost_core::game_logic::roles::Faction::Ghost)
            .cloned()
            .collect();
        
        ghosts.shuffle(&mut rng);
        others.shuffle(&mut rng);
        
        if !ghosts.is_empty() {
            assigned_roles.push(ghosts.remove(0));
        }
        while assigned_roles.len() < player_count && !others.is_empty() {
            assigned_roles.push(others.remove(0));
        }
        if assigned_roles.len() < player_count {
            assigned_roles.push(role_pool[0].clone());
        }
        assigned_roles.shuffle(&mut rng);

        let seed: Option<u64> = None;
        let game_state = areyoughost_core::game_logic::state::GameState::init_from_room(
            room_ref.room_id,
            players_initial_data,
            Some(assigned_roles),
            seed
        );
        self.games.insert(room_ref.room_id, game_state);

        let state_val = serde_json::json!({
            "roomId": room_ref.room_id,
            "ownerId": room_ref.owner_id,
            "players": room_ref.players.iter().map(|p| serde_json::json!({
                "playerId": p.player_id,
                "username": p.username,
                "isReady": p.is_ready,
                "isHost": p.is_host,
            })).collect::<Vec<_>>(),
            "maxPlayers": room_ref.max_players,
            "roomType": room_ref.room_type,
            "status": room_ref.status,
            "autoStartAt": room_ref.auto_start_at,
        });

        drop(room_ref);

        let r_id = room_id;
        let state = self.clone();
        
        let (tx, rx) = tokio::sync::mpsc::unbounded_channel::<crate::game_logic::room_task::RoomAction>();
        state.room_tx.insert(r_id, tx);
        
        tokio::spawn(async move {
            tokio::time::sleep(tokio::time::Duration::from_secs(4)).await;

            if let Some(mut room) = state.rooms.get_mut(&r_id) {
                room.status = GameStatus::Playing;
            }
            
            let _ = sqlx::query(
                "UPDATE rooms SET room_status = 'PLAYING', updated_at = now() WHERE room_id = $1"
            )
            .bind(r_id)
            .execute(&state.db)
            .await;

            crate::game_logic::room_task::run_game_loop(state.clone(), r_id, rx).await;
            state.room_tx.remove(&r_id);
        });

        Ok(state_val)
    }
}
