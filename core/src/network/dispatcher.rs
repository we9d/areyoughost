//! # Dispatcher Module
//!
//! Routes inbound `Message` structs to the appropriate game-logic handler by opcode.
//! Implements the full opcode table (0x01–0xFF) as specified in the Areyoughost Protocol.

use anyhow::{anyhow, Result};
use bytes::Bytes;
use dashmap::DashMap;
use std::collections::HashMap;
use std::sync::Arc;
use std::time::SystemTime;
use tokio::sync::{mpsc, RwLock};
use tracing::{debug, error, info, warn};
use uuid::Uuid;
use chrono::{DateTime, Utc};

use crate::game_logic::state::AppState;
use crate::network::message::{
    Message, MessageType,
    LoginRequest, LoginResponse,
    RegisterRequest, RegisterResponse,
    ReconnectRequest, ReconnectResponse,
    QuickJoinRequest, QuickJoinResponse,
    CreateRoomRequest, CreateRoomResponse,
    JoinRoomRequest, JoinRoomResponse,
    StartGameRequest, CastVoteRequest,
    NightActionRequest, ChatMessageRequest, ChatBroadcast,
    InvitePlayerRequest, GameInviteReceived,
    ParticipantInfoDto, RoomStateSync,
    HeartbeatPayload, ErrorPayload,
};
use sqlx::Row;

// Redundant local structs removed - now using crate::network::message

// ─── Dispatcher ──────────────────────────────────────────────────────────────

/// Central command dispatcher — routes inbound messages to game-logic handlers.
#[derive(Clone)]
pub struct Dispatcher {
    pub app_state: Arc<RwLock<AppState>>,
    pub registry: Arc<DashMap<Uuid, mpsc::UnboundedSender<Bytes>>>,
}

impl Dispatcher {
    /// Construct a new `Dispatcher`.
    pub fn new(
        app_state: Arc<RwLock<AppState>>,
        registry: Arc<DashMap<Uuid, mpsc::UnboundedSender<Bytes>>>,
    ) -> Self {
        Self { app_state, registry }
    }

    // ─── Public entry point ───────────────────────────────────────────────────

    /// Route an inbound message to the appropriate handler based on opcode.
    ///
    /// Requirements 4.5, 4.6: unknown opcodes return Error (0xFF); all payloads
    /// are deserialized with `msg.parse_binary::<T>()` and validated before use.
    pub async fn handle(&self, player_id: Uuid, msg: Message) -> Result<()> {
        debug!(
            player_id = %player_id,
            opcode = ?msg.msg_type,
            "Dispatcher::handle"
        );

        match msg.msg_type {
            // ── Authentication ────────────────────────────────────────────────
            MessageType::LoginRequest => {
                self.handle_login(player_id, msg).await
            }
            MessageType::RegisterRequest => {
                self.handle_register(player_id, msg).await
            }
            MessageType::ReconnectRequest => {
                self.handle_reconnect(player_id, msg).await
            }

            // ── Room management ───────────────────────────────────────────────
            MessageType::RoomListResponse => {
                // 0x11 repurposed as StartGame (C→S direction)
                self.handle_start_game(player_id, msg).await
            }
            MessageType::CreateRoomRequest => {
                self.handle_create_room(player_id, msg).await
            }
            MessageType::JoinRoomRequest => {
                self.handle_join_room(player_id, msg).await
            }
            MessageType::QuickJoinRequest => {
                self.handle_quick_join(player_id, msg).await
            }
            MessageType::InvitePlayer => {
                self.handle_invite_player(player_id, msg).await
            }

            // ── Game actions ──────────────────────────────────────────────────
            MessageType::ChatMessage => {
                self.handle_chat(player_id, msg).await
            }
            MessageType::CastVote => {
                self.handle_cast_vote(player_id, msg).await
            }
            MessageType::NightAction => {
                self.handle_night_action(player_id, msg).await
            }

            // ── Keep-alive ────────────────────────────────────────────────────
            MessageType::Heartbeat => {
                self.handle_heartbeat(player_id, msg).await
            }

            // ── Graceful disconnect ───────────────────────────────────────────
            MessageType::Disconnect => {
                self.handle_disconnect(player_id).await
            }

            // ── Unknown / unsupported opcodes (Requirement 4.5) ───────────────
            other => {
                warn!(
                    player_id = %player_id,
                    opcode = ?other,
                    "Unsupported opcode received"
                );
                let err_msg = Message::from_json(
                    MessageType::Error,
                    &ErrorPayload {
                        message: format!("Unsupported opcode: {:?} (0x{:02X})", other, other as u8),
                    },
                )?;
                self.unicast(player_id, err_msg).await
            }
        }
    }

    // ─── Authentication handlers ──────────────────────────────────────────────

    /// Handle 0x01 LoginRequest.
    ///
    /// Queries DB for username, verifies bcrypt hash, creates a SessionInfo in
    /// AppState.sessions, sets player online_status = 'online', responds with
    /// LoginResponse (0x02) containing session_id and player_id, and re-registers
    /// the player in the Connection Registry under their actual player_id.
    ///
    /// Requirements: 11.1, 11.2, 11.3, 12.3, 25.2
    async fn handle_login(&self, player_id: Uuid, msg: Message) -> Result<()> {
        let req: LoginRequest = msg.parse_json().map_err(|e| {
            anyhow!("LoginRequest deserialize failed: {}", e)
        })?;

        if req.username.is_empty() || req.password.is_empty() {
            let resp = Message::from_json(
                MessageType::LoginResponse,
                &LoginResponse {
                    success: false,
                    session_id: None,
                    player_id: None,
                    error: Some("username and password are required".to_string()),
                },
            )?;
            return self.unicast(player_id, resp).await;
        }

        // NOTE: req.password is used only for bcrypt verification — never logged or stored.
        info!(username = %req.username, "LoginRequest received");

        // 1. Query DB for player record
        let db_pool = {
            let state = self.app_state.read().await;
            state.db_pool.clone()
        };

        let (db_player_id, password_hash) = match Self::find_player_by_username(&db_pool, &req.username).await {
            Ok(Some(record)) => record,
            Ok(None) => {
                let resp = Message::from_json(
                    MessageType::LoginResponse,
                    &LoginResponse {
                        success: false,
                        session_id: None,
                        player_id: None,
                        error: Some("invalid username or password".to_string()),
                    },
                )?;
                return self.unicast(player_id, resp).await;
            }
            Err(e) => {
                error!(error = %e, "DB error during login");
                let resp = Message::from_json(
                    MessageType::LoginResponse,
                    &LoginResponse {
                        success: false,
                        session_id: None,
                        player_id: None,
                        error: Some("internal server error".to_string()),
                    },
                )?;
                return self.unicast(player_id, resp).await;
            }
        };

        // 2. Verify bcrypt hash — password is used here only, never stored or logged
        let password_matches = bcrypt::verify(&req.password, &password_hash)
            .unwrap_or(false);

        if !password_matches {
            let resp = Message::from_json(
                MessageType::LoginResponse,
                &LoginResponse {
                    success: false,
                    session_id: None,
                    player_id: None,
                    error: Some("invalid username or password".to_string()),
                },
            )?;
            return self.unicast(player_id, resp).await;
        }

        // 3. Create session
        let session_id = Uuid::new_v4();
        {
            let mut state = self.app_state.write().await;
            state.sessions.insert(
                session_id,
                crate::game_logic::state::SessionInfo {
                    player_id: db_player_id,
                    last_seen: std::time::Instant::now(),
                },
            );
        }

        // 4. Update online status
        if let Err(e) = Self::update_online_status(&db_pool, &db_player_id, "online").await {
            error!(player_id = %db_player_id, error = %e, "Failed to set online status during login");
        }

        // 5. Re-register player in Connection Registry under their actual player_id.
        //    Move the sender from the temp UUID key to the real player_id key.
        if let Some((_, sender)) = self.registry.remove(&player_id) {
            self.registry.insert(db_player_id, sender);
        }

        info!(player_id = %db_player_id, "Login successful");

        let resp = Message::from_json(
            MessageType::LoginResponse,
            &LoginResponse {
                success: true,
                session_id: Some(session_id),
                player_id: Some(db_player_id),
                error: None,
            },
        )?;
        // Send via the new registry key (real player_id)
        self.unicast(db_player_id, resp).await
    }

