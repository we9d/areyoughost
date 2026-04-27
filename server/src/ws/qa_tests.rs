//! Automated checks aligned with `docs/QA_CHECKLIST.md` (social flows).
//! `game.started` broadcast is covered in `state::manager::tests::qa_game_started_broadcasts_to_two_registered_connections`.

use super::handle_client_message;
use super::messages::ClientMessage;
use crate::state::manager::{AppState, PlayerInfo, Room};
use axum::extract::ws::Message;
use serde_json::json;
use serde_json::Value;
use sqlx::postgres::PgPoolOptions;
use std::sync::Arc;
use std::time::Duration;
use tokio::sync::mpsc;

fn qa_state() -> Arc<AppState> {
    let db = PgPoolOptions::new()
        .acquire_timeout(Duration::from_secs(2))
        .connect_lazy("postgres://postgres:postgres@localhost/postgres")
        .expect("lazy pool");
    AppState::new(db, "test-secret".to_string(), 90, 180, 120, 90, true)
}

fn drain_until_contains(rx: &mut mpsc::UnboundedReceiver<Message>, needle: &str) -> String {
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

fn drain_json_until_contains(rx: &mut mpsc::UnboundedReceiver<Message>, needle: &str) -> Value {
    let line = drain_until_contains(rx, needle);
    serde_json::from_str::<Value>(&line).expect("valid json message")
}

#[tokio::test]
async fn qa_invite_send_delivers_invite_received() {
    let state = qa_state();
    let host_id = "30000000-0000-4000-8000-000000000001".to_string();
    let friend_id = "30000000-0000-4000-8000-000000000002".to_string();

    let (_room_id, invite_code) = state
        .create_private_room(host_id.clone(), "Host".to_string())
        .await
        .expect("create_private_room");

    let (host_tx, mut host_rx) = mpsc::unbounded_channel::<Message>();
    let (friend_tx, mut friend_rx) = mpsc::unbounded_channel::<Message>();
    state.connections.insert(host_id.clone(), host_tx.clone());
    state.connections.insert(friend_id.clone(), friend_tx.clone());

    handle_client_message(
        ClientMessage {
            msg_type: "invite.send".to_string(),
            payload: json!({ "friendId": friend_id, "inviteCode": invite_code }),
            req_id: None,
        },
        &host_id,
        "Host",
        &state,
        &host_tx,
    )
    .await;

    let _ = drain_until_contains(&mut host_rx, "invite.sent");
    let invite_line = drain_until_contains(&mut friend_rx, "invite.received");
    assert!(invite_line.contains(&invite_code));
}

#[tokio::test]
async fn qa_invite_code_joins_friend_in_room() {
    let state = qa_state();
    let host_id = "31000000-0000-4000-8000-000000000001".to_string();
    let friend_id = "31000000-0000-4000-8000-000000000002".to_string();

    let (room_id, invite_code) = state
        .create_private_room(host_id.clone(), "Host".to_string())
        .await
        .expect("create_private_room");

    assert_eq!(
        state.resolve_invite(&invite_code).as_deref(),
        Some(room_id.as_str())
    );
    state
        .join_room(&room_id, &friend_id, "Friend".to_string())
        .await
        .expect("join_room");

    let room = state.rooms.get(&room_id).expect("room in memory");
    assert_eq!(room.players.len(), 2);
}

#[tokio::test]
async fn qa_room_sync_includes_runtime_alive_flags() {
    let state = qa_state();
    let host_id = "32000000-0000-4000-8000-000000000001".to_string();
    let guest_id = "32000000-0000-4000-8000-000000000002".to_string();
    let room_id = "42000000-0000-4000-8000-000000000010".to_string();

    state.rooms.insert(
        room_id.clone(),
        Room {
            room_id: room_id.clone(),
            players: vec![
                PlayerInfo {
                    player_id: host_id.clone(),
                    username: "Host".to_string(),
                    is_ready: true,
                    is_host: true,
                },
                PlayerInfo {
                    player_id: guest_id.clone(),
                    username: "Guest".to_string(),
                    is_ready: true,
                    is_host: false,
                },
            ],
            max_players: 8,
            is_public: true,
            status: "waiting".to_string(),
        },
    );
    state.player_rooms.insert(host_id.clone(), room_id.clone());
    state.player_rooms.insert(guest_id.clone(), room_id.clone());

    state.start_game(&room_id, &host_id).await.expect("start game");

    {
        let mut g = state.active_games.get_mut(&room_id).expect("runtime");
        g.players.get_mut(&guest_id).expect("guest state").alive = false;
    }

    let (host_tx, mut host_rx) = mpsc::unbounded_channel::<Message>();
    state.connections.insert(host_id.clone(), host_tx.clone());

    handle_client_message(
        ClientMessage {
            msg_type: "room.sync".to_string(),
            payload: json!({}),
            req_id: None,
        },
        &host_id,
        "Host",
        &state,
        &host_tx,
    )
    .await;

    let msg = drain_json_until_contains(&mut host_rx, "\"type\":\"room.state\"");
    let payload = msg["payload"].as_object().expect("room.state payload");
    let players = payload["players"].as_array().expect("players array");
    let guest = players
        .iter()
        .find(|p| p["playerId"].as_str() == Some(guest_id.as_str()))
        .expect("guest row");
    assert_eq!(guest["alive"].as_bool(), Some(false));
}

#[tokio::test]
async fn qa_room_chat_broadcasts_to_all_room_members() {
    let state = qa_state();
    let host_id = "33000000-0000-4000-8000-000000000001".to_string();
    let friend_id = "33000000-0000-4000-8000-000000000002".to_string();
    let room_id = "43000000-0000-4000-8000-000000000010".to_string();

    state.rooms.insert(
        room_id.clone(),
        Room {
            room_id: room_id.clone(),
            players: vec![
                PlayerInfo {
                    player_id: host_id.clone(),
                    username: "Host".to_string(),
                    is_ready: true,
                    is_host: true,
                },
                PlayerInfo {
                    player_id: friend_id.clone(),
                    username: "Friend".to_string(),
                    is_ready: true,
                    is_host: false,
                },
            ],
            max_players: 8,
            is_public: true,
            status: "waiting".to_string(),
        },
    );
    state.player_rooms.insert(host_id.clone(), room_id.clone());
    state.player_rooms.insert(friend_id.clone(), room_id.clone());

    let (host_tx, mut host_rx) = mpsc::unbounded_channel::<Message>();
    let (friend_tx, mut friend_rx) = mpsc::unbounded_channel::<Message>();
    state.connections.insert(host_id.clone(), host_tx.clone());
    state.connections.insert(friend_id.clone(), friend_tx.clone());

    handle_client_message(
        ClientMessage {
            msg_type: "room.chat".to_string(),
            payload: json!({ "text": "hello lobby" }),
            req_id: None,
        },
        &host_id,
        "Host",
        &state,
        &host_tx,
    )
    .await;

    let host_msg = drain_json_until_contains(&mut host_rx, "\"type\":\"room.chat_message\"");
    let friend_msg = drain_json_until_contains(&mut friend_rx, "\"type\":\"room.chat_message\"");
    for msg in [host_msg, friend_msg] {
        assert_eq!(msg["payload"]["roomId"].as_str(), Some(room_id.as_str()));
        assert_eq!(msg["payload"]["playerId"].as_str(), Some(host_id.as_str()));
        assert_eq!(msg["payload"]["username"].as_str(), Some("Host"));
        assert_eq!(msg["payload"]["text"].as_str(), Some("hello lobby"));
    }
}
