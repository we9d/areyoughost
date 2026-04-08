//! # End-to-End Integration Test: Full Game Loop
//!
//! This test verifies the complete multiplayer game flow:
//! 1. Two clients connect and authenticate
//! 2. Client 1 creates a room, Client 2 joins
//! 3. Both receive RoomStateSync with 2 participants
//! 4. Client 1 starts the game
//! 5. Both receive role assignments and Night phase begins
//! 6. Night phase resolves, Day phase begins
//! 7. Day phase transitions to Vote phase
//! 8. Vote phase resolves and transitions back to Night
//!
//! Requirements: 10.1, 10.2, 10.3, 10.4, 10.5

use anyhow::Result;
use bytes::Bytes;
use dashmap::DashMap;
use std::sync::Arc;
use std::time::Duration;
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::{TcpListener, TcpStream};
use tokio::time::timeout;

use crate::game_logic::state::AppState;
use crate::network::message::{
    Message, MessageType, LoginRequest, LoginResponse,
    RoomStateSync, GamePhaseChange, GameEvent,
};
use crate::network::tcp_server::TcpServer;

/// Helper to read a complete Areyoughost frame from a socket
async fn read_frame(socket: &mut TcpStream) -> Result<Message> {
    let mut buf = vec![0u8; 4096];
    let n = socket.read(&mut buf).await?;
    if n == 0 {
        anyhow::bail!("Socket EOF");
    }
    buf.truncate(n);
    Message::from_bytes(Bytes::from(buf))
}

/// Helper to send a message over a socket
async fn send_message(socket: &mut TcpStream, msg: Message) -> Result<()> {
    let bytes = msg.to_bytes();
    socket.write_all(&bytes).await?;
    Ok(())
}

// Test payload structs
#[derive(serde::Serialize, serde::Deserialize)]
struct CreateRoomRequest {
    room_name: String,
    is_public: bool,
}

#[derive(serde::Serialize, serde::Deserialize)]
struct CreateRoomResponse {
    success: bool,
    room_id: Option<String>,
    error: Option<String>,
}

#[derive(serde::Serialize, serde::Deserialize)]
struct JoinRoomRequest {
    room_id: String,
}

#[derive(serde::Serialize, serde::Deserialize)]
struct RoleResp {
    success: bool,
    room_id: String,
    role_code: String,
    role_name: String,
    faction: String,
    description: String,
}

#[derive(serde::Serialize, serde::Deserialize)]
struct StartGameReq {
    room_id: String,
}