    /// Handle 0x03 RegisterRequest.
    ///
    /// Validates username length (3–20), checks DB uniqueness, hashes password with
    /// bcrypt (cost 10), inserts into `players` table, and responds with
    /// RegisterResponse (0x04).
    ///
    /// Requirements: 11.4, 11.5, 25.2
    async fn handle_register(&self, player_id: Uuid, msg: Message) -> Result<()> {
        let req: RegisterRequest = msg.parse_json().map_err(|e| {
            anyhow!("RegisterRequest deserialize failed: {}", e)
        })?;

        // Validate username length (3–20 chars)
        if req.username.len() < 3 || req.username.len() > 20 {
            let resp = Message::from_json(
                MessageType::RegisterResponse,
                &RegisterResponse {
                    success: false,
                    error: Some("username must be 3–20 characters".to_string()),
                },
            )?;
            return self.unicast(player_id, resp).await;
        }

        if req.password.is_empty() {
            let resp = Message::from_json(
                MessageType::RegisterResponse,
                &RegisterResponse {
                    success: false,
                    error: Some("password is required".to_string()),
                },
            )?;
            return self.unicast(player_id, resp).await;
        }

        // NOTE: req.password is used only for bcrypt hashing — never logged or stored in plaintext.
        info!(username = %req.username, "RegisterRequest received");

        let db_pool = {
            let state = self.app_state.read().await;
            state.db_pool.clone()
        };

        // 1. Check username uniqueness
        let count_row = sqlx::query(
            "SELECT COUNT(*) AS count FROM players WHERE username = $1",
        )
        .bind(&req.username)
        .fetch_one(&db_pool)
        .await;

        match count_row {
            Ok(row) => {
                use sqlx::Row;
                let count: i64 = row.try_get("count").unwrap_or(0);
                if count > 0 {
                    let resp = Message::from_json(
                        MessageType::RegisterResponse,
                        &RegisterResponse {
                            success: false,
                            error: Some("username already taken".to_string()),
                        },
                    )?;
                    return self.unicast(player_id, resp).await;
                }
            }
            Err(e) => {
                error!(error = %e, "DB error checking username uniqueness");
                let resp = Message::from_json(
                    MessageType::RegisterResponse,
                    &RegisterResponse {
                        success: false,
                        error: Some("internal server error".to_string()),
                    },
                )?;
                return self.unicast(player_id, resp).await;
            }
        }

        // 2. Hash password with bcrypt cost 10 — plaintext password is dropped after this
        let password_hash = match bcrypt::hash(&req.password, 10) {
            Ok(h) => h,
            Err(e) => {
                error!(error = %e, "bcrypt hash failed");
                let resp = Message::from_json(
                    MessageType::RegisterResponse,
                    &RegisterResponse {
                        success: false,
                        error: Some("internal server error".to_string()),
                    },
                )?;
                return self.unicast(player_id, resp).await;
            }
        };

        // 3. Generate new player_id and insert into players table
        let new_player_id = uuid::Uuid::new_v4();

        let insert_result = Self::register_player(&db_pool, &new_player_id, &req.username, &password_hash).await;

        match insert_result {
            Ok(_) => {
                info!(player_id = %new_player_id, username = %req.username, "Player registered");
                let resp = Message::from_json(
                    MessageType::RegisterResponse,
                    &RegisterResponse {
                        success: true,
                        error: None,
                    },
                )?;
                self.unicast(player_id, resp).await
            }
            Err(e) => {
                error!(error = %e, "DB insert failed during registration");
                let resp = Message::from_json(
                    MessageType::RegisterResponse,
                    &RegisterResponse {
                        success: false,
                        error: Some("registration failed, please try again".to_string()),
                    },
                )?;
                self.unicast(player_id, resp).await
            }
        }
    }

    /// Handle 0x05 ReconnectRequest.
    ///
    /// Looks up session_id in AppState.sessions; if found and last_seen within 30 s,
    /// re-registers the player and restores game state. Full implementation in Task 8.
    async fn handle_reconnect(&self, temp_player_id: Uuid, msg: Message) -> Result<()> {
        let req: ReconnectRequest = msg.parse_json().map_err(|e| {
            anyhow!("ReconnectRequest deserialize failed: {}", e)
        })?;

        info!(session_id = %req.session_id, "ReconnectRequest received");

        // 1. Look up session in AppState
        let player_id = {
            let state = self.app_state.read().await;
            state.sessions.get(&req.session_id).map(|s| s.player_id)
        };

        let db_player_id = match player_id {
            Some(pid) => pid,
            None => {
                let resp = Message::from_json(
                    MessageType::ReconnectResponse,
                    &ReconnectResponse {
                        success: false,
                        room_id: None,
                        phase: None,
                        day_number: None,
                        phase_remaining_secs: None,
                        is_alive: None,
                        role: None,
                        error: Some("session expired".to_string()),
                    },
                )?;
                return self.unicast(temp_player_id, resp).await;
            }
        };

        // 2. Re-register player in Connection Registry
        if let Some((_, sender)) = self.registry.remove(&temp_player_id) {
            self.registry.insert(db_player_id, sender);
        }

        // 3. Update online status
        let db_pool = {
            let state = self.app_state.read().await;
            state.db_pool.clone()
        };
        if let Err(e) = Self::update_online_status(&db_pool, &db_player_id, "online").await {
            error!(player_id = %db_player_id, error = %e, "Failed to set online status during reconnect");
        }

        info!(player_id = %db_player_id, "Reconnect successful");

        let resp = Message::from_json(
            MessageType::ReconnectResponse,
            &ReconnectResponse {
                success: true,
                room_id: None, // TODO: find current room_id if applicable
                phase: None,
                day_number: None,
                phase_remaining_secs: None,
                is_alive: Some(true),
                role: None,
                error: None,
            },
        )?;
        self.unicast(db_player_id, resp).await
    }

    // ─── Room management handlers ─────────────────────────────────────────────

    /// Handle 0x11 StartGame (RoomListResponse opcode repurposed for C→S StartGame).
    ///
    /// Validates sender is Host, room has ≥ 4 players, and room is not already PLAYING.
    /// Assigns roles, unicasts each player's role, spawns RoomRunner, broadcasts
    /// GamePhaseChange (0x33) for Night phase 1.
    ///
    /// Requirements: 4.2, 9.1, 9.2, 9.3, 9.4, 9.5, 14.2, 25.6
    async fn handle_start_game(&self, player_id: Uuid, msg: Message) -> Result<()> {
        let req: StartGameRequest = msg.parse_json().map_err(|e| {
            anyhow!("StartGameRequest deserialize failed: {}", e)
        })?;

        if req.room_id.is_nil() {
            let err = Message::from_json(
                MessageType::Error,
                &ErrorPayload { message: "room_id is required".to_string() },
            )?;
            return self.unicast(player_id, err).await;
        }

        info!(player_id = %player_id, room_id = %req.room_id, "StartGame received");

        // ── 1. Validate: sender is room Host ─────────────────────────────────
        {
            let state = self.app_state.read().await;
            match state.rooms.get(&req.room_id) {
                None => {
                let err = Message::from_json(
                    MessageType::Error,
                    &ErrorPayload { message: "room not found".to_string() },
                )?;
                    return self.unicast(player_id, err).await;
                }
                Some(room_state) => {
                    if room_state.host_id != player_id {
                        let err = Message::from_json(
                            MessageType::Error,
                            &ErrorPayload { message: "not room host".to_string() },
                        )?;
                        return self.unicast(player_id, err).await;
                    }
                    // ── 2. Validate: room is not already PLAYING ──────────────
                    if room_state.room.room_status == crate::models::GameStatus::Playing {
                        let err = Message::from_json(
                            MessageType::Error,
                            &ErrorPayload { message: "game already started".to_string() },
                        )?;
                        return self.unicast(player_id, err).await;
                    }
                }
            }
        }

        let db_pool = {
            let state = self.app_state.read().await;
            state.db_pool.clone()
        };

        // ── 4. Get all JOINED room members from DB ────────────────────────────
        let members_rows = sqlx::query(
            "SELECT p.player_id, p.username \
             FROM room_members rm \
             JOIN players p ON rm.player_id = p.player_id \
             WHERE rm.room_id = $1 AND rm.member_status = 'JOINED'",
        )
        .bind(req.room_id)
        .fetch_all(&db_pool)
        .await
        .map_err(|e| anyhow!("DB error fetching room members: {}", e))?;

        if members_rows.is_empty() {
            let err = Message::from_json(
                MessageType::Error,
                &ErrorPayload { message: "no joined players found".to_string() },
            )?;
            return self.unicast(player_id, err).await;
        }

        // ── 3. Validate: at least 4 players ──────────────────────
        if members_rows.len() < 4 {
            let err = Message::from_json(
                MessageType::Error,
                &ErrorPayload { message: "need >= 4 players".to_string() },
            )?;
            return self.unicast(player_id, err).await;
        }

        use sqlx::Row;
        let players: Vec<(Uuid, String)> = members_rows
            .iter()
            .map(|row| {
                let pid: Uuid = row.try_get("player_id").unwrap_or_default();
                let uname: String = row.try_get("username").unwrap_or_default();
                (pid, uname)
            })
            .collect();

        let player_count = players.len();

        // ── 5. Assign roles with a random seed ───────────────────────────────
        let random_seed: u64 = rand::random::<u64>();

        let roles = crate::game_logic::role_distributor::RoleDistributor::assign_roles(
            player_count,
            Some(random_seed),
        );

        // ── 6. Unicast each player's role via JoinRoomResponse (0x15) ─────────
        for (i, (pid, _uname)) in players.iter().enumerate() {
            let role = roles.get(i).cloned().unwrap_or_else(|| {
                crate::game_logic::roles::Role::new(crate::game_logic::roles::RoleType::Villager)
            });

            let faction_str = format!("{:?}", role.faction);

            let role_msg = Message::from_json(
                MessageType::JoinRoomResponse,
                &JoinRoomResponse {
                    success: true,
                    room_id: req.room_id,
                    role_code: role.role_code.clone(),
                    role_name: role.name.clone(),
                    faction: faction_str,
                    description: role.description.clone(),
                },
            )?;

            // Best-effort unicast — log failure but continue
            if let Err(e) = self.unicast(*pid, role_msg).await {
                warn!(player_id = %pid, error = %e, "Failed to unicast role to player");
            }
        }

        // ── 7. Create GameState ───────────────────────────────────────────────
        let mut game_state = crate::game_logic::state::GameState::init_from_room(
            req.room_id,
            players.clone(),
            Some(roles.clone()),
            Some(random_seed),
        );

        let game_id = Uuid::new_v4();
        game_state.game_id = game_id;

        // ── 8. Persist game record to DB ──────────────────────────────────────
        if let Err(e) = Self::create_game(&db_pool, &game_id, &req.room_id, random_seed as i64).await {
            error!(error = %e, "DB insert failed for games record");
            // Non-fatal: continue — game state is in memory
        }

        // ── 8b. Insert game_participants records ──────────────────────────────
        for (seat, (pid, _uname)) in players.iter().enumerate() {
            let role_code = roles
                .get(seat)
                .map(|r| r.role_code.clone())
                .unwrap_or_else(|| "VILLAGER".to_string());
            if let Err(e) = Self::insert_game_participant(&db_pool, &game_id, pid, &role_code, (seat + 1) as i32).await {
                error!(
                    player_id = %pid,
                    role_code = %role_code,
                    error = %e,
                    "DB insert failed for game_participants"
                );
                // Non-fatal: continue
            }
        }

        // ── 9. Update room status in DB ───────────────────────────────────────
        if let Err(e) = sqlx::query(
            "UPDATE rooms SET room_status = 'PLAYING' WHERE room_id = $1",
        )
        .bind(req.room_id)
        .execute(&db_pool)
        .await
        {
            error!(error = %e, "DB update failed for room status");
        }

        // ── 10. Create action channel and store sender in room_state ──────────
        let (action_tx, action_rx) =
            mpsc::unbounded_channel::<crate::game_logic::room_task::RoomAction>();

        // ── 11. Update AppState: store game_state, action_tx, room status ─────
        {
            let mut state = self.app_state.write().await;
            if let Some(room_state) = state.rooms.get_mut(&req.room_id) {
                room_state.game_state = Some(game_state);
                room_state.action_tx = Some(action_tx);
                room_state.room.room_status = crate::models::GameStatus::Playing;
            }
        }

        // ── 12. Spawn RoomRunner task ─────────────────────────────────────────
        let runner = crate::game_logic::room_task::RoomRunner {
            room_id: req.room_id,
            app_state: Arc::clone(&self.app_state),
            registry: Arc::clone(&self.registry),
            action_rx,
        };
        tokio::spawn(async move { runner.run().await });

        // ── 13. Broadcast GamePhaseChange (0x33) for Night phase 1 ───────────
        let server_timestamp = SystemTime::now()
            .duration_since(SystemTime::UNIX_EPOCH)
            .unwrap_or_default()
            .as_secs();

        let phase_change_msg = Message::from_json(
            MessageType::GamePhaseChange,
            &crate::network::message::GamePhaseChange {
                phase: crate::game_logic::phase_machine::PhaseType::Night,
                day_number: 1,
                duration_secs: 20,
                server_timestamp,
                night_chat_history: None,
            },
        )?;

        self.broadcast_to_room(&req.room_id, phase_change_msg).await?;

        info!(
            player_id = %player_id,
            room_id = %req.room_id,
            player_count = player_count,
            game_id = %game_id,
            "Game started — Night phase 1 broadcast"
        );
        Ok(())
    }

