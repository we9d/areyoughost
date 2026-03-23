use std::sync::Arc;

use dashmap::DashMap;
use sqlx::PgPool;
use std::collections::VecDeque;
use tokio::sync::{mpsc, Mutex};
use axum::extract::ws::Message;
use serde::Serialize;

pub type PlayerId = String;
pub type RoomId = String;

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
}

impl AppState {
    pub fn new(db: PgPool, jwt_secret: String) -> Arc<Self> {
        Arc::new(Self {
            db,
            jwt_secret,
            connections: DashMap::new(),
            player_rooms: DashMap::new(),
            rooms: DashMap::new(),
            queue: Mutex::new(VecDeque::new()),
            invites: DashMap::new(),
        })
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
        let room_id = uuid::Uuid::new_v4().to_string();
        let invite_code = uuid::Uuid::new_v4()
            .to_string()
            .split('-')
            .next()
            .unwrap_or("INVITE")
            .to_uppercase();

        let now = chrono::Utc::now().to_rfc3339();
        let mut tx = self.db.begin().await
            .map_err(|e| format!("DB Error: {}", e))?;

        sqlx::query(
            "INSERT INTO rooms (room_id, owner_id, room_name, max_players, is_public, room_status, created_at, updated_at) \
             VALUES ($1, $2, $3, $4, $5, $6, $7, $8)"
        )
        .bind(&room_id)
        .bind(&host_id)
        .bind(format!("{}'s Room", username))
        .bind(16i32)
        .bind(0) // is_public = false
        .bind("WAITING")
        .bind(&now)
        .bind(&now)
        .execute(&mut *tx)
        .await
        .map_err(|e| format!("DB Error (insert room): {}", e))?;

        let member_id = uuid::Uuid::new_v4().to_string();
        sqlx::query(
            "INSERT INTO room_members (room_member_id, room_id, player_id, member_status, joined_at) \
             VALUES ($1, $2, $3, $4, $5)"
        )
        .bind(member_id)
        .bind(&room_id)
        .bind(&host_id)
        .bind("JOINED")
        .bind(&now)
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
        let _ = sqlx::query(
            "INSERT INTO rooms (room_id, owner_id, room_name, max_players, is_public, room_status) 
             VALUES ($1, $2, $3, $4, $5, $6)"
        )
        .bind(room_id_uuid)
        .bind(host_uuid)
        .bind(format!("Matchmaking Room"))
        .bind(16) // default max
        .bind(true)
        .bind("WAITING")
        .execute(&self.db)
        .await;

        // 2. Insert all matched players into room_members
        for (p_uuid, p_id_str, username, is_host) in matched_uuids {
            let _ = sqlx::query(
                "INSERT INTO room_members (room_id, player_id, member_status) 
                 VALUES ($1, $2, $3)"
            )
            .bind(room_id_uuid)
            .bind(p_uuid)
            .bind("JOINED")
            .execute(&self.db)
            .await;

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

    pub async fn create_room(&self, host_id_str: String, username: String, max_players: usize) -> Result<RoomId, sqlx::Error> {
        let room_id = uuid::Uuid::new_v4().to_string();

        let mut tx = self.db.begin().await?;

        // 1. Insert into rooms — bind as TEXT strings for UUIDs/timestamps, int for max_players/is_public
        let now = chrono::Utc::now().to_rfc3339();
        sqlx::query(
            "INSERT INTO rooms (room_id, owner_id, room_name, max_players, is_public, room_status, created_at, updated_at) 
             VALUES ($1, $2, $3, $4, $5, $6, $7, $8)"
        )
        .bind(&room_id)
        .bind(&host_id_str)
        .bind(format!("{}'s Room", username))
        .bind(max_players as i32)
        .bind(1) // is_public is integer in DB
        .bind("WAITING")
        .bind(&now)
        .bind(&now)
        .execute(&mut *tx)
        .await?;

        // 2. Insert into room_members (Host is JOINED)
        let room_member_id = uuid::Uuid::new_v4().to_string();
        sqlx::query(
            "INSERT INTO room_members (room_member_id, room_id, player_id, member_status, joined_at) 
             VALUES ($1, $2, $3, $4, $5)"
        )
        .bind(room_member_id)
        .bind(&room_id)
        .bind(&host_id_str)
        .bind("JOINED")
        .bind(&now)
        .execute(&mut *tx)
        .await?;

        tx.commit().await?;

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
        let _room_id_uuid = uuid::Uuid::parse_str(room_id_str)
            .map_err(|_| "Invalid room ID format".to_string())?;
            
        let _player_uuid = uuid::Uuid::parse_str(player_id_str)
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
        let now = chrono::Utc::now().to_rfc3339();
        let member_id = uuid::Uuid::new_v4().to_string();
        sqlx::query(
            "INSERT INTO room_members (room_member_id, room_id, player_id, member_status, joined_at) 
             VALUES ($1, $2, $3, $4, $5)
             ON CONFLICT (room_id, player_id) 
             DO UPDATE SET member_status = 'JOINED', joined_at = EXCLUDED.joined_at, left_at = NULL, lost_at = NULL"
        )
        .bind(member_id)
        .bind(room_id_str)
        .bind(player_id_str)
        .bind("JOINED")
        .bind(&now)
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

        // Update DB in background to not block the immediate memory state update 
        let db_pool = self.db.clone();
        let p_id = player_id_str.to_string();
        let r_id = room_id.clone();
        
        tokio::spawn(async move {
            if let (Ok(r_uuid), Ok(p_uuid)) = (uuid::Uuid::parse_str(&r_id), uuid::Uuid::parse_str(&p_id)) {
                let _ = sqlx::query(
                    "UPDATE room_members SET member_status = 'LEFT', left_at = now() 
                     WHERE room_id = $1 AND player_id = $2"
                )
                .bind(r_uuid)
                .bind(p_uuid)
                .execute(&db_pool)
                .await;
            }
        });

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
            })
        })
    }

    // ─── Game Management ──────────────────────────────────────────
    pub async fn start_game(&self, host_id_str: &str, room_id_str: &str) -> Result<serde_json::Value, String> {
        let mut room_ref = self.rooms.get_mut(room_id_str)
            .ok_or_else(|| "Room not found".to_string())?;

        // 1. Verify Host
        let is_host = room_ref.players.iter()
            .any(|p| p.player_id == host_id_str && p.is_host);

        if !is_host {
            return Err("Only the host can start the game".to_string());
        }

        // 2. Verify Room Status
        if room_ref.status != "waiting" {
            return Err("Game has already started or room is invalid".to_string());
        }

        // 3. Optional: Verify minimum players (example: minimum 2)
        if room_ref.players.len() < 2 {
            return Err("Not enough players to start the game (minimum 2 required)".to_string());
        }

        // 4. Update memory state
        room_ref.status = "playing".to_string();

        // 5. Update DB in background
        let db_pool = self.db.clone();
        let r_id = room_id_str.to_string();
        tokio::spawn(async move {
            if let Ok(r_uuid) = uuid::Uuid::parse_str(&r_id) {
                let _ = sqlx::query(
                    "UPDATE rooms SET room_status = 'PLAYING', updated_at = now() WHERE room_id = $1"
                )
                .bind(r_uuid)
                .execute(&db_pool)
                .await;
            }
        });

        // 6. Return the updated state
        let state_val = serde_json::json!({
            "roomId": room_ref.room_id,
            "players": room_ref.players.iter().map(|p| serde_json::json!({
                "playerId": p.player_id,
                "username": p.username,
                "isReady": p.is_ready,
                "isHost": p.is_host,
            })).collect::<Vec<_>>(),
            "maxPlayers": room_ref.max_players,
            "isPublic": room_ref.is_public,
            "status": room_ref.status,
        });

        Ok(state_val)
    }
}
