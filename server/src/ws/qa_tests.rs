//! Automated checks aligned with `docs/QA_CHECKLIST.md` (social flows).
//! `game.started` broadcast is covered in `state::manager::tests::qa_game_started_broadcasts_to_two_registered_connections`.

use super::handle_client_message;
use super::messages::ClientMessage;
use crate::state::manager::AppState;
use axum::extract::ws::Message;
use serde_json::json;
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