    async fn handle_create_room(&self, player_id: Uuid, msg: Message) -> Result<()> {
        let req: CreateRoomRequest = msg.parse_json().map_err(|e| {
            anyhow!("CreateRoomRequest deserialize failed: {}", e)
        })?;

        if req.room_name.is_empty() {
            let resp = Message::from_json(
                MessageType::CreateRoomResponse,
                &CreateRoomResponse {
                    success: false,
                    room_id: None,
                    error: Some("room_name is required".to_string()),
                },
            )?;
            return self.unicast(player_id, resp).await;
        }

        let room_id = Uuid::new_v4();

        // Build the Room model
        let room = crate::models::Room {
            room_id,
            room_name: req.room_name.clone(),
            max_players: 16,
            room_type: "CUSTOM".to_string(), // new field
            room_status: crate::models::GameStatus::Waiting,
            auto_start_at: None,
            started_by_owner: true,
            created_at: Utc::now(),
            updated_at: Utc::now(),
            owner_id: player_id,
        };

        // Insert RoomState into AppState
        {
            let mut state = self.app_state.write().await;
            state.rooms.insert(
                room_id,
                crate::game_logic::state::RoomState {
                    room,
                    game_state: None,
                    host_id: player_id,
                    action_tx: None,
                    room_mode: crate::game_logic::state::RoomMode::Custom,
                    lobby_start_time: Some(std::time::Instant::now()),
                },
            );
        }

        info!(player_id = %player_id, room_id = %room_id, "Room created (Custom)");

        let resp = Message::from_json(
            MessageType::CreateRoomResponse,
            &CreateRoomResponse {
                success: true,
                room_id: Some(room_id),
                error: None,
            },
        )?;
        self.unicast(player_id, resp).await
    }

    async fn handle_join_room(&self, player_id: Uuid, msg: Message) -> Result<()> {
        let req: JoinRoomRequest = msg.parse_json().map_err(|e| {
            anyhow!("JoinRoomRequest deserialize failed: {}", e)
        })?;

        info!(player_id = %player_id, room_id = %req.room_id, "JoinRoomRequest received");

        // 1. Validate room exists and is not PLAYING
        {
            let state = self.app_state.read().await;
            match state.rooms.get(&req.room_id) {
                None => {
                    let err = Message::from_json(
                        MessageType::Error,
                        &ErrorPayload { message: "room not found".to_string() },
                    )?;
                    return self.unicast(player_id, err).await;
                }
                Some(room_state) => {
                    if room_state.room.room_status == crate::models::GameStatus::Playing {
                        let err = Message::from_json(
                            MessageType::Error,
                            &ErrorPayload { message: "game already in progress".to_string() },
                        )?;
                        return self.unicast(player_id, err).await;
                    }
                }
            }
        }

        let db_pool = {
            let state = self.app_state.read().await;
            state.db_pool.clone()
        };

        // 2. Insert room_members record in DB
        let member_id = Uuid::new_v4();
        if let Err(e) = Self::add_room_member(&db_pool, &member_id, &req.room_id, &player_id).await {
            error!(error = %e, "DB insert failed for room_members during join_room");
        }

        // 3. Collect all current room members from DB for RoomStateSync
        let members_rows = sqlx::query(
            "SELECT p.player_id, p.username, p.online_status \
             FROM room_members rm \
             JOIN players p ON rm.player_id = p.player_id \
             WHERE rm.room_id = $1 AND rm.member_status = 'JOINED'",
        )
        .bind(req.room_id)
        .fetch_all(&db_pool)
        .await
        .map_err(|e| anyhow!("DB query failed fetching room members for RoomStateSync: {}", e))?;

        let participants: Vec<ParticipantInfoDto> = members_rows
             .iter()
             .enumerate()
             .map(|(i, row)| {
                 let pid: Uuid = row.try_get("player_id").unwrap_or_else(|_| Uuid::nil());
                 let uname: String = row.try_get("username").unwrap_or_default();
                 let online_status: String = row.try_get("online_status").unwrap_or_default();
                 ParticipantInfoDto {
                     player_id: pid,
                     username: uname,
                     is_online: online_status == "online",
                     seat_number: (i + 1) as i32,
                     is_alive: true, // newly added field in DTO
                 }
             })
             .collect();

        let alive_count = participants.len() as u32;

        // 4. Serialize RoomStateSync (0x20) and broadcast to all room members
        let sync_msg = Message::from_json(
            MessageType::RoomStateSync,
            &crate::network::message::RoomStateSync {
                room_id: req.room_id,
                participants,
                alive_count,
            },
        )?;

        // Broadcast to all current members (lobby — no game_state yet, use participant list from DB)
        self.broadcast_to_room(&req.room_id, sync_msg).await?;

        info!(
            player_id = %player_id,
            room_id = %req.room_id,
            member_count = alive_count,
            "Player joined room, RoomStateSync broadcast"
        );
        Ok(())
    }