#[tokio::test]
async fn test_full_game_loop_two_clients() -> Result<()> {
    // ─── Setup: Create in-process TCP server on random port ──────────────────
    let listener = TcpListener::bind("127.0.0.1:0").await?;
    let addr = listener.local_addr()?;
    let port = addr.port();
    println!("Test server listening on 127.0.0.1:{}", port);

    // Create AppState with a test database pool (or mock)
    // For this test, we'll use a minimal in-memory setup
    let db_pool = {
        // In a real test, this would connect to a test database
        // For now, we'll create a mock pool or skip DB operations
        // This requires DATABASE_URL to be set or we mock it
        match sqlx::postgres::PgPoolOptions::new()
            .max_connections(1)
            .connect("postgres://postgres:postgres@localhost:5432/test_db")
            .await
        {
            Ok(pool) => pool,
            Err(_) => {
                // Skip test if database is not available
                println!("Skipping test: database not available");
                return Ok(());
            }
        }
    };

    let app_state = AppState::new(db_pool);
    let registry: Arc<DashMap<String, tokio::sync::mpsc::UnboundedSender<Bytes>>> = Arc::new(DashMap::new());

    // Spawn the TCP server in a background task
    let server = TcpServer::bind(&format!("127.0.0.1:{}", port), Arc::clone(&app_state))
        .await?;
    let registry_clone = server.registry();

    tokio::spawn(async move {
        server.run().await;
    });

    // Give the server a moment to start
    tokio::time::sleep(Duration::from_millis(100)).await;

    // ─── Client 1: Connect and Login ──────────────────────────────────────────
    let mut client1 = TcpStream::connect(format!("127.0.0.1:{}", port)).await?;
    println!("Client 1 connected");

    // Send LoginRequest
    let login_req = Message::from_json(
        MessageType::LoginRequest,
        &LoginRequest {
            username: "player1".to_string(),
            password: "password1".to_string(),
        },
    )?;
    send_message(&mut client1, login_req).await?;

    // Receive LoginResponse
    let login_resp = timeout(Duration::from_secs(5), read_frame(&mut client1)).await??;
    assert_eq!(login_resp.msg_type, MessageType::LoginResponse);
    let login_data: LoginResponse = login_resp.parse_json()?;
    assert!(login_data.success);
    let session_id_1 = login_data.session_id.clone().expect("session_id");
    let player_id_1 = login_data.player_id.clone().expect("player_id");
    println!("Client 1 logged in: player_id={}, session_id={}", player_id_1, session_id_1);

    // ─── Client 2: Connect and Login ──────────────────────────────────────────
    let mut client2 = TcpStream::connect(format!("127.0.0.1:{}", port)).await?;
    println!("Client 2 connected");

    let login_req = Message::from_json(
        MessageType::LoginRequest,
        &LoginRequest {
            username: "player2".to_string(),
            password: "password2".to_string(),
        },
    )?;
    send_message(&mut client2, login_req).await?;

    let login_resp = timeout(Duration::from_secs(5), read_frame(&mut client2)).await??;
    assert_eq!(login_resp.msg_type, MessageType::LoginResponse);
    let login_data: LoginResponse = login_resp.parse_json()?;
    assert!(login_data.success);
    let session_id_2 = login_data.session_id.clone().expect("session_id");
    let player_id_2 = login_data.player_id.clone().expect("player_id");
    println!("Client 2 logged in: player_id={}, session_id={}", player_id_2, session_id_2);

    // ─── Client 1: Create Room ────────────────────────────────────────────────
    let create_room_req = Message::from_json(
        MessageType::CreateRoomRequest,
        &CreateRoomRequest {
            room_name: "Test Game".to_string(),
            is_public: false,
        },
    )?;
    send_message(&mut client1, create_room_req).await?;

    let create_resp = timeout(Duration::from_secs(5), read_frame(&mut client1)).await??;
    assert_eq!(create_resp.msg_type, MessageType::CreateRoomResponse);
    let create_data: CreateRoomResponse = create_resp.parse_json()?;
    assert!(create_data.success);
    let room_id = create_data.room_id.clone().expect("room_id");
    println!("Room created: room_id={}", room_id);

    // ─── Client 2: Join Room ──────────────────────────────────────────────────
    let join_room_req = Message::from_json(
        MessageType::JoinRoomRequest,
        &JoinRoomRequest {
            room_id: room_id.clone(),
        },
    )?;
    send_message(&mut client2, join_room_req).await?;

    // ─── Both clients should receive RoomStateSync (0x20) ─────────────────────
    // Client 1 receives it (broadcast to room)
    let room_sync_1 = timeout(Duration::from_secs(5), read_frame(&mut client1)).await??;
    assert_eq!(room_sync_1.msg_type, MessageType::RoomStateSync);
    let room_sync_data_1: RoomStateSync = room_sync_1.parse_json()?;
    assert_eq!(room_sync_data_1.participants.len(), 2);
    println!("Client 1 received RoomStateSync with {} participants", room_sync_data_1.participants.len());

    // Client 2 receives it (broadcast to room)
    let room_sync_2 = timeout(Duration::from_secs(5), read_frame(&mut client2)).await??;
    assert_eq!(room_sync_2.msg_type, MessageType::RoomStateSync);
    let room_sync_data_2: RoomStateSync = room_sync_2.parse_json()?;
    assert_eq!(room_sync_data_2.participants.len(), 2);
    println!("Client 2 received RoomStateSync with {} participants", room_sync_data_2.participants.len());

    // ─── Client 1 (Host): Start Game ──────────────────────────────────────────
    let start_game_req = Message::from_json(
        MessageType::RoomListResponse, // 0x11 repurposed as StartGame
        &StartGameReq {
            room_id: room_id.clone(),
        },
    )?;
    send_message(&mut client1, start_game_req).await?;

    // ─── Both clients should receive JoinRoomResponse (0x15) with role ────────
    let role_resp_1 = timeout(Duration::from_secs(5), read_frame(&mut client1)).await??;
    assert_eq!(role_resp_1.msg_type, MessageType::JoinRoomResponse);
    let role_data_1: RoleResp = role_resp_1.parse_json()?;
    assert!(role_data_1.success);
    println!("Client 1 received role: {}", role_data_1.role_name);

    let role_resp_2 = timeout(Duration::from_secs(5), read_frame(&mut client2)).await??;
    assert_eq!(role_resp_2.msg_type, MessageType::JoinRoomResponse);
    let role_data_2: RoleResp = role_resp_2.parse_json()?;
    assert!(role_data_2.success);
    println!("Client 2 received role: {}", role_data_2.role_name);

    // ─── Both clients should receive GamePhaseChange (0x33) for Night phase ───
    let phase_change_1 = timeout(Duration::from_secs(5), read_frame(&mut client1)).await??;
    assert_eq!(phase_change_1.msg_type, MessageType::GamePhaseChange);
    let phase_data_1: GamePhaseChange = phase_change_1.parse_json()?;
    assert_eq!(phase_data_1.phase, crate::game_logic::phase_machine::PhaseType::Night);
    assert_eq!(phase_data_1.day_number, 1);
    assert_eq!(phase_data_1.duration_secs, 20);
    println!("Client 1 received GamePhaseChange: Night phase, {} seconds", phase_data_1.duration_secs);

    let phase_change_2 = timeout(Duration::from_secs(5), read_frame(&mut client2)).await??;
    assert_eq!(phase_change_2.msg_type, MessageType::GamePhaseChange);
    let phase_data_2: GamePhaseChange = phase_change_2.parse_json()?;
    assert_eq!(phase_data_2.phase, crate::game_logic::phase_machine::PhaseType::Night);
    assert_eq!(phase_data_2.day_number, 1);
    assert_eq!(phase_data_2.duration_secs, 20);
    println!("Client 2 received GamePhaseChange: Night phase, {} seconds", phase_data_2.duration_secs);

    // ─── Wait for Night phase to resolve (20 seconds or mocked) ───────────────
    // In a real test, we'd use tokio::time::pause() to speed this up
    // For now, we'll wait a shorter time and check for GameEvent
    println!("Waiting for Night phase resolution...");
    tokio::time::sleep(Duration::from_millis(500)).await;

    // ─── Both clients should receive GameEvent (0x34) for night resolution ────
    let game_event_1 = timeout(Duration::from_secs(5), read_frame(&mut client1)).await??;
    assert_eq!(game_event_1.msg_type, MessageType::GameEvent);
    let event_data_1: GameEvent = game_event_1.parse_json()?;
    println!("Client 1 received GameEvent: {:?}", event_data_1.event_type);

    let game_event_2 = timeout(Duration::from_secs(5), read_frame(&mut client2)).await??;
    assert_eq!(game_event_2.msg_type, MessageType::GameEvent);
    let event_data_2: GameEvent = game_event_2.parse_json()?;
    println!("Client 2 received GameEvent: {:?}", event_data_2.event_type);

    // ─── Both clients should receive GamePhaseChange (0x33) for Day phase ─────
    let phase_change_day_1 = timeout(Duration::from_secs(5), read_frame(&mut client1)).await??;
    assert_eq!(phase_change_day_1.msg_type, MessageType::GamePhaseChange);
    let phase_data_day_1: GamePhaseChange = phase_change_day_1.parse_json()?;
    assert_eq!(phase_data_day_1.phase, crate::game_logic::phase_machine::PhaseType::Day);
    assert_eq!(phase_data_day_1.day_number, 1);
    assert_eq!(phase_data_day_1.duration_secs, 60);
    println!("Client 1 received GamePhaseChange: Day phase, {} seconds", phase_data_day_1.duration_secs);

    let phase_change_day_2 = timeout(Duration::from_secs(5), read_frame(&mut client2)).await??;
    assert_eq!(phase_change_day_2.msg_type, MessageType::GamePhaseChange);
    let phase_data_day_2: GamePhaseChange = phase_change_day_2.parse_json()?;
    assert_eq!(phase_data_day_2.phase, crate::game_logic::phase_machine::PhaseType::Day);
    assert_eq!(phase_data_day_2.day_number, 1);
    assert_eq!(phase_data_day_2.duration_secs, 60);
    println!("Client 2 received GamePhaseChange: Day phase, {} seconds", phase_data_day_2.duration_secs);

    // ─── Wait for Day phase to resolve (60 seconds or mocked) ──────────────────
    println!("Waiting for Day phase resolution...");
    tokio::time::sleep(Duration::from_millis(500)).await;

    // ─── Both clients should receive GamePhaseChange (0x33) for Vote phase ────
    let phase_change_vote_1 = timeout(Duration::from_secs(5), read_frame(&mut client1)).await??;
    assert_eq!(phase_change_vote_1.msg_type, MessageType::GamePhaseChange);
    let phase_data_vote_1: GamePhaseChange = phase_change_vote_1.parse_json()?;
    assert_eq!(phase_data_vote_1.phase, crate::game_logic::phase_machine::PhaseType::Vote);
    assert_eq!(phase_data_vote_1.duration_secs, 15);
    println!("Client 1 received GamePhaseChange: Vote phase, {} seconds", phase_data_vote_1.duration_secs);

    let phase_change_vote_2 = timeout(Duration::from_secs(5), read_frame(&mut client2)).await??;
    assert_eq!(phase_change_vote_2.msg_type, MessageType::GamePhaseChange);
    let phase_data_vote_2: GamePhaseChange = phase_change_vote_2.parse_json()?;
    assert_eq!(phase_data_vote_2.phase, crate::game_logic::phase_machine::PhaseType::Vote);
    assert_eq!(phase_data_vote_2.duration_secs, 15);
    println!("Client 2 received GamePhaseChange: Vote phase, {} seconds", phase_data_vote_2.duration_secs);

    // ─── Wait for Vote phase to resolve (15 seconds or mocked) ────────────────
    println!("Waiting for Vote phase resolution...");
    tokio::time::sleep(Duration::from_millis(500)).await;

    // ─── Both clients should receive GameEvent (0x34) for vote result ─────────
    let vote_event_1 = timeout(Duration::from_secs(5), read_frame(&mut client1)).await??;
    assert_eq!(vote_event_1.msg_type, MessageType::GameEvent);
    let vote_data_1: GameEvent = vote_event_1.parse_json()?;
    println!("Client 1 received GameEvent (vote result): {:?}", vote_data_1.event_type);

    let vote_event_2 = timeout(Duration::from_secs(5), read_frame(&mut client2)).await??;
    assert_eq!(vote_event_2.msg_type, MessageType::GameEvent);
    let vote_data_2: GameEvent = vote_event_2.parse_json()?;
    println!("Client 2 received GameEvent (vote result): {:?}", vote_data_2.event_type);

    // ─── Both clients should receive GamePhaseChange (0x33) for Night phase ───
    let phase_change_night_2_1 = timeout(Duration::from_secs(5), read_frame(&mut client1)).await??;
    assert_eq!(phase_change_night_2_1.msg_type, MessageType::GamePhaseChange);
    let phase_data_night_2_1: GamePhaseChange = phase_change_night_2_1.parse_json()?;
    assert_eq!(phase_data_night_2_1.phase, crate::game_logic::phase_machine::PhaseType::Night);
    assert_eq!(phase_data_night_2_1.day_number, 2);
    println!("Client 1 received GamePhaseChange: Night phase 2");

    let phase_change_night_2_2 = timeout(Duration::from_secs(5), read_frame(&mut client2)).await??;
    assert_eq!(phase_change_night_2_2.msg_type, MessageType::GamePhaseChange);
    let phase_data_night_2_2: GamePhaseChange = phase_change_night_2_2.parse_json()?;
    assert_eq!(phase_data_night_2_2.phase, crate::game_logic::phase_machine::PhaseType::Night);
    assert_eq!(phase_data_night_2_2.day_number, 2);
    println!("Client 2 received GamePhaseChange: Night phase 2");

    println!("✓ Full game loop test completed successfully!");
    Ok(())
}
