use std::sync::Arc;

use axum::extract::ws::{Message, WebSocket, WebSocketUpgrade};
use axum::{extract::State, response::IntoResponse};
use futures::{SinkExt, StreamExt};
use serde_json::json;
use tokio::sync::mpsc;

use crate::auth::verify_jwt;
use crate::state::manager::AppState;

pub mod messages;
use messages::{ClientMessage, ServerMessage};

pub async fn ws_handler(
    State(state): State<Arc<AppState>>,
    ws: WebSocketUpgrade,
) -> impl IntoResponse {
    ws.on_upgrade(move |socket| handle_socket(socket, state))
}

pub async fn handle_socket(socket: WebSocket, state: Arc<AppState>) {
    tracing::info!("New WebSocket connection established");

    let (mut sender, mut receiver) = socket.split();
    let (tx, mut rx) = mpsc::unbounded_channel::<Message>();

    // Forward outgoing messages to socket
    let send_task = tokio::spawn(async move {
        while let Some(msg) = rx.recv().await {
            if sender.send(msg).await.is_err() {
                break;
            }
        }
    });

    // ── Phase 3: verify JWT before allowing any other message ─────
    let (player_id, username) = match wait_for_auth(&mut receiver, &tx, &state.jwt_secret).await {
        Some(claims) => (claims.0, claims.1),
        None => {
            tracing::warn!("Connection closed before authentication");
            return;
        }
    };

    tracing::info!("Player '{}' (id={}) authenticated via JWT", username, player_id);

    // Register connection
    state.connections.insert(player_id.clone(), tx.clone());

    // Confirm auth success
    let _ = tx.send(Message::Text(
        serde_json::to_string(&ServerMessage::new(
            "auth.ok",
            json!({ "playerId": player_id, "username": username }),
        ))
        .unwrap(),
    ));

    // ── Main message loop ─────────────────────────────────────────
    while let Some(msg) = receiver.next().await {
        match msg {
            Ok(Message::Text(text)) => {
                match serde_json::from_str::<ClientMessage>(&text) {
                    Ok(client_msg) => {
                        tracing::info!("Msg '{}' from player '{}'", client_msg.msg_type, player_id);
                        handle_client_message(client_msg, &player_id, &username, &state, &tx).await;
                    }
                    Err(e) => {
                        tracing::error!("JSON parse error: {e:?}");
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
            Ok(Message::Close(_)) => {
                tracing::info!("Player '{}' closed connection", player_id);
                break;
            }
            Err(e) => {
                tracing::error!("WebSocket error: {e:?}");
                break;
            }
            _ => {}
        }
    }

    // ── Cleanup ───────────────────────────────────────────────────
    tracing::info!("Cleaning up connection for player '{}'", player_id);
    state.connections.remove(&player_id);

    {
        let mut queue = state.queue.lock().await;
        queue.retain(|id| id != &player_id);
    }

    if let Some(room_id) = state.leave_room(&player_id).await {
        // Broadcast that player left to the rest of the room
        let left_msg = ServerMessage::new(
            "room.player_left",
            serde_json::json!({ "playerId": player_id }),
        );
        state.broadcast_to_room(&room_id, &serde_json::to_string(&left_msg).unwrap());

        // Broadcast updated room state
        if let Some(room_state) = state.get_room_state(&room_id) {
            let state_msg = ServerMessage::new("room.state", room_state);
            state.broadcast_to_room(&room_id, &serde_json::to_string(&state_msg).unwrap());
        }
    }

    send_task.abort();
}

/// Wait for `auth.hello { token: "..." }`, verify JWT, return (player_id, username).
/// Sends an error and returns None if token is missing or invalid.
async fn wait_for_auth(
    receiver: &mut futures::stream::SplitStream<WebSocket>,
    tx: &mpsc::UnboundedSender<Message>,
    jwt_secret: &str,
) -> Option<(String, String)> {
    match receiver.next().await {
        Some(Ok(Message::Text(text))) => {
            match serde_json::from_str::<ClientMessage>(&text) {
                Ok(msg) if msg.msg_type == "auth.hello" => {
                    // Extract token from payload
                    let token = match msg.payload.get("token").and_then(|v| v.as_str()) {
                        Some(t) => t.to_string(),
                        None => {
                            let _ = tx.send(Message::Text(
                                serde_json::to_string(&ServerMessage::error(
                                    "INVALID_AUTH",
                                    "Missing token in auth.hello payload",
                                ))
                                .unwrap(),
                            ));
                            return None;
                        }
                    };

                    // Verify JWT
                    match verify_jwt(&token, jwt_secret) {
                        Ok(claims) => Some((claims.sub, claims.username)),
                        Err(e) => {
                            tracing::warn!("JWT verify failed: {e}");
                            let _ = tx.send(Message::Text(
                                serde_json::to_string(&ServerMessage::error(
                                    "UNAUTHORIZED",
                                    "Invalid or expired token",
                                ))
                                .unwrap(),
                            ));
                            None
                        }
                    }
                }
                _ => {
                    let _ = tx.send(Message::Text(
                        serde_json::to_string(&ServerMessage::error(
                            "UNAUTHORIZED",
                            "First message must be auth.hello { token }",
                        ))
                        .unwrap(),
                    ));
                    None
                }
            }
        }
        _ => None,
    }
}

async fn handle_client_message(
    msg: ClientMessage,
    player_id: &str,
    username: &str,
    state: &Arc<AppState>,
    tx: &mpsc::UnboundedSender<Message>,
) {
    match msg.msg_type.as_str() {

        // ── Quick Play ────────────────────────────────────────────
        "mm.quick_play" => {
            tracing::info!("Player '{}' requests quick play", player_id);
            match state.quick_play(player_id.to_string(), username.to_string()).await {
                Ok(room_id) => {
                    let members = state.load_room_members(&room_id).await;
                    if let Some(mut room_state) = state.get_room_state(&room_id) {
                        if let Some(obj) = room_state.as_object_mut() {
                            obj.insert("players".to_string(), serde_json::to_value(&members).unwrap());
                        }
                        let joined_msg = ServerMessage::new(
                            "room.joined",
                            json!({ "roomId": room_id, "room": room_state.clone() }),
                        );
                        let _ = tx.send(Message::Text(serde_json::to_string(&joined_msg).unwrap()));
                        let state_msg = ServerMessage::new("room.state", room_state);
                        state.broadcast_to_room(&room_id, &serde_json::to_string(&state_msg).unwrap());
                        let joined_notify = ServerMessage::new(
                            "room.player_joined",
                            json!({ "playerId": player_id, "username": username }),
                        );
                        state.broadcast_to_room(&room_id, &serde_json::to_string(&joined_notify).unwrap());
                    }
                }
                Err(e) => {
                    let _ = tx.send(Message::Text(
                        serde_json::to_string(&ServerMessage::error("QUICK_PLAY_FAILED", &e)).unwrap(),
                    ));
                }
            }
        }

        // ── Private Room ──────────────────────────────────────────
        "room.create_private" => {
            tracing::info!("Player '{}' creating private room", player_id);
            match state.create_private_room(player_id.to_string(), username.to_string()).await {
                Ok((room_id, invite_code)) => {
                    let members = state.load_room_members(&room_id).await;
                    if let Some(mut room_state) = state.get_room_state(&room_id) {
                        if let Some(obj) = room_state.as_object_mut() {
                            obj.insert("players".to_string(), serde_json::to_value(&members).unwrap());
                            obj.insert("inviteCode".to_string(), serde_json::Value::String(invite_code.clone()));
                        }
                        let response = ServerMessage::new(
                            "room.created",
                            json!({ "roomId": room_id, "inviteCode": invite_code, "room": room_state }),
                        );
                        let _ = tx.send(Message::Text(serde_json::to_string(&response).unwrap()));
                    }
                }
                Err(e) => {
                    let _ = tx.send(Message::Text(
                        serde_json::to_string(&ServerMessage::error("CREATE_PRIVATE_FAILED", &e)).unwrap(),
                    ));
                }
            }
        }

        // ── Invite: send ──────────────────────────────────────────
        "invite.send" => {
            let friend_id = msg.payload.get("friendId").and_then(|v| v.as_str());
            let invite_code = msg.payload.get("inviteCode").and_then(|v| v.as_str());
            if let (Some(friend_id), Some(code)) = (friend_id, invite_code) {
                if let Some(friend_tx) = state.connections.get(friend_id) {
                    let invite_msg = ServerMessage::new(
                        "invite.received",
                        json!({ "inviteCode": code, "fromPlayerId": player_id, "fromUsername": username }),
                    );
                    let _ = friend_tx.send(Message::Text(serde_json::to_string(&invite_msg).unwrap()));
                    let _ = tx.send(Message::Text(
                        serde_json::to_string(&ServerMessage::new(
                            "invite.sent",
                            json!({ "friendId": friend_id, "status": "ok" }),
                        )).unwrap(),
                    ));
                } else {
                    let _ = tx.send(Message::Text(
                        serde_json::to_string(&ServerMessage::error("FRIEND_NOT_ONLINE", "Friend not connected")).unwrap(),
                    ));
                }
            } else {
                let _ = tx.send(Message::Text(
                    serde_json::to_string(&ServerMessage::error("INVALID_PAYLOAD", "Missing friendId or inviteCode")).unwrap(),
                ));
            }
        }

        // ── Invite: accept ────────────────────────────────────────
        "invite.accept" => {
            let invite_code = msg.payload.get("inviteCode").and_then(|v| v.as_str());
            if let Some(code) = invite_code {
                match state.resolve_invite(code) {
                    Some(room_id) => {
                        match state.join_room(&room_id, player_id, username.to_string()).await {
                            Ok(_) => {
                                let members = state.load_room_members(&room_id).await;
                                if let Some(mut room_state) = state.get_room_state(&room_id) {
                                    if let Some(obj) = room_state.as_object_mut() {
                                        obj.insert("players".to_string(), serde_json::to_value(&members).unwrap());
                                    }
                                    let joined_msg = ServerMessage::new(
                                        "room.joined",
                                        json!({ "roomId": room_id, "room": room_state.clone() }),
                                    );
                                    let _ = tx.send(Message::Text(serde_json::to_string(&joined_msg).unwrap()));
                                    let state_msg = ServerMessage::new("room.state", room_state);
                                    state.broadcast_to_room(&room_id, &serde_json::to_string(&state_msg).unwrap());
                                    let joined_notify = ServerMessage::new(
                                        "room.player_joined",
                                        json!({ "playerId": player_id, "username": username }),
                                    );
                                    state.broadcast_to_room(&room_id, &serde_json::to_string(&joined_notify).unwrap());
                                }
                            }
                            Err(e) => {
                                let _ = tx.send(Message::Text(
                                    serde_json::to_string(&ServerMessage::error("JOIN_FAILED", &e)).unwrap(),
                                ));
                            }
                        }
                    }
                    None => {
                        let _ = tx.send(Message::Text(
                            serde_json::to_string(&ServerMessage::error("INVALID_INVITE", "Invite code not found")).unwrap(),
                        ));
                    }
                }
            } else {
                let _ = tx.send(Message::Text(
                    serde_json::to_string(&ServerMessage::error("INVALID_PAYLOAD", "Missing inviteCode")).unwrap(),
                ));
            }
        }

        "mm.join_queue" => {
            tracing::info!("Player '{}' joining queue", player_id);

            match state
                .join_queue(player_id.to_string(), username.to_string())
                .await
            {
                Some(room_id) => {
                    tracing::info!("Match found! Room: {}", room_id);
                    
                    let matched_msg =
                        ServerMessage::new("mm.matched", json!({ "roomId": room_id }));
                    state.broadcast_to_room(
                        &room_id,
                        &serde_json::to_string(&matched_msg).unwrap(),
                    );
                    
                    let members = state.load_room_members(&room_id).await;
                    if let Some(room_state) = state.get_room_state(&room_id) {
                        let mut state_json = room_state.clone();
                        // Overwrite players with fresh DB truth
                        if let Some(obj) = state_json.as_object_mut() {
                            obj.insert("players".to_string(), serde_json::to_value(&members).unwrap());
                        }

                        let state_msg = ServerMessage::new("room.state", state_json);
                        state.broadcast_to_room(
                            &room_id,
                            &serde_json::to_string(&state_msg).unwrap(),
                        );
                    }
                }
                None => {
                    let queue_size = state.queue.lock().await.len();
                    let response = ServerMessage::new(
                        "mm.queued",
                        json!({ "status": "waiting", "queueSize": queue_size }),
                    );
                    let _ = tx.send(Message::Text(serde_json::to_string(&response).unwrap()));
                }
            }
        }

        "mm.leave_queue" => {
            let mut queue = state.queue.lock().await;
            queue.retain(|id| id != player_id);
            let _ = tx.send(Message::Text(
                serde_json::to_string(&ServerMessage::new(
                    "mm.left_queue",
                    json!({ "status": "ok" }),
                ))
                .unwrap(),
            ));
        }

        "room.create" => {
            let max_players = msg
                .payload
                .get("maxPlayers")
                .and_then(|v| v.as_u64())
                .unwrap_or(16) as usize;

            match state.create_room(player_id.to_string(), username.to_string(), max_players).await {
                Ok(room_id) => {
                    let members = state.load_room_members(&room_id).await;
                    if let Some(room_state) = state.get_room_state(&room_id) {
                        let mut state_json = room_state.clone();
                        if let Some(obj) = state_json.as_object_mut() {
                            obj.insert("players".to_string(), serde_json::to_value(&members).unwrap());
                        }

                        let response = ServerMessage::new(
                            "room.created",
                            json!({ "roomId": room_id, "room": state_json }),
                        );
                        let _ = tx.send(Message::Text(serde_json::to_string(&response).unwrap()));
                    }
                }
                Err(e) => {
                    tracing::error!("Failed to create room in DB: {}", e);
                    let _ = tx.send(Message::Text(
                        serde_json::to_string(&ServerMessage::error(
                            "DB_ERROR",
                            &format!("Failed to create room: {}", e),
                        ))
                        .unwrap(),
                    ));
                }
            }
        }

        "room.join" => {
            let target_room = msg.payload.get("roomId").and_then(|v| v.as_str());

            if let Some(room_id) = target_room {
                match state.join_room(room_id, player_id, username.to_string()).await {
                    Ok(_) => {
                        let joined_msg = ServerMessage::new(
                            "room.player_joined",
                            json!({ "playerId": player_id, "username": username }),
                        );
                        state.broadcast_to_room(
                            room_id,
                            &serde_json::to_string(&joined_msg).unwrap(),
                        );

                        let members = state.load_room_members(room_id).await;
                        if let Some(room_state) = state.get_room_state(room_id) {
                            let mut state_json = room_state.clone();
                            if let Some(obj) = state_json.as_object_mut() {
                                obj.insert("players".to_string(), serde_json::to_value(&members).unwrap());
                            }

                            let state_msg = ServerMessage::new("room.state", state_json);
                            state.broadcast_to_room(
                                room_id,
                                &serde_json::to_string(&state_msg).unwrap(),
                            );
                        }
                    }
                    Err(e) => {
                        let _ = tx.send(Message::Text(
                            serde_json::to_string(&ServerMessage::error("JOIN_FAILED", &e))
                                .unwrap(),
                        ));
                    }
                }
            } else {
                let _ = tx.send(Message::Text(
                    serde_json::to_string(&ServerMessage::error(
                        "INVALID_PAYLOAD",
                        "Missing roomId in payload",
                    ))
                    .unwrap(),
                ));
            }
        }

        "room.leave" => {
            if let Some(room_id) = state.leave_room(player_id).await {
                let left_msg = ServerMessage::new(
                    "room.player_left",
                    json!({ "playerId": player_id }),
                );
                state.broadcast_to_room(
                    &room_id,
                    &serde_json::to_string(&left_msg).unwrap(),
                );

                let members = state.load_room_members(&room_id).await;
                if let Some(room_state) = state.get_room_state(&room_id) {
                    let mut state_json = room_state.clone();
                    if let Some(obj) = state_json.as_object_mut() {
                        obj.insert("players".to_string(), serde_json::to_value(&members).unwrap());
                    }

                    let state_msg = ServerMessage::new("room.state", state_json);
                    state.broadcast_to_room(
                        &room_id,
                        &serde_json::to_string(&state_msg).unwrap(),
                    );
                }

                let _ = tx.send(Message::Text(
                    serde_json::to_string(&ServerMessage::new(
                        "room.left",
                        json!({ "status": "ok" }),
                    ))
                    .unwrap(),
                ));
            } else {
                let _ = tx.send(Message::Text(
                    serde_json::to_string(&ServerMessage::error("NOT_IN_ROOM", "You are not in a room"))
                        .unwrap(),
                ));
            }
        }

        _ => {
            tracing::warn!("Unknown message type: {}", msg.msg_type);
            let _ = tx.send(Message::Text(
                serde_json::to_string(&ServerMessage::error(
                    "UNKNOWN_MESSAGE_TYPE",
                    &format!("Unknown type: {}", msg.msg_type),
                ))
                .unwrap(),
            ));
        }
    }
}