    /// Handle 0x17 QuickJoinRequest.
    ///
    /// Finds or creates a public room, adds player, responds with QuickJoinResponse (0x18).
    /// Full implementation in Task 9.
    async fn handle_quick_join(&self, player_id: Uuid, msg: Message) -> Result<()> {
        let req: QuickJoinRequest = msg.parse_json().map_err(|e| {
            anyhow!("QuickJoinRequest deserialize failed: {}", e)
        })?;

        if req.player_id == Uuid::nil() {
            let err = Message::from_json(
                MessageType::Error,
                &ErrorPayload { message: "player_id is required".to_string() },
            )?;
            return self.unicast(player_id, err).await;
        }

        info!(player_id = %player_id, "QuickJoinRequest received");

        // Search for an existing public QuickPlay room that is WAITING and has < 16 players
        let found_room = {
            let state = self.app_state.read().await;
            let mut found: Option<(Uuid, usize, Option<std::time::Instant>)> = None;
            for (rid, room_state) in &state.rooms {
                if room_state.room_mode == crate::game_logic::state::RoomMode::QuickPlay
                    && room_state.room.room_type == "PUBLIC"
                    && room_state.room.room_status == crate::models::GameStatus::Waiting
                {
                    let participant_count = if let Some(gs) = &room_state.game_state {
                        gs.participants.len()
                    } else {
                        0 // We'll look at DB or session counts if needed
                    };
                    if participant_count < 16 {
                        found = Some((*rid, participant_count, room_state.lobby_start_time));
                        break;
                    }
                }
            }
            found
        };

        let (room_id, current_players, lobby_remaining_secs) = if let Some((rid, count, start_time)) = found_room {
            // Found an existing room — add player to it
            // No current_players field to update in AppState anymore
            let elapsed = start_time
                .map(|t| t.elapsed().as_secs())
                .unwrap_or(0);
            let remaining = 120u32.saturating_sub(elapsed as u32);
        (rid, (count + 1) as u32, remaining)
        } else {
            // No suitable room found — create a new public QuickPlay room
            let db_pool = {
                let state = self.app_state.read().await;
                state.db_pool.clone()
            };

            let new_room_id = Uuid::new_v4();

            if let Err(e) = Self::create_room(&db_pool, &new_room_id, &player_id, "Quick Play", true).await {
                error!(error = %e, "DB insert failed during quick_join room creation");
                let err = Message::from_json(
                    MessageType::Error,
                    &ErrorPayload { message: "failed to create quick play room".to_string() },
                )?;
                return self.unicast(player_id, err).await;
            }

            let lobby_start = std::time::Instant::now();

            let room = crate::models::Room {
                room_id: new_room_id,
                room_name: "Quick Play".to_string(),
                max_players: 16,
                room_type: "PUBLIC".to_string(),
                room_status: crate::models::GameStatus::Waiting,
                auto_start_at: None,
                started_by_owner: false,
                created_at: Utc::now(),
                updated_at: Utc::now(),
                owner_id: player_id,
            };

            {
                let mut state = self.app_state.write().await;
                state.rooms.insert(
                    new_room_id,
                    crate::game_logic::state::RoomState {
                        room,
                        game_state: None,
                        host_id: player_id,
                        action_tx: None,
                        room_mode: crate::game_logic::state::RoomMode::QuickPlay,
                        lobby_start_time: Some(lobby_start),
                    },
                );
            }

            info!(player_id = %player_id, room_id = %new_room_id, "QuickPlay room created");

            // ── Spawn 120 s lobby timer for the new QuickPlay room ────────────
            {
                let room_id_clone = new_room_id.clone();
                let app_state_clone = Arc::clone(&self.app_state);
                let registry_clone = Arc::clone(&self.registry);
                tokio::spawn(async move {
                    tokio::time::sleep(tokio::time::Duration::from_secs(120)).await;

                    // If the room is already PLAYING (auto-started because it filled
                    // to 16 players), nothing to do — just return.
                    {
                        let state = app_state_clone.read().await;
                        if let Some(room_state) = state.rooms.get(&room_id_clone) {
                            if room_state.room.room_status == crate::models::GameStatus::Playing {
                                info!(room_id = %room_id_clone, "QuickPlay timer fired but game already started — skipping");
                                return;
                            }
                        } else {
                            // Room was already removed
                            return;
                        }
                    }

                    // Snapshot participant count and player IDs
                    let (participant_ids, current_count) = {
                        let state = app_state_clone.read().await;
                        match state.rooms.get(&room_id_clone) {
                            Some(room_state) => {
                                let count = if let Some(gs) = &room_state.game_state {
                                    gs.participants.len()
                                } else {
                                    0
                                };
                                let ids: Vec<Uuid> = if let Some(game_state) = &room_state.game_state {
                                    game_state.participants.keys().cloned().collect()
                                } else {
                                    Vec::new()
                                };
                                (ids, count)
                            }
                            None => return,
                        }
                    };

                    if current_count >= 4 {
                        // ── Auto-start: same flow as handle_start_game ────────
                        info!(room_id = %room_id_clone, players = current_count, "QuickPlay timer: auto-starting game");

                        let db_pool = {
                            let state = app_state_clone.read().await;
                            state.db_pool.clone()
                        };

                        // Get all JOINED room members from DB
                        let members_rows = sqlx::query(
                            "SELECT p.player_id, p.username \
                             FROM room_members rm \
                             JOIN players p ON rm.player_id = p.player_id \
                             WHERE rm.room_id = $1::uuid AND rm.member_status = 'JOINED'",
                        )
                        .bind(&room_id_clone)
                        .fetch_all(&db_pool)
                        .await;

                        let players: Vec<(Uuid, String)> = match members_rows {
                            Ok(rows) => {
                                use sqlx::Row;
                                rows.iter()
                                    .map(|row| {
                                        let pid: Uuid = row.try_get("player_id").unwrap_or_else(|_| Uuid::nil());
                                        let uname: String = row.try_get("username").unwrap_or_default();
                                        (pid, uname)
                                    })
                                    .collect()
                            }
                            Err(e) => {
                                error!(room_id = %room_id_clone, error = %e, "QuickPlay timer: DB error fetching members");
                                return;
                            }
                        };

                        if players.len() < 4 {
                            // Race condition: DB says fewer than 4 — disband instead
                            warn!(room_id = %room_id_clone, "QuickPlay timer: DB member count < 4, disbanding");
                        } else {
                            let player_count = players.len();
                            let random_seed: u64 = rand::random::<u64>();
                            let roles = crate::game_logic::role_distributor::RoleDistributor::assign_roles(
                                player_count,
                                Some(random_seed),
                            );

                            // Unicast each player's role
                            for (i, (pid, _uname)) in players.iter().enumerate() {
                                let role = roles.get(i).cloned().unwrap_or_else(|| {
                                    crate::game_logic::roles::Role::new(crate::game_logic::roles::RoleType::Villager)
                                });
                                let faction_str = format!("{:?}", role.faction);
                                let role_msg = Message::from_json(
                                    MessageType::JoinRoomResponse,
                                    &JoinRoomResponse {
                                        success: true,
                                        room_id: room_id_clone,
                                        role_code: role.role_code.clone(),
                                        role_name: role.name.clone(),
                                        faction: faction_str,
                                        description: role.description.clone(),
                                    },
                                );
                                if let Ok(msg) = role_msg {
                                    let bytes = msg.to_bytes();
                                    if let Some(sender) = registry_clone.get(pid) {
                                        let _ = sender.send(bytes);
                                    }
                                }
                            }

                            // Create GameState
                            let mut game_state = crate::game_logic::state::GameState::init_from_room(
                                room_id_clone,
                                players.clone(),
                                Some(roles),
                                Some(random_seed),
                            );
                            let game_id = Uuid::new_v4();
                            game_state.game_id = game_id;

                            // Persist game record
                            if let Err(e) = Dispatcher::create_game(&db_pool, &game_id, &room_id_clone, random_seed as i64).await {
                                error!(room_id = %room_id_clone, error = %e, "QuickPlay timer: DB insert failed for game");
                            }

                            // Update room status in DB
                            if let Err(e) = sqlx::query(
                                "UPDATE rooms SET room_status = 'PLAYING' WHERE room_id = $1::uuid",
                            )
                            .bind(&room_id_clone)
                            .execute(&db_pool)
                            .await
                            {
                                error!(room_id = %room_id_clone, error = %e, "QuickPlay timer: DB update room status failed");
                            }

                            // Create action channel and spawn RoomRunner
                            let (action_tx, action_rx) =
                                mpsc::unbounded_channel::<crate::game_logic::room_task::RoomAction>();

                            // Store game_state and action_tx in AppState
                            {
                                let mut state = app_state_clone.write().await;
                                if let Some(room_state) = state.rooms.get_mut(&room_id_clone) {
                                    room_state.game_state = Some(game_state);
                                    room_state.action_tx = Some(action_tx);
                                    room_state.room.room_status = crate::models::GameStatus::Playing;
                                }
                            }

                            // Spawn RoomRunner
                            let runner = crate::game_logic::room_task::RoomRunner {
                                room_id: room_id_clone.clone(),
                                app_state: Arc::clone(&app_state_clone),
                                registry: Arc::clone(&registry_clone),
                                action_rx,
                            };
                            tokio::spawn(async move { runner.run().await });

                            // Broadcast GamePhaseChange (0x33) for Night phase 1
                            let server_timestamp = std::time::SystemTime::now()
                                .duration_since(std::time::SystemTime::UNIX_EPOCH)
                                .unwrap_or_default()
                                .as_secs();

                            let phase_msg = Message::from_json(
                                MessageType::GamePhaseChange,
                                &crate::network::message::GamePhaseChange {
                                    phase: crate::game_logic::phase_machine::PhaseType::Night,
                                    day_number: 1,
                                    duration_secs: 20,
                                    server_timestamp,
                                    night_chat_history: None,
                                },
                            );

                            if let Ok(msg) = phase_msg {
                                let bytes = msg.to_bytes();
                                for (pid, _) in &players {
                                    if let Some(sender) = registry_clone.get(pid) {
                                        let _ = sender.send(bytes.clone());
                                    }
                                }
                            }

                            info!(room_id = %room_id_clone, players = player_count, "QuickPlay timer: game auto-started");
                            return;
                        }
                    }

                    // ── Disband: < 4 players (or DB race) ────────────────────
                    info!(room_id = %room_id_clone, players = current_count, "QuickPlay timer: not enough players, disbanding room");

                    // Collect participant IDs for disband notification.
                    // At this point game hasn't started so game_state is None;
                    // we need to find connected players via the registry.
                    // We'll query the DB for room members to get their player_ids.
                    let db_pool = {
                        let state = app_state_clone.read().await;
                        state.db_pool.clone()
                    };

                    let member_ids: Vec<Uuid> = {
                        use sqlx::Row;
                        sqlx::query(
                            "SELECT player_id FROM room_members \
                             WHERE room_id = $1::uuid AND member_status = 'JOINED'",
                        )
                        .bind(&room_id_clone)
                        .fetch_all(&db_pool)
                        .await
                        .unwrap_or_default()
                        .iter()
                        .map(|row| row.try_get::<Uuid, _>("player_id").unwrap_or_else(|_| Uuid::nil()))
                        .collect()
                    };

                    // Also include participant_ids collected earlier (pre-game state)
                    let all_ids: Vec<Uuid> = {
                        let mut combined = participant_ids.clone();
                        for id in member_ids {
                            if !combined.contains(&id) {
                                combined.push(id);
                            }
                        }
                        combined
                    };

                    // Send Error (0xFF) to all participants
                    let err_msg = Message::from_json(
                        MessageType::Error,
                        &ErrorPayload {
                            message: "not enough players, room closed".to_string(),
                        },
                    );

                    if let Ok(msg) = err_msg {
                        let bytes = msg.to_bytes();
                        for pid in &all_ids {
                            if let Some(sender) = registry_clone.get(pid) {
                                let _ = sender.send(bytes.clone());
                            }
                        }
                    }

                    // Remove room from AppState
                    {
                        let mut state = app_state_clone.write().await;
                        state.rooms.remove(&room_id_clone);
                    }

                    info!(room_id = %room_id_clone, "QuickPlay room disbanded");
                });
            }

            (new_room_id, 1u32, 120u32)
        };

        let db_pool = {
            let state = self.app_state.read().await;
            state.db_pool.clone()
        };

        // If the player jumped into an existing QuickPlay room, we must add them to DB.
        if found_room.is_some() {
            let member_id = Uuid::new_v4();
            if let Err(e) = Self::add_room_member(&db_pool, &member_id, &room_id, &player_id).await {
                error!(error = %e, "DB insert failed for room_members during quick_join");
            }
        }

        // Collect all current room members from DB for RoomStateSync
        let members_rows = sqlx::query(
            "SELECT p.player_id, p.username, p.online_status \
             FROM room_members rm \
             JOIN players p ON rm.player_id = p.player_id \
             WHERE rm.room_id = $1 AND rm.member_status = 'JOINED'",
        )
        .bind(room_id)
        .fetch_all(&db_pool)
        .await
        .unwrap_or_default();

        let participants: Vec<ParticipantInfoDto> = members_rows
             .iter()
             .enumerate()
             .map(|(i, row)| {
                 use sqlx::Row;
                 let pid: Uuid = row.try_get("player_id").unwrap_or_else(|_| Uuid::nil());
                 let uname: String = row.try_get("username").unwrap_or_default();
                 let online_status: String = row.try_get("online_status").unwrap_or_default();
                 ParticipantInfoDto {
                     player_id: pid,
                     username: uname,
                     is_online: online_status == "online",
                     seat_number: (i + 1) as i32,
                     is_alive: true,
                 }
             })
             .collect();

        let alive_count = participants.len() as u32;

        let sync_msg = Message::from_json(
            MessageType::RoomStateSync,
            &crate::network::message::RoomStateSync {
                room_id: room_id.clone(),
                participants,
                alive_count,
            },
        )?;

        self.broadcast_to_room(&room_id, sync_msg).await?;

        // ── Check if joining an existing room fills it to 16 → auto-start ────
        // (handled below after we know the room_id and current_players)
        let should_auto_start = current_players >= 16;

        let resp = Message::from_json(
            MessageType::QuickJoinResponse,
            &QuickJoinResponse {
                room_id: room_id.clone(),
                current_players,
                lobby_remaining_secs,
            },
        )?;
        self.unicast(player_id, resp).await?;

        // If the room just hit 16 players, trigger auto-start immediately.
        // The timer task will see room.status == Playing and return early.
        if should_auto_start {
            info!(player_id = %player_id, room_id = %room_id, "QuickPlay room full (16 players) — auto-starting");
            self.quick_play_auto_start(room_id).await?;
        }

        Ok(())
    }

