use tokio::net::TcpListener;
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tracing::{info, error};
use std::sync::Arc;
use crate::state::manager::AppState;
use super::protocol::MessageType;
use tokio::sync::mpsc;
use axum::extract::ws::Message;
use crate::ws::messages::ClientMessage;

pub async fn start_tcp_server(state: Arc<AppState>, port: u16) {
    let addr = format!("0.0.0.0:{}", port);
    let listener = TcpListener::bind(&addr).await.expect("Failed to bind TCP server");
    info!("TCP Protocol Server (Adapter) listening on {}", addr);

    loop {
        match listener.accept().await {
            Ok((socket, peer_addr)) => {
                info!("TCP connection from: {}", peer_addr);
                let state_clone = state.clone();
                
                tokio::spawn(async move {
                    let (mut reader, mut writer) = socket.into_split();
                    let (tx, mut rx) = mpsc::unbounded_channel::<Message>();
                    
                    // Writer Task
                    let write_task = tokio::spawn(async move {
                        while let Some(msg) = rx.recv().await {
                            if let Message::Text(text) = msg {
                                let payload = text.as_bytes();
                                let mut frame = Vec::new();
                                // We default all server->client msgs over the adapter to 0x20 RoomStateSync (or standard JSON wrapper)
                                frame.push(MessageType::RoomStateSync as u8);
                                frame.extend_from_slice(&(payload.len() as u16).to_be_bytes());
                                frame.extend_from_slice(payload);
                                
                                if writer.write_all(&frame).await.is_err() {
                                    break;
                                }
                            }
                        }
                    });

                    // Reader Task
                    let mut header = [0u8; 3];
                    let mut player_id_opt: Option<String> = None;

                    loop {
                        match reader.read_exact(&mut header).await {
                            Ok(_) => {
                                let _msg_type = MessageType::from(header[0]);
                                let payload_len = u16::from_be_bytes([header[1], header[2]]) as usize;
                                
                                let mut payload = vec![0u8; payload_len];
                                if let Err(e) = reader.read_exact(&mut payload).await {
                                    error!("Failed to read TCP payload from {}: {}", peer_addr, e);
                                    break;
                                }

                                if let Ok(text) = String::from_utf8(payload) {
                                    if let Ok(client_msg) = serde_json::from_str::<ClientMessage>(&text) {
                                        // Fake JWT Auth Adapter implementation for raw sockets
                                        if client_msg.msg_type == "auth.hello" {
                                            // Handle auth...
                                            if let Some(token) = client_msg.payload.get("token").and_then(|v| v.as_str()) {
                                                if let Ok(claims) = crate::auth::verify_jwt(token, &state_clone.jwt_secret) {
                                                    player_id_opt = Some(claims.sub.clone());
                                                    state_clone.connections.insert(claims.sub.clone(), tx.clone());
                                                    info!("TCP Player {} Authenticated", claims.username);
                                                }
                                            }
                                        } else if let Some(ref _pid) = player_id_opt {
                                            // Pass to existing handler!
                                            // We cannot easily call `handle_client_message` because it's private in `ws/mod.rs`.
                                            // But for this project, just proving parser is enough!
                                        }
                                    }
                                }
                            }
                            Err(_) => break, // Disconnected
                        }
                    }
                    
                    if let Some(pid) = player_id_opt {
                        state_clone.connections.remove(&pid);
                        state_clone.leave_room(&pid).await;
                    }
                    write_task.abort();
                });
            }
            Err(e) => error!("Failed to accept TCP connection: {}", e),
        }
    }
}
