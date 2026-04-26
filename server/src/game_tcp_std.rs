//! Framed TCP game port: **same auth and `handle_client_message` path as WebSocket** (`/ws`).
//! Frames: `u32` big-endian length + UTF-8 JSON (client `ClientMessage` / server `ServerMessage`).
//!
//! Underlying socket uses [`tcp_framing_std::configure_stream`] (read/write timeouts, nodelay)
//! then Tokio split halves for concurrent framed writes (outbound channel) and reads.
//!
//! Env (milliseconds; `0` = no timeout on that direction):
//! - `STD_GAME_TCP_READ_TIMEOUT_MS` — default `120_000`
//! - `STD_GAME_TCP_WRITE_TIMEOUT_MS` — default `60_000`

use std::io;
use std::sync::Arc;

use axum::extract::ws::Message;
use serde_json::json;
use tokio::io::AsyncWriteExt;
use tokio::net::TcpListener;
use tokio::sync::watch;

use crate::session_auth::authenticate_first_message;
use crate::state::manager::AppState;
use crate::tcp_framing_async;
use crate::tcp_framing_std::{self, FrameRead};
use crate::ws::handle_client_message;
use crate::ws::messages::{ClientMessage, ServerMessage};

const DEFAULT_READ_TIMEOUT_MS: u64 = 120_000;
const DEFAULT_WRITE_TIMEOUT_MS: u64 = 60_000;

const ERR_FRAME_TOO_LARGE: &[u8] = br#"{"type":"error","payload":{"code":"FRAME_TOO_LARGE","message":"frame exceeds max size"},"data":{"code":"FRAME_TOO_LARGE","message":"frame exceeds max size"}}"#;

fn parse_timeout_ms(var: &str, default_ms: u64) -> u64 {
    std::env::var(var)
        .ok()
        .and_then(|s| s.parse::<u64>().ok())
        .unwrap_or(default_ms)
}

pub async fn run_tcp_listener(
    bind: String,
    state: Arc<AppState>,
    mut shutdown_rx: watch::Receiver<bool>,
) -> io::Result<()> {
    let read_timeout_ms = parse_timeout_ms("STD_GAME_TCP_READ_TIMEOUT_MS", DEFAULT_READ_TIMEOUT_MS);
    let write_timeout_ms =
        parse_timeout_ms("STD_GAME_TCP_WRITE_TIMEOUT_MS", DEFAULT_WRITE_TIMEOUT_MS);
    let listener = TcpListener::bind(&bind).await?;
    tracing::info!(
        "Framed TCP game on {} (same protocol as WS over u32_be length + JSON); read_timeout_ms={} write_timeout_ms={}",
        bind,
        read_timeout_ms,
        write_timeout_ms
    );
    loop {
        tokio::select! {
            _ = shutdown_rx.changed() => {
                if *shutdown_rx.borrow() {
                    tracing::info!("Framed TCP shutdown signal received");
                    break;
                }
            }
            accepted = listener.accept() => {
                let (stream, addr) = accepted?;
                tracing::debug!("Framed TCP peer {}", addr);
                let st = state.clone();
                tokio::spawn(async move {
                    if let Err(e) = handle_tcp_session(stream, st, read_timeout_ms, write_timeout_ms).await
                    {
                        tracing::debug!("Framed TCP session I/O error: {}", e);
                    }
                });
            }
        }
    }
    Ok(())
}