    /// Auto-start a QuickPlay room (called when room fills to 16 players).
    ///
    /// Mirrors the logic in `handle_start_game()` but without host validation.
    async fn quick_play_auto_start(&self, room_id: Uuid) -> Result<()> {
        // Validate room is still WAITING
        {
            let state = self.app_state.read().await;
            match state.rooms.get(&room_id) {
                None => return Ok(()),
                Some(rs) => {
                    if rs.room.room_status == crate::models::GameStatus::Playing {
                        return Ok(()); // Already started
                    }
                }
            }
        }

        let db_pool = {
            let state = self.app_state.read().await;
            state.db_pool.clone()
        };

        // Get all JOINED room members from DB
        let members_rows = sqlx::query(
            "SELECT p.player_id, p.username \
             FROM room_members rm \
             JOIN players p ON rm.player_id = p.player_id \
             WHERE rm.room_id = $1::uuid AND rm.member_status = 'JOINED'",
        )
        .bind(room_id)
        .fetch_all(&db_pool)
        .await
        .map_err(|e| anyhow!("DB error fetching room members for auto-start: {}", e))?;

        if members_rows.len() < 4 {
            return Ok(()); // Not enough players yet
        }

        use sqlx::Row;
        let players: Vec<(Uuid, String)> = members_rows
            .iter()
            .map(|row| {
                let pid: Uuid = row.try_get("player_id").unwrap_or_else(|_| Uuid::nil());
                let uname: String = row.try_get("username").unwrap_or_default();
                (pid, uname)
            })
            .collect();

        let player_count = players.len();
        let random_seed: u64 = rand::random::<u64>();
        let roles = crate::game_logic::role_distributor::RoleDistributor::assign_roles(
            player_count,
            Some(random_seed),
        );

        // Unicast each player's role
        for (i, (pid, _uname)) in players.iter().enumerate() {
            let role = roles.get(i).cloned().unwrap_or_else(|| {
                crate::game_logic::roles::Role::new(crate::game_logic::roles::RoleType::Villager)
            });
            let faction_str = format!("{:?}", role.faction);
            let role_msg = Message::from_json(
                MessageType::JoinRoomResponse,
                &JoinRoomResponse {
                    success: true,
                    room_id,
                    role_code: role.role_code.clone(),
                    role_name: role.name.clone(),
                    faction: faction_str,
                    description: role.description.clone(),
                },
            )?;
            if let Err(e) = self.unicast(*pid, role_msg).await {
                warn!(player_id = %pid, error = %e, "quick_play_auto_start: failed to unicast role");
            }
        }

        // Create GameState
        let mut game_state = crate::game_logic::state::GameState::init_from_room(
            room_id,
            players.clone(),
            Some(roles),
            Some(random_seed),
        );
        let game_id = Uuid::new_v4();
        game_state.game_id = game_id;

        // Persist game record
        if let Err(e) = Self::create_game(&db_pool, &game_id, &room_id, random_seed as i64).await {
            error!(room_id = %room_id, error = %e, "quick_play_auto_start: DB insert failed for game");
        }

        // Update room status in DB
        if let Err(e) = sqlx::query(
            "UPDATE rooms SET room_status = 'PLAYING' WHERE room_id = $1::uuid",
        )
        .bind(room_id)
        .execute(&db_pool)
        .await
        {
            error!(room_id = %room_id, error = %e, "quick_play_auto_start: DB update room status failed");
        }

        // Create action channel and spawn RoomRunner
        let (action_tx, action_rx) =
            mpsc::unbounded_channel::<crate::game_logic::room_task::RoomAction>();

        // Store game_state and action_tx in AppState
        {
            let mut state = self.app_state.write().await;
            if let Some(room_state) = state.rooms.get_mut(&room_id) {
                room_state.game_state = Some(game_state);
                room_state.action_tx = Some(action_tx);
                room_state.room.room_status = crate::models::GameStatus::Playing;
            }
        }

        // Spawn RoomRunner
        let runner = crate::game_logic::room_task::RoomRunner {
            room_id,
            app_state: Arc::clone(&self.app_state),
            registry: Arc::clone(&self.registry),
            action_rx,
        };
        tokio::spawn(async move { runner.run().await });

        // Broadcast GamePhaseChange (0x33) for Night phase 1
        let server_timestamp = SystemTime::now()
            .duration_since(SystemTime::UNIX_EPOCH)
            .unwrap_or_default()
            .as_secs();

        let phase_change_msg = Message::from_json(
            MessageType::GamePhaseChange,
            &crate::network::message::GamePhaseChange {
                phase: crate::game_logic::phase_machine::PhaseType::Night,
                day_number: 1,
                duration_secs: 20,
                server_timestamp,
                night_chat_history: None,
            },
        )?;

        self.broadcast_to_room(&room_id, phase_change_msg).await?;

        info!(room_id = %room_id, players = player_count, "QuickPlay room auto-started (full)");
        Ok(())
    }

    /// Handle 0x1A InvitePlayer.
    ///
    /// Looks up target_username in DB, verifies online, unicasts GameInviteReceived (0x1B).
    /// Full implementation in Task 10.
    async fn handle_invite_player(&self, player_id: Uuid, msg: Message) -> Result<()> {
        let req: InvitePlayerRequest = msg.parse_json().map_err(|e| {
            anyhow!("InvitePlayerRequest deserialize failed: {}", e)
        })?;

        if req.target_username.is_empty() {
            let err = Message::from_json(
                MessageType::Error,
                &ErrorPayload { message: "target_username and room_id are required".to_string() },
            )?;
            return self.unicast(player_id, err).await;
        }

        info!(
            player_id = %player_id,
            target = %req.target_username,
            room_id = %req.room_id,
            "InvitePlayer received"
        );

        let db_pool = {
            let state = self.app_state.read().await;
            state.db_pool.clone()
        };

        // 1. Look up target player in DB
        let target_row = sqlx::query(
            "SELECT player_id, online_status FROM players WHERE username = $1",
        )
        .bind(&req.target_username)
        .fetch_optional(&db_pool)
        .await
        .map_err(|e| anyhow!("DB error looking up target player: {}", e))?;

        let (target_player_id, online_status) = match target_row {
            None => {
                let err = Message::from_json(
                    MessageType::Error,
                    &ErrorPayload { message: "player not found".to_string() },
                )?;
                return self.unicast(player_id, err).await;
            }
            Some(row) => {
                use sqlx::Row;
                let pid: Uuid = row.try_get("player_id")
                    .map_err(|e| anyhow!("Failed to get player_id: {}", e))?;
                let status: String = row.try_get("online_status")
                    .map_err(|e| anyhow!("Failed to get online_status: {}", e))?;
                (pid, status)
            }
        };

        // 2. Check online_status in DB
        if online_status != "online" {
            let err = Message::from_json(
                MessageType::Error,
                &ErrorPayload { message: "player not online".to_string() },
            )?;
            return self.unicast(player_id, err).await;
        }

        // 3. Check if target is in the Connection Registry
        if !self.registry.contains_key(&target_player_id) {
            let err = Message::from_json(
                MessageType::Error,
                &ErrorPayload { message: "player not online".to_string() },
            )?;
            return self.unicast(player_id, err).await;
        }

        // 4. Get the room name from AppState
        let room_name = {
            let state = self.app_state.read().await;
            state.rooms.get(&req.room_id).map(|r| r.room.room_name.clone())
        };

        let room_name = match room_name {
            Some(name) => name,
            None => {
                let err = Message::from_json(
                    MessageType::Error,
                    &ErrorPayload { message: "room not found".to_string() },
                )?;
                return self.unicast(player_id, err).await;
            }
        };

        // 5. Look up the inviting player's username from DB
        let from_username_row = sqlx::query(
            "SELECT username FROM players WHERE player_id = $1::uuid",
        )
        .bind(player_id)
        .fetch_optional(&db_pool)
        .await
        .map_err(|e| anyhow!("DB error looking up inviting player: {}", e))?;

        let from_username = match from_username_row {
            Some(row) => {
                use sqlx::Row;
                row.try_get::<String, _>("username")
                    .map_err(|e| anyhow!("Failed to get username: {}", e))?
            }
            None => {
                let err = Message::from_json(
                    MessageType::Error,
                    &ErrorPayload { message: "inviting player not found".to_string() },
                )?;
                return self.unicast(player_id, err).await;
            }
        };

        // 6. Serialize and unicast GameInviteReceived (0x1B) to the target player
        use crate::network::message::GameInviteReceived;
        let invite_msg = Message::from_json(
            MessageType::GameInviteReceived,
            &GameInviteReceived {
                from_username,
                room_id: req.room_id,
                room_name,
            },
        )?;

        info!(
            from = %player_id,
            target_player_id = %target_player_id,
            room_id = %req.room_id,
            "Sending GameInviteReceived"
        );
        self.unicast(target_player_id, invite_msg).await
    }

