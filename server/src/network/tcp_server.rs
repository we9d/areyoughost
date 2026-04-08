use tokio::net::TcpListener;
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tracing::{info, error, warn};
use std::sync::Arc;
use crate::state::manager::{AppState, CachedRole, CachedSkill};
use areyoughost_core::network::message::{Message, MessageType, MAGIC_BYTES, LoginRequest, LoginResponse};
use areyoughost_core::Serialize;
use crate::auth::verify_password;
use uuid::Uuid;
use sqlx::Row;
use bytes::Bytes;

#[derive(Serialize)]
struct GameDataResponse {
    roles: Vec<CachedRole>,
    skills: Vec<CachedSkill>,
}

pub async fn start_tcp_server(state: Arc<AppState>, port: u16) {
    let addr = format!("0.0.0.0:{}", port);
    let listener = TcpListener::bind(&addr).await.expect("Failed to bind TCP server");
    info!("🚀 Areyoughost Binary Protocol Server listening on {}", addr);

    loop {
        match listener.accept().await {
            Ok((socket, peer_addr)) => {
                info!("Incoming TCP connection: {}", peer_addr);
                let state_clone = state.clone();
                
                tokio::spawn(async move {
                    let (mut reader, mut writer) = socket.into_split();
                    let (tx, mut rx) = tokio::sync::mpsc::unbounded_channel::<Bytes>();
                    
                    // Task 1: Write Half - Consumes from mpsc and writes to network
                    tokio::spawn(async move {
                        while let Some(bytes) = rx.recv().await {
                            if let Err(e) = writer.write_all(&bytes).await {
                                error!("TCP Writer Error: {}", e);
                                break;
                            }
                        }
                    });

                    // We need a variable to track this connection's player ID to clean up tx_map on disconnect
                    let mut current_player_id: Option<Uuid> = None;

                    loop {
                        // 1. Read Header (7 bytes: Magic[2], Type[1], Len[4])
                        let mut header_buf = [0u8; 7];
                        if let Err(_) = reader.read_exact(&mut header_buf).await {
                            break; // Disconnected
                        }

                        // Verify Magic
                        if header_buf[0..2] != MAGIC_BYTES {
                            warn!("Invalid Magic Bytes from {}: 0x{:02X} 0x{:02X}", peer_addr, header_buf[0], header_buf[1]);
                            break;
                        }

                        let _type_byte = header_buf[2];
                        let payload_len = u32::from_be_bytes([header_buf[3], header_buf[4], header_buf[5], header_buf[6]]) as usize;

                        // 2. Read Payload + CRC (payload_len + 2 bytes)
                        let mut remaining = vec![0u8; payload_len + 2];
                        if let Err(e) = reader.read_exact(&mut remaining).await {
                            error!("Failed to read TCP payload/CRC from {}: {}", peer_addr, e);
                            break;
                        }

                        // Reconstruct full message bytes
                        let mut full_msg_bytes = Vec::with_capacity(7 + payload_len + 2);
                        full_msg_bytes.extend_from_slice(&header_buf);
                        full_msg_bytes.extend_from_slice(&remaining);

                        // 3. Parse Message
                        match Message::from_bytes(Bytes::from(full_msg_bytes)) {
                            Ok(msg) => {
                                info!("Received Protocol Message: {:?} ({} bytes) from {}", msg.msg_type, payload_len, peer_addr);
                                
                                // 4. Handle Specific Messages
                                match msg.msg_type {
                                    MessageType::LoginRequest => {
                                        match msg.parse_binary::<LoginRequest>() {
                                            Ok(req) => {
                                                #[derive(sqlx::FromRow)]
                                                struct AuthRow {
                                                    player_id: Uuid,
                                                    password_hash: String,
                                                }
                                                let user_res = sqlx::query_as::<_, AuthRow>(
                                                    "SELECT player_id, password_hash FROM players WHERE username = $1"
                                                )
                                                .bind(&req.username)
                                                .fetch_optional(&state_clone.db).await;
                                                let mut auth_success = false;
                                                let mut p_id: Option<Uuid> = None;
                                                let mut err_msg: Option<String> = None;

                                                match user_res {
                                                    Ok(Some(user)) => {
                                                        match verify_password(&req.password, &user.password_hash) {
                                                            Ok(true) => {
                                                                auth_success = true;
                                                                p_id = Some(user.player_id);
                                                                current_player_id = Some(user.player_id);
                                                                state_clone.tx_map.insert(user.player_id, tx.clone());
                                                            }
                                                            _ => {
                                                                err_msg = Some("Invalid password".to_string());
                                                            }
                                                        }
                                                    }
                                                    Ok(None) => err_msg = Some("User not found".to_string()),
                                                    Err(e) => {
                                                        error!("DB error: {}", e);
                                                        err_msg = Some("Internal server error".to_string());
                                                    }
                                                }

                                                let s_uuid: Option<Uuid> = if auth_success {
                                                    let s_id = Uuid::new_v4();
                                                    if let Some(pid) = p_id {
                                                        state_clone.sessions.insert(s_id, pid);
                                                    }
                                                    Some(s_id)
                                                } else { None };

                                                 let resp = LoginResponse {
                                                    success: auth_success,
                                                    session_id: s_uuid,
                                                    player_id: p_id,
                                                    error: err_msg,
                                                };

                                                if let Ok(resp_msg) = Message::from_json(MessageType::LoginResponse, &resp) {
                                                    let _ = tx.send(resp_msg.to_bytes());
                                                    if auth_success {
                                                        info!("Login successful for {}", req.username);
                                                    }
                                                }
                                            }
                                            Err(e) => error!("Failed to parse LoginRequest: {}", e),
                                        }
                                    }
                                    MessageType::ReconnectRequest => {
                                        // Attempt to parse as Bincode first (standard requirement)
                                        let reconnect_id = match msg.parse_binary::<areyoughost_core::network::message::ReconnectRequest>() {
                                            Ok(r) => Some(r.session_id),
                                            Err(_) => {
                                                // Fallback to JSON for legacy/web support
                                                msg.parse_json::<areyoughost_core::network::message::ReconnectRequest>().ok().map(|r| r.session_id)
                                            }
                                        };

                                        let mut res = areyoughost_core::network::message::ReconnectResponse {
                                            success: false,
                                            error: Some("Invalid session".to_string()),
                                            room_id: None,
                                            phase: None,
                                            day_number: None,
                                            phase_remaining_secs: None,
                                            is_alive: None,
                                            role: None,
                                        };

                                        if let Some(s_id) = reconnect_id {
                                            if let Some(p_id) = state_clone.sessions.get(&s_id) {
                                                let player_id = *p_id;
                                                current_player_id = Some(player_id);
                                                
                                                state_clone.tx_map.insert(player_id, tx.clone());
                                                
                                                res.success = true;
                                                res.error = None;
                                                
                                                if let Some(r_id) = state_clone.player_rooms.get(&player_id) {
                                                    res.room_id = Some(*r_id);
                                                }

                                                info!("Verified TCP session attached to player {}", player_id);
                                            }
                                        }

                                        if let Ok(resp_msg) = Message::from_json(MessageType::ReconnectResponse, &res) {
                                            let _ = tx.send(resp_msg.to_bytes());
                                        }
                                    }
                                    MessageType::GetGameData => {
                                        let response_data = GameDataResponse {
                                            roles: state_clone.cached_roles.clone(),
                                            skills: state_clone.cached_skills.clone(),
                                        };
                                        if let Ok(resp_msg) = Message::from_json(MessageType::GetGameData, &response_data) {
                                            let _ = tx.send(resp_msg.to_bytes());
                                        }
                                    }
                                    MessageType::Heartbeat => {
                                        let _ = tx.send(msg.to_bytes());
                                    }
                                    // DELEGATE other messages to Dispatcher in the next phase
                                    _ => {
                                        crate::network::dispatcher::dispatch_command(msg, &state_clone, &current_player_id, &tx).await;
                                    }
                                }
                            }
                            Err(e) => {
                                error!("Protocol Error from {}: {}", peer_addr, e);
                                break;
                            }
                        }
                    }

                    // Cleanup when disconnected
                    if let Some(pid) = current_player_id {
                        state_clone.tx_map.remove(&pid);
                        info!("Player {} disconnected. Removed from tx_map", pid);
                    }
                    info!("TCP Connection closed: {}", peer_addr);
                });
            }
            Err(e) => error!("Failed to accept TCP connection: {}", e),
        }
    }
}