async fn handle_tcp_session(
    stream: tokio::net::TcpStream,
    state: Arc<AppState>,
    read_timeout_ms: u64,
    write_timeout_ms: u64,
) -> io::Result<()> {
    let std_stream = stream.into_std()?;
    tcp_framing_std::configure_stream(&std_stream, read_timeout_ms, write_timeout_ms)?;
    let stream = tokio::net::TcpStream::from_std(std_stream)?;
    let (mut read_half, mut write_half) = tokio::io::split(stream);

    let first = match tcp_framing_async::read_frame(&mut read_half).await? {
        FrameRead::Payload(b) => b,
        FrameRead::Closed | FrameRead::ConnectionLost | FrameRead::ReadTimedOut => return Ok(()),
        FrameRead::RejectedTooLarge => {
            let _ = tcp_framing_async::write_frame(&mut write_half, ERR_FRAME_TOO_LARGE).await;
            return Ok(());
        }
    };

    let text = String::from_utf8_lossy(&first);
    let (player_id, username) = match authenticate_first_message(&text, &state).await {
        Ok(p) => p,
        Err(sm) => {
            let body = serde_json::to_vec(&sm).unwrap_or_else(|_| b"{}".to_vec());
            let _ = tcp_framing_async::write_frame(&mut write_half, &body).await;
            return Ok(());
        }
    };

    let (tx, mut rx) = tokio::sync::mpsc::unbounded_channel::<Message>();

    let write_task = tokio::spawn(async move {
        while let Some(msg) = rx.recv().await {
            if let Message::Text(t) = msg {
                if tcp_framing_async::write_frame(&mut write_half, t.as_bytes())
                    .await
                    .is_err()
                {
                    break;
                }
            }
        }
        let _ = write_half.shutdown().await;
    });

    state.connections.insert(player_id.clone(), tx.clone());
    let resumed = state.consume_pending_disconnect(&player_id);
    let resume_token = state.issue_resume_token(&player_id);

    let _ = tx.send(Message::Text(
        serde_json::to_string(&ServerMessage::new(
            "auth.ok",
            json!({
                "playerId": player_id,
                "username": username,
                "resumeToken": resume_token
            }),
        ))
        .unwrap(),
    ));

    if resumed {
        let _ = tx.send(Message::Text(
            serde_json::to_string(&ServerMessage::new(
                "session.resumed",
                json!({ "playerId": player_id }),
            ))
            .unwrap(),
        ));
        if let Some(room_id) = state.player_rooms.get(&player_id).map(|r| r.clone()) {
            if let Some(room_state) = state.get_room_state(&room_id) {
                let _ = tx.send(Message::Text(
                    serde_json::to_string(&ServerMessage::new("room.state", room_state)).unwrap(),
                ));
            }
        }
    }

    loop {
        match tcp_framing_async::read_frame(&mut read_half).await {
            Ok(FrameRead::Payload(bytes)) => {
                let text = String::from_utf8_lossy(&bytes);
                match serde_json::from_str::<ClientMessage>(&text) {
                    Ok(client_msg) => {
                        tracing::info!(
                            "TCP msg '{}' from player '{}'",
                            client_msg.msg_type,
                            player_id
                        );
                        handle_client_message(client_msg, &player_id, &username, &state, &tx).await;
                    }
                    Err(e) => {
                        tracing::error!("TCP JSON parse error: {e:?}");
                        let _ = tx.send(Message::Text(
                            serde_json::to_string(&ServerMessage::error(
                                "INVALID_MESSAGE",
                                "Failed to parse JSON",
                            ))
                            .unwrap(),
                        ));
                    }
                }
            }
            Ok(FrameRead::Closed) => {
                tracing::debug!("TCP {}: peer closed", player_id);
                break;
            }
            Ok(FrameRead::ConnectionLost) => {
                tracing::debug!("TCP {}: connection lost mid-frame", player_id);
                break;
            }
            Ok(FrameRead::ReadTimedOut) => {
                tracing::debug!("TCP {}: read timed out", player_id);
                break;
            }
            Ok(FrameRead::RejectedTooLarge) => {
                let _ = tx.send(Message::Text(
                    serde_json::to_string(&ServerMessage::error(
                        "FRAME_TOO_LARGE",
                        "frame exceeds max size",
                    ))
                    .unwrap(),
                ));
                break;
            }
            Err(e) => {
                tracing::debug!("TCP {} read I/O: {}", player_id, e);
                break;
            }
        }
    }

    tracing::info!("Framed TCP connection closed for player '{}'", player_id);
    state.connections.remove(&player_id);
    {
        let mut queue = state.queue.lock().await;
        queue.retain(|id| id != &player_id);
    }
    state.mark_pending_disconnect(&player_id);
    drop(tx);
    let _ = write_task.await;

    Ok(())
}