    // ─── Game action handlers ─────────────────────────────────────────────────

    /// Handle 0x30 ChatMessage.
    ///
    /// Validates sender is alive; day = broadcast to all alive; night = ghost-only.
    /// Full implementation in Task 14.
    async fn handle_chat(&self, player_id: Uuid, msg: Message) -> Result<()> {
        let req: ChatMessageRequest = msg.parse_json().map_err(|e| {
            anyhow!("ChatMessageRequest deserialize failed: {}", e)
        })?;

        if req.message_text.is_empty() {
            let err = Message::from_json(
                MessageType::Error,
                &ErrorPayload { message: "message_text is required".to_string() },
            )?;
            return self.unicast(player_id, err).await;
        }

        debug!(player_id = %player_id, room_id = %req.room_id, "ChatMessage received");

        // ── 1. Look up sender's participant info and current phase ────────────
        let (is_alive, sender_faction, current_phase, sender_username) = {
            let state = self.app_state.read().await;
            let room_state = match state.rooms.get(&req.room_id) {
                Some(r) => r,
                None => {
                    let err = Message::from_json(
                        MessageType::Error,
                        &ErrorPayload { message: "room not found".to_string() },
                    )?;
                    return self.unicast(player_id, err).await;
                }
            };
            let game_state = match &room_state.game_state {
                Some(g) => g,
                None => {
                    let err = Message::from_json(
                        MessageType::Error,
                        &ErrorPayload { message: "game not started".to_string() },
                    )?;
                    return self.unicast(player_id, err).await;
                }
            };
            let participant = match game_state.participants.get(&player_id) {
                Some(p) => p,
                None => {
                    let err = Message::from_json(
                        MessageType::Error,
                        &ErrorPayload { message: "player not in game".to_string() },
                    )?;
                    return self.unicast(player_id, err).await;
                }
            };
            let faction = participant
                .role
                .as_ref()
                .map(|r| r.faction.clone())
                .unwrap_or(crate::game_logic::roles::Faction::Villager);
            (
                participant.model.is_alive,
                faction,
                game_state.phase_machine.current_phase.clone(),
                participant.username.clone(),
            )
        };

        // ── 2. Validate: sender must be alive ─────────────────────────────────
        if !is_alive {
            let err = Message::from_json(
                MessageType::Error,
                &ErrorPayload { message: "dead players cannot chat".to_string() },
            )?;
            return self.unicast(player_id, err).await;
        }

        // ── 3. Night-phase restriction: only Ghost/Special faction may chat ───
        if current_phase == crate::game_logic::phase_machine::PhaseType::Night {
            if sender_faction == crate::game_logic::roles::Faction::Villager {
                let err = Message::from_json(
                    MessageType::Error,
                    &ErrorPayload { message: "night chat restricted".to_string() },
                )?;
                return self.unicast(player_id, err).await;
            }
        }

        // ── 4. Build broadcast payload ────────────────────────────────────────
        let broadcast_msg = Message::from_json(
            MessageType::ChatMessage,
            &ChatBroadcast {
                sender_id: player_id,
                message_text: req.message_text.clone(),
            },
        )?;

        // ── 5. Collect recipient player_ids ───────────────────────────────────
        let recipients: Vec<Uuid> = {
            let state = self.app_state.read().await;
            let room_state = match state.rooms.get(&req.room_id) {
                Some(r) => r,
                None => return Ok(()),
            };
            let game_state = match &room_state.game_state {
                Some(g) => g,
                None => return Ok(()),
            };
            game_state
                .participants
                .iter()
                .filter(|(_, p)| {
                    if !p.model.is_alive {
                        return false;
                    }
                    // Night phase: only broadcast to Ghost-faction players
                    if current_phase == crate::game_logic::phase_machine::PhaseType::Night {
                        let faction = p
                            .role
                            .as_ref()
                            .map(|r| r.faction.clone())
                            .unwrap_or(crate::game_logic::roles::Faction::Villager);
                        return faction == crate::game_logic::roles::Faction::Ghost;
                    }
                    true
                })
                .map(|(pid, _)| *pid)
                .collect()
        };

        // ── 6. Broadcast to recipients ────────────────────────────────────────
        let msg_bytes = broadcast_msg.to_bytes();
        for recipient_id in &recipients {
            if let Some(sender) = self.registry.get(recipient_id) {
                if let Err(e) = sender.send(msg_bytes.clone()) {
                    warn!(
                        player_id = %recipient_id,
                        error = %e,
                        "Failed to send ChatMessage; removing from registry"
                    );
                    drop(sender);
                    self.registry.remove(recipient_id);
                }
            }
        }

        info!(
            from = %player_id,
            username = %sender_username,
            room_id = %req.room_id,
            phase = ?current_phase,
            recipients = recipients.len(),
            "ChatMessage broadcast"
        );
        Ok(())
    }

    /// Handle 0x31 CastVote.
    ///
    /// Validates player is alive and phase is Vote; forwards to RoomRunner via action_tx.
    /// Full implementation in Task 13.
    async fn handle_cast_vote(&self, player_id: Uuid, msg: Message) -> Result<()> {
        let req: CastVoteRequest = msg.parse_json().map_err(|e| {
            anyhow!("CastVoteRequest deserialize failed: {}", e)
        })?;

        if req.target_id == Uuid::nil() {
            let err = Message::from_json(
                MessageType::Error,
                &ErrorPayload { message: "target_id is required".to_string() },
            )?;
            return self.unicast(player_id, err).await;
        }

        debug!(player_id = %player_id, target = %req.target_id, "CastVote received");

        // 1. Find the player's room and validate state
        let (action_tx, is_alive, is_vote_phase) = {
            let state = self.app_state.read().await;
            let mut found: Option<(Option<mpsc::UnboundedSender<crate::game_logic::room_task::RoomAction>>, bool, bool)> = None;

            for (_room_id, room_state) in &state.rooms {
                if let Some(game_state) = &room_state.game_state {
                    if let Some(participant) = game_state.participants.get(&player_id) {
                        let is_alive = participant.model.is_alive;
                        let is_vote_phase = game_state.phase_machine.current_phase
                            == crate::game_logic::phase_machine::PhaseType::Vote;
                        let tx = room_state.action_tx.clone();
                        found = Some((tx, is_alive, is_vote_phase));
                        break;
                    }
                }
            }
            found
        }.unwrap_or((None, false, false));

        // 2. Validate: game started
        let tx = match action_tx {
            Some(tx) => tx,
            None => {
                let err = Message::from_json(
                    MessageType::Error,
                    &ErrorPayload { message: "game not started".to_string() },
                )?;
                return self.unicast(player_id, err).await;
            }
        };

        // 3. Validate: player is alive
        if !is_alive {
            let err = Message::from_json(
                MessageType::Error,
                &ErrorPayload { message: "dead players cannot vote".to_string() },
            )?;
            return self.unicast(player_id, err).await;
        }

        // 4. Validate: current phase is Vote
        if !is_vote_phase {
            let err = Message::from_json(
                MessageType::Error,
                &ErrorPayload { message: "voting is not allowed in this phase".to_string() },
            )?;
            return self.unicast(player_id, err).await;
        }

        // 5. Forward vote to Room Runner
        let action = crate::game_logic::room_task::RoomAction::Vote {
            voter_id: player_id,
            target_id: req.target_id,
        };

        if let Err(e) = tx.send(action) {
            error!(player_id = %player_id, error = %e, "Failed to send Vote to RoomRunner");
            let err = Message::from_json(
                MessageType::Error,
                &ErrorPayload { message: "game not started".to_string() },
            )?;
            return self.unicast(player_id, err).await;
        }

        info!(player_id = %player_id, target = %req.target_id, "Vote forwarded to RoomRunner");
        Ok(())
    }

    /// Handle 0x32 NightAction.
    ///
    /// Validates player is alive, phase is Night, and role has a night-active skill.
    /// Forwards to RoomRunner via action_tx. Full implementation in Task 13.
    async fn handle_night_action(&self, player_id: Uuid, msg: Message) -> Result<()> {
        let req: NightActionRequest = msg.parse_json().map_err(|e| {
            anyhow!("NightActionRequest deserialize failed: {}", e)
        })?;

        debug!(
            player_id = %player_id,
            room_id = %req.room_id,
            action_type = ?req.action_type,
            "NightAction received"
        );

        // 1. Find the player's room and validate state
        let (action_tx, is_alive, is_night_phase, has_night_skill) = {
            let state = self.app_state.read().await;
            let mut found: Option<(
                Option<mpsc::UnboundedSender<crate::game_logic::room_task::RoomAction>>,
                bool,
                bool,
                bool,
            )> = None;

            for (_room_id, room_state) in &state.rooms {
                if let Some(game_state) = &room_state.game_state {
                    if let Some(participant) = game_state.participants.get(&player_id) {
                        let is_alive = participant.model.is_alive;
                        let is_night_phase = game_state.phase_machine.current_phase
                            == crate::game_logic::phase_machine::PhaseType::Night;
                        // A role has a night action if it has skill_uses > 0
                        let has_night_skill = participant
                            .role
                            .as_ref()
                            .map(|r| r.role_type != crate::game_logic::roles::RoleType::Villager
                                  && r.role_type != crate::game_logic::roles::RoleType::Fool)
                            .unwrap_or(false);
                        let tx = room_state.action_tx.clone();
                        found = Some((tx, is_alive, is_night_phase, has_night_skill));
                        break;
                    }
                }
            }
            found
        }.unwrap_or((None, false, false, false));

        // 2. Validate: game started
        let tx = match action_tx {
            Some(tx) => tx,
            None => {
                let err = Message::from_json(
                    MessageType::Error,
                    &ErrorPayload { message: "game not started".to_string() },
                )?;
                return self.unicast(player_id, err).await;
            }
        };

        // 3. Validate: player is alive
        if !is_alive {
            let err = Message::from_json(
                MessageType::Error,
                &ErrorPayload { message: "dead players cannot perform actions".to_string() },
            )?;
            return self.unicast(player_id, err).await;
        }

        // 4. Validate: current phase is Night
        if !is_night_phase {
            let err = Message::from_json(
                MessageType::Error,
                &ErrorPayload { message: "night actions are not allowed in this phase".to_string() },
            )?;
            return self.unicast(player_id, err).await;
        }

        // 5. Validate: role has a night-active skill
        if !has_night_skill {
            let err = Message::from_json(
                MessageType::Error,
                &ErrorPayload { message: "your role has no night action".to_string() },
            )?;
            return self.unicast(player_id, err).await;
        }

        // 6. Forward action to Room Runner
        let action = crate::game_logic::room_task::RoomAction::NightAction {
            actor_id: player_id,
            action_type: req.action_type,
            target_id: req.target_id,
        };

        if let Err(e) = tx.send(action) {
            error!(player_id = %player_id, error = %e, "Failed to send NightAction to RoomRunner");
            let err = Message::from_json(
                MessageType::Error,
                &ErrorPayload { message: "game not started".to_string() },
            )?;
            return self.unicast(player_id, err).await;
        }

        info!(
            player_id = %player_id,
            action_type = %req.action_type,
            "NightAction forwarded to RoomRunner"
        );
        Ok(())
    }

    // ─── Keep-alive handler ───────────────────────────────────────────────────

    /// Handle 0x50 Heartbeat — echo back a Heartbeat response.
    async fn handle_heartbeat(&self, player_id: Uuid, _msg: Message) -> Result<()> {
        debug!(player_id = %player_id, "Heartbeat received");

        let now = SystemTime::now()
            .duration_since(SystemTime::UNIX_EPOCH)
            .unwrap_or_default()
            .as_secs();

        let resp = Message::from_json(
            MessageType::Heartbeat,
            &HeartbeatPayload { timestamp: now },
        )?;
        self.unicast(player_id, resp).await
    }

    // ─── Disconnect handler ───────────────────────────────────────────────────

    /// Handle 0x70 Disconnect — clean up player from registry and AppState.
    async fn handle_disconnect(&self, player_id: Uuid) -> Result<()> {
        info!(player_id = %player_id, "Disconnect received — cleaning up");

        // Remove from connection registry
        self.registry.remove(&player_id);

        // Set online_status = 'offline' in DB
        let db_pool = {
            let state = self.app_state.read().await;
            state.db_pool.clone()
        };
        if let Err(e) = Self::update_online_status(&db_pool, &player_id, "offline").await {
            error!(player_id = %player_id, error = %e, "Failed to set offline status on disconnect");
        }

        Ok(())
    }

    // ─── Database helper functions ────────────────────────────────────────────

    /// Insert a new player record into the `players` table.
    ///
    /// Returns the `player_id` passed in (for chaining convenience).
    /// Requirements: 11.1, 11.3
    pub async fn register_player(
        pool: &sqlx::PgPool,
        player_id: &Uuid,
        username: &str,
        password_hash: &str,
    ) -> Result<()> {
        sqlx::query(
            "INSERT INTO players (player_id, username, password_hash, online_status) \
             VALUES ($1::uuid, $2, $3, 'offline')",
        )
        .bind(player_id)
        .bind(username)
        .bind(password_hash)
        .execute(pool)
        .await
        .map_err(|e| anyhow!("register_player DB error: {}", e))?;
        Ok(())
    }

    /// Look up a player by username.
    ///
    /// Returns `(player_id, password_hash)` if found, or `None`.
    /// Requirements: 11.1, 12.3
    pub async fn find_player_by_username(
        pool: &sqlx::PgPool,
        username: &str,
    ) -> Result<Option<(Uuid, String)>> {
        use sqlx::Row;
        let row = sqlx::query(
            "SELECT player_id, password_hash \
             FROM players WHERE username = $1",
        )
        .bind(username)
        .fetch_optional(pool)
        .await
        .map_err(|e| anyhow!("find_player_by_username DB error: {}", e))?;

        Ok(row.map(|r| {
            let pid: Uuid = r.try_get("player_id").unwrap_or_else(|_| Uuid::nil());
            let hash: String = r.try_get("password_hash").unwrap_or_default();
            (pid, hash)
        }))
    }

    /// Update a player's `online_status` column.
    ///
    /// Requirements: 12.3, 12.4
    pub async fn update_online_status(
        pool: &sqlx::PgPool,
        player_id: &Uuid,
        status: &str,
    ) -> Result<()> {
        sqlx::query(
            "UPDATE players SET online_status = $1 WHERE player_id = $2::uuid",
        )
        .bind(status)
        .bind(player_id)
        .execute(pool)
        .await
        .map_err(|e| anyhow!("update_online_status DB error: {}", e))?;
        Ok(())
    }

    /// Insert a new room record into the `rooms` table.
    ///
    /// Returns the `room_id` passed in.
    /// Requirements: 11.1
    pub async fn create_room(
        pool: &sqlx::PgPool,
        room_id: &Uuid,
        owner_id: &Uuid,
        room_name: &str,
        is_public: bool,
    ) -> Result<Uuid> {
        let room_type = if is_public { "PUBLIC" } else { "PRIVATE" };
        sqlx::query(
            "INSERT INTO rooms (room_id, owner_id, room_name, max_players, room_type, room_status) \
             VALUES ($1::uuid, $2::uuid, $3, 16, $4, 'WAITING')",
        )
        .bind(room_id)
        .bind(owner_id)
        .bind(room_name)
        .bind(room_type)
        .execute(pool)
        .await
        .map_err(|e| anyhow!("create_room DB error: {}", e))?;
        Ok(*room_id)
    }

    /// Insert a `room_members` record for a player joining a room.
    ///
    /// Requirements: 11.1
    pub async fn add_room_member(
        pool: &sqlx::PgPool,
        room_member_id: &Uuid,
        room_id: &Uuid,
        player_id: &Uuid,
    ) -> Result<()> {
        sqlx::query(
            "INSERT INTO room_members (room_member_id, room_id, player_id, member_status, joined_at) \
             VALUES ($1::uuid, $2::uuid, $3::uuid, 'JOINED', NOW())",
        )
        .bind(room_member_id)
        .bind(room_id)
        .bind(player_id)
        .execute(pool)
        .await
        .map_err(|e| anyhow!("add_room_member DB error: {}", e))?;
        Ok(())
    }

    /// Insert a new game record into the `games` table.
    ///
    /// Returns the `game_id` passed in.
    /// Requirements: 18.1
    pub async fn create_game(
        pool: &sqlx::PgPool,
        game_id: &Uuid,
        room_id: &Uuid,
        random_seed: i64,
    ) -> Result<Uuid> {
        sqlx::query(
            "INSERT INTO games (game_id, room_id, game_status, random_seed, started_at) \
             VALUES ($1::uuid, $2::uuid, 'ONGOING', $3, NOW())",
        )
        .bind(game_id)
        .bind(room_id)
        .bind(random_seed)
        .execute(pool)
        .await
        .map_err(|e| anyhow!("create_game DB error: {}", e))?;
        Ok(*game_id)
    }

    /// Insert a `game_participants` record for a player in a game.
    ///
    /// Requirements: 18.1
    pub async fn insert_game_participant(
        pool: &sqlx::PgPool,
        game_id: &Uuid,
        player_id: &Uuid,
        role_code: &str,
        seat_number: i32,
    ) -> Result<()> {
        sqlx::query(
            "INSERT INTO game_participants (game_id, player_id, role_id, seat_number) \
             VALUES ($1::uuid, $2::uuid, \
                     (SELECT role_id FROM roles WHERE role_code = $3), \
                     $4)",
        )
        .bind(game_id)
        .bind(player_id)
        .bind(role_code)
        .bind(seat_number)
        .execute(pool)
        .await
        .map_err(|e| anyhow!("insert_game_participant DB error: {}", e))?;
        Ok(())
    }

    /// Insert a `game_actions` record for a night action.
    ///
    /// Requirements: 18.1, 26.4
    pub async fn persist_game_action(
        pool: &sqlx::PgPool,
        game_id: &Uuid,
        phase_id: &Uuid,
        actor_id: &Uuid,
        target_id: Option<&Uuid>,
        action_type: &str,
    ) -> Result<()> {
        let action_id = Uuid::new_v4();
        sqlx::query(
            "INSERT INTO game_actions (action_id, game_id, phase_id, actor_id, target_id, action_type, created_at) \
             VALUES ($1::uuid, $2::uuid, $3, $4::uuid, $5::uuid, $6, NOW())",
        )
        .bind(&action_id)
        .bind(game_id)
        .bind(phase_id)
        .bind(actor_id)
        .bind(target_id)
        .bind(action_type)
        .execute(pool)
        .await
        .map_err(|e| anyhow!("persist_game_action DB error: {}", e))?;
        Ok(())
    }

    /// Insert a `votes` record for a player's vote during the vote phase.
    ///
    /// Requirements: 26.4
    pub async fn persist_vote(
        pool: &sqlx::PgPool,
        game_id: &Uuid,
        phase_id: &Uuid,
        voter_id: &Uuid,
        candidate_id: &Uuid,
    ) -> Result<()> {
        let vote_id = Uuid::new_v4();
        sqlx::query(
            "INSERT INTO votes (vote_id, game_id, phase_id, voter_id, candidate_id, created_at) \
             VALUES ($1::uuid, $2::uuid, $3, $4::uuid, $5::uuid, NOW())",
        )
        .bind(&vote_id)
        .bind(game_id)
        .bind(phase_id)
        .bind(voter_id)
        .bind(candidate_id)
        .execute(pool)
        .await
        .map_err(|e| anyhow!("persist_vote DB error: {}", e))?;
        Ok(())
    }

    /// Mark a player as dead in `game_participants`.
    ///
    /// Requirements: 26.4
    pub async fn mark_player_dead(
        pool: &sqlx::PgPool,
        game_id: &Uuid,
        player_id: &Uuid,
        died_at: DateTime<Utc>,
    ) -> Result<()> {
        sqlx::query(
            "UPDATE game_participants SET is_alive = false, died_at = $1 \
             WHERE game_id = $2::uuid AND player_id = $3::uuid",
        )
        .bind(died_at)
        .bind(game_id)
        .bind(player_id)
        .execute(pool)
        .await
        .map_err(|e| anyhow!("mark_player_dead DB error: {}", e))?;
        Ok(())
    }

    /// Mark a game as finished with the winning faction.
    ///
    /// Requirements: 26.4
    pub async fn finish_game(
        pool: &sqlx::PgPool,
        game_id: &Uuid,
        winner_faction: &str,
    ) -> Result<()> {
        sqlx::query(
            "UPDATE games SET game_status = 'FINISHED', winner_faction = $1, ended_at = NOW() \
             WHERE game_id = $2::uuid",
        )
        .bind(winner_faction)
        .bind(game_id)
        .execute(pool)
        .await
        .map_err(|e| anyhow!("finish_game DB error: {}", e))?;
        Ok(())
    }

    // ─── Broadcast / unicast helpers ──────────────────────────────────────────


    /// Broadcast a message to all participants in a room.
    ///
    /// Serializes once, then sends the same `Bytes` to every participant's channel.
    /// On send failure, removes the player from the registry and continues.
    /// Does not hold any locks during the send loop (Requirement 3.3).
    pub async fn broadcast_to_room(&self, room_id: &Uuid, msg: Message) -> Result<()> {
        // Collect participant IDs without holding the AppState lock during sends.
        let participant_ids: Vec<Uuid> = {
            let state = self.app_state.read().await;
            match state.rooms.get(room_id) {
                Some(room_state) => {
                    if let Some(game_state) = &room_state.game_state {
                        game_state.participants.keys().cloned().collect()
                    } else {
                        Vec::new()
                    }
                }
                None => {
                    warn!(room_id = %room_id, "broadcast_to_room: room not found");
                    return Ok(());
                }
            }
        };

        let bytes = msg.to_bytes();

        for pid in &participant_ids {
            if let Some(sender) = self.registry.get(pid) {
                if sender.send(bytes.clone()).is_err() {
                    warn!(player_id = %pid, "broadcast_to_room: channel closed, removing from registry");
                    drop(sender);
                    self.registry.remove(pid);
                }
            }
        }

        Ok(())
    }

    /// Send a message to a single player.
    ///
    /// On channel send failure, removes the player from the registry.
    pub async fn unicast(&self, player_id: Uuid, msg: Message) -> Result<()> {
        let bytes = msg.to_bytes();

        match self.registry.get(&player_id) {
            Some(sender) => {
                if sender.send(bytes).is_err() {
                    warn!(player_id = %player_id, "unicast: channel closed, removing from registry");
                    drop(sender);
                    self.registry.remove(&player_id);
                    return Err(anyhow!("player {} channel closed", player_id));
                }
                Ok(())
            }
            None => {
                error!(player_id = %player_id, "unicast: player not in registry");
                Err(anyhow!("player {} not in registry", player_id))
            }
        }
    }
}

// ─── Tests ────────────────────────────────────────────────────────────────────

#[cfg(test)]
mod tests {
    use super::*;
    use bytes::Bytes;
    use dashmap::DashMap;
    use std::sync::Arc;
    use tokio::sync::mpsc;

    /// **Property 9: Broadcast Completeness**
    ///
    /// For any room with N registered participants in the Connection Registry,
    /// `broadcast_to_room(room_id, message)` attempts to send to exactly N channels,
    /// and the `Bytes` sent to each channel equals `message.to_bytes()`.
    ///
    /// **Validates: Requirements 3.1**
    #[tokio::test]
    async fn test_broadcast_completeness_p9() {
        use crate::game_logic::state::{AppState, RoomMode, RoomState};
        use crate::models::{GameStatus, Room};
        use crate::network::message::{Message, MessageType};

        // Build an in-process registry with N mock UnboundedSender channels
        let n_players: usize = 5;
        let registry: Arc<DashMap<Uuid, mpsc::UnboundedSender<Bytes>>> =
            Arc::new(DashMap::new());

        let mut receivers: Vec<(Uuid, mpsc::UnboundedReceiver<Bytes>)> = Vec::new();

        for _ in 0..n_players {
            let player_id = Uuid::new_v4();
            let (tx, rx) = mpsc::unbounded_channel::<Bytes>();
            registry.insert(player_id, tx);
            receivers.push((player_id, rx));
        }

        // Build a minimal AppState with a room containing those N participants
        let db_url = std::env::var("DATABASE_URL")
            .unwrap_or_else(|_| "postgres://localhost/test".to_string());
        // We can't connect to a real DB in a unit test, so we skip DB-dependent
        // parts and build AppState directly with a fake pool reference.
        // Instead, we test broadcast_to_room by constructing a Dispatcher with
        // a real registry and a GameState containing the N participants.

        // Use a mock pool — we won't actually query the DB in this test.
        // We create the pool lazily; if it fails to connect, we skip the test.
        let pool_result = sqlx::PgPool::connect_lazy(&db_url);
        let db_pool = match pool_result {
            Ok(p) => p,
            Err(_) => {
                // Skip test if no DB available
                return;
            }
        };

        let app_state = AppState::new(db_pool);

        // Build a GameState with N participants
        let room_id = Uuid::new_v4();
        let mut participants = std::collections::HashMap::new();
        for i in 0..n_players {
            let pid = receivers[i].0;
            participants.insert(
                pid,
                crate::game_logic::state::ParticipantInfo {
                    player_id: pid,
                    username: format!("User{}", i),
                    is_alive: true,
                    role: Some(crate::game_logic::roles::Role::new(crate::game_logic::roles::RoleType::Villager)),
                    is_online: true,
                },
            );
        }

        let mut game_state = crate::game_logic::state::GameState::new(room_id);
        game_state.participants = participants;

        let room = crate::models::Room {
            room_id,
            room_name: "Test Room".to_string(),
            max_players: 16,
            room_type: "PUBLIC".to_string(),
            room_status: crate::models::GameStatus::Playing,
            created_at: Utc::now(),
            started_at: Some(Utc::now()),
            ended_at: None,
            owner_id: receivers[0].0,
        };

        {
            let mut state = app_state.write().await;
            state.rooms.insert(
                room_id,
                RoomState {
                    room,
                    game_state: Some(game_state),
                    host_id: receivers[0].0,
                    action_tx: None,
                    room_mode: RoomMode::Custom,
                    lobby_start_time: None,
                },
            );
        }

        let dispatcher = Dispatcher::new(app_state, Arc::clone(&registry));

        // Build a test message
        let test_msg = Message::from_json(
            MessageType::ChatMessage,
            &ErrorPayload { message: "broadcast test".to_string() },
        )
        .unwrap();
        let expected_bytes = test_msg.to_bytes();

        // Broadcast to the room
        dispatcher
            .broadcast_to_room(&room_id, test_msg)
            .await
            .unwrap();

        // Assert all N receivers got exactly the expected bytes
        let mut received_count = 0;
        for (_pid, mut rx) in receivers {
            match rx.try_recv() {
                Ok(bytes) => {
                    assert_eq!(
                        bytes, expected_bytes,
                        "Bytes received by player do not match expected message bytes"
                    );
                    received_count += 1;
                }
                Err(_) => {
                    // Channel had no message — this player was not reached
                }
            }
        }

        assert_eq!(
            received_count, n_players,
            "broadcast_to_room should send to exactly {} channels, but sent to {}",
            n_players, received_count
        );
    }
}
