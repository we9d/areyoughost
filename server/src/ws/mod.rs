use std::sync::Arc;

use axum::extract::ws::{Message, WebSocket, WebSocketUpgrade};
use axum::{extract::State, response::IntoResponse};
use futures::{SinkExt, StreamExt};
use serde_json::json;
use tokio::sync::mpsc;

use crate::session_auth::authenticate_first_message;
use crate::persistence::insert_match_event;
use crate::state::manager::{AppState, PlayerInfo};

pub mod messages;
use messages::{ClientMessage, ServerMessage};

fn room_players_payload_with_runtime(
    state: &Arc<AppState>,
    room_id: &str,
    members: &[PlayerInfo],
) -> serde_json::Value {
    let runtime = state.active_games.get(room_id);
    let players = members
        .iter()
        .map(|p| {
            let alive = runtime
                .as_ref()
                .and_then(|g| g.players.get(&p.player_id).map(|s| s.alive))
                .unwrap_or(true);
            serde_json::json!({
                "playerId": p.player_id,
                "username": p.username,
                "isReady": p.is_ready,
                "isHost": p.is_host,
                "alive": alive,
            })
        })
        .collect::<Vec<_>>();
    serde_json::to_value(players).unwrap_or_else(|_| serde_json::json!([]))
}

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
    let (player_id, username) = match wait_for_auth(&mut receiver, &tx, &state).await {
        Some(claims) => (claims.0, claims.1),
        None => {
            tracing::warn!("Connection closed before authentication");
            return;
        }
    };

    tracing::info!("Player '{}' (id={}) authenticated via JWT", username, player_id);

    // Register/replace active connection for this player.
    // Single-session ownership: latest authenticated socket wins.
    state.connections.insert(player_id.clone(), tx.clone());
    let resumed = state.consume_pending_disconnect(&player_id);
    let resume_token = state.issue_resume_token(&player_id);

    // Confirm auth success
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

        // Send latest room snapshot to help client resync quickly.
        if let Some(room_id) = state.player_rooms.get(&player_id).map(|r| r.clone()) {
            if let Some(mut room_state) = state.get_room_state(&room_id) {
                state.enrich_room_state_for_viewer(&room_id, &player_id, &mut room_state);
                let _ = tx.send(Message::Text(
                    serde_json::to_string(&ServerMessage::new("room.state", room_state)).unwrap(),
                ));
            }
        }
    }

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
                let err_text = format!("{e:?}");
                if err_text.contains("ResetWithoutClosingHandshake") {
                    // Common when client process/network drops abruptly. Treat as
                    // non-fatal disconnect noise so logs stay actionable.
                    tracing::warn!(
                        "WebSocket reset without closing handshake for player '{}'",
                        player_id
                    );
                } else {
                    tracing::error!("WebSocket error for player '{}': {e:?}", player_id);
                }
                break;
            }
            _ => {}
        }
    }

    // ── Cleanup ───────────────────────────────────────────────────
    tracing::info!("Connection closed for player '{}'", player_id);
    state.connections.remove(&player_id);

    {
        let mut queue = state.queue.lock().await;
        queue.retain(|id| id != &player_id);
    }

    // Do not immediately remove room membership on network drops.
    // Start grace window; leave-room will be finalized only if no reconnect.
    state.mark_pending_disconnect(&player_id);

    send_task.abort();
}

/// Wait for `auth.hello { token: "..." }`, verify JWT, return (player_id, username).
/// Sends an error and returns None if token is missing or invalid.
async fn wait_for_auth(
    receiver: &mut futures::stream::SplitStream<WebSocket>,
    tx: &mpsc::UnboundedSender<Message>,
    state: &Arc<AppState>,
) -> Option<(String, String)> {
    match receiver.next().await {
        Some(Ok(Message::Text(text))) => {
            match authenticate_first_message(&text, state).await {
                Ok(pair) => Some(pair),
                Err(sm) => {
                    let _ = tx.send(Message::Text(serde_json::to_string(&sm).unwrap()));
                    None
                }
            }
        }
        _ => None,
    }
}

pub(crate) async fn handle_client_message(
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
                            obj.insert(
                                "players".to_string(),
                                room_players_payload_with_runtime(state, &room_id, &members),
                            );
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
                        state.schedule_quickplay_start(&room_id);
                    } else {
                        tracing::error!(
                            "quick_play ok but get_room_state missing room_id={} (in-memory rooms out of sync)",
                            room_id
                        );
                        let _ = tx.send(Message::Text(
                            serde_json::to_string(&ServerMessage::error(
                                "QUICK_PLAY_FAILED",
                                "Room state missing after quick play; check server logs",
                            ))
                            .unwrap(),
                        ));
                    }
                }
                Err(e) => {
                    tracing::error!("Player '{}' mm.quick_play failed: {}", player_id, e);
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
                            obj.insert(
                                "players".to_string(),
                                room_players_payload_with_runtime(state, &room_id, &members),
                            );
                            obj.insert("inviteCode".to_string(), serde_json::Value::String(invite_code.clone()));
                        }
                        let response = ServerMessage::new(
                            "room.created",
                            json!({ "roomId": room_id, "inviteCode": invite_code, "room": room_state }),
                        );
                        let _ = tx.send(Message::Text(serde_json::to_string(&response).unwrap()));
                        tracing::info!(
                            "Player '{}' room.created sent (room_id={}, invite={})",
                            player_id,
                            room_id,
                            invite_code
                        );
                    } else {
                        tracing::error!(
                            "create_private ok but get_room_state missing room_id={}",
                            room_id
                        );
                        let _ = tx.send(Message::Text(
                            serde_json::to_string(&ServerMessage::error(
                                "CREATE_PRIVATE_FAILED",
                                "Room state missing after create; check server logs",
                            ))
                            .unwrap(),
                        ));
                    }
                }
                Err(e) => {
                    tracing::error!(
                        "Player '{}' room.create_private failed: {}",
                        player_id,
                        e
                    );
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
                                        obj.insert(
                                            "players".to_string(),
                                            room_players_payload_with_runtime(state, &room_id, &members),
                                        );
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
                                    state.schedule_quickplay_start(&room_id);
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
            match state.quick_play(player_id.to_string(), username.to_string()).await {
                Ok(room_id) => {
                    tracing::info!("Quickplay room assigned: {}", room_id);
                    let matched_msg = ServerMessage::new("mm.matched", json!({ "roomId": room_id }));
                    state.broadcast_to_room(&room_id, &serde_json::to_string(&matched_msg).unwrap());

                    let members = state.load_room_members(&room_id).await;
                    if let Some(mut room_state) = state.get_room_state(&room_id) {
                        if let Some(obj) = room_state.as_object_mut() {
                            obj.insert(
                                "players".to_string(),
                                room_players_payload_with_runtime(state, &room_id, &members),
                            );
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
                        // Start/refresh countdown only when room has enough players.
                        state.schedule_quickplay_start(&room_id);
                    } else {
                        tracing::error!(
                            "mm.join_queue quick_play ok but get_room_state missing room_id={}",
                            room_id
                        );
                        let _ = tx.send(Message::Text(
                            serde_json::to_string(&ServerMessage::error(
                                "QUICK_PLAY_FAILED",
                                "Room state missing after quickplay; check server logs",
                            ))
                            .unwrap(),
                        ));
                    }
                }
                Err(e) => {
                    tracing::error!("Player '{}' mm.join_queue quickplay failed: {}", player_id, e);
                    let _ = tx.send(Message::Text(
                        serde_json::to_string(&ServerMessage::error("QUICK_PLAY_FAILED", &e)).unwrap(),
                    ));
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

            match state
                .create_room(
                    player_id.to_string(),
                    username.to_string(),
                    max_players,
                    "PUBLIC",
                )
                .await
            {
                Ok(room_id) => {
                    let members = state.load_room_members(&room_id).await;
                    if let Some(room_state) = state.get_room_state(&room_id) {
                        let mut state_json = room_state.clone();
                        if let Some(obj) = state_json.as_object_mut() {
                            obj.insert(
                                "players".to_string(),
                                room_players_payload_with_runtime(state, &room_id, &members),
                            );
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
                                obj.insert(
                                    "players".to_string(),
                                    room_players_payload_with_runtime(state, room_id, &members),
                                );
                            }

                            let state_msg = ServerMessage::new("room.state", state_json);
                            state.broadcast_to_room(
                                room_id,
                                &serde_json::to_string(&state_msg).unwrap(),
                            );
                        }
                        state.schedule_quickplay_start(room_id);
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
                        obj.insert(
                            "players".to_string(),
                            room_players_payload_with_runtime(state, &room_id, &members),
                        );
                    }
                    let player_count = state_json
                        .get("players")
                        .and_then(|v| v.as_array())
                        .map(|a| a.len())
                        .unwrap_or(0);

                    let state_msg = ServerMessage::new("room.state", state_json);
                    state.broadcast_to_room(
                        &room_id,
                        &serde_json::to_string(&state_msg).unwrap(),
                    );
                    if player_count < 2 {
                        state.schedule_quickplay_start(&room_id);
                    }
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

        "room.sync" => {
            // Safety net: if phase deadline already elapsed but periodic ticker lagged,
            // progress phases before returning current room.state.
            state.tick_games();
            if let Some(room_id) = state.player_rooms.get(player_id).map(|r| r.clone()) {
                if let Some(phase_payload) = state.tick_room(&room_id) {
                    let phase_msg = ServerMessage::new("game.phase_changed", phase_payload);
                    state.broadcast_to_room(
                        &room_id,
                        &serde_json::to_string(&phase_msg).unwrap(),
                    );
                }
                let now = chrono::Utc::now().timestamp();
                let maybe_start_payload = if !state.active_games.contains_key(&room_id) {
                    if let Some(room) = state.rooms.get(&room_id) {
                        if room.status == "waiting" && room.players.len() >= 2 {
                            if let Some(deadline_ref) = state.quickplay_countdown_deadlines.get(&room_id) {
                                if *deadline_ref <= now {
                                    let host_id = room
                                        .players
                                        .iter()
                                        .find(|p| p.is_host)
                                        .map(|p| p.player_id.clone())
                                        .or_else(|| room.players.first().map(|p| p.player_id.clone()));
                                    if let Some(host_id) = host_id {
                                        match state.start_game(&room_id, &host_id).await {
                                            Ok(payload) => Some(payload),
                                            Err(_) => None,
                                        }
                                    } else {
                                        None
                                    }
                                } else {
                                    None
                                }
                            } else {
                                state.schedule_quickplay_start(&room_id);
                                None
                            }
                        } else {
                            None
                        }
                    } else {
                        None
                    }
                } else {
                    None
                };

                if let Some(payload) = maybe_start_payload {
                    let started = ServerMessage::new("game.started", payload);
                    state.broadcast_to_room(&room_id, &serde_json::to_string(&started).unwrap());
                }

                let members = state.load_room_members(&room_id).await;
                if let Some(mut room_state) = state.get_room_state(&room_id) {
                    if let Some(obj) = room_state.as_object_mut() {
                        obj.insert(
                            "players".to_string(),
                            room_players_payload_with_runtime(state, &room_id, &members),
                        );
                    }
                    state.enrich_room_state_for_viewer(&room_id, player_id, &mut room_state);
                    let state_msg = ServerMessage::new("room.state", room_state);
                    let _ = tx.send(Message::Text(serde_json::to_string(&state_msg).unwrap()));
                } else {
                    let _ = tx.send(Message::Text(
                        serde_json::to_string(&ServerMessage::error(
                            "ROOM_STATE_MISSING",
                            "Room state not found",
                        ))
                        .unwrap(),
                    ));
                }
            } else {
                let _ = tx.send(Message::Text(
                    serde_json::to_string(&ServerMessage::error("NOT_IN_ROOM", "You are not in a room"))
                        .unwrap(),
                ));
            }
        }

        "room.chat" => {
            let room_id = state.player_rooms.get(player_id).map(|r| r.clone());
            let text = msg.payload.get("text").and_then(|v| v.as_str());
            if let (Some(room_id), Some(text)) = (room_id, text) {
                let trimmed = text.trim();
                if trimmed.is_empty() {
                    let _ = tx.send(Message::Text(
                        serde_json::to_string(&ServerMessage::error(
                            "INVALID_PAYLOAD",
                            "Chat text cannot be empty",
                        ))
                        .unwrap(),
                    ));
                    return;
                }
                let out = ServerMessage::new(
                    "room.chat_message",
                    json!({
                        "roomId": room_id,
                        "playerId": player_id,
                        "username": username,
                        "text": trimmed
                    }),
                );
                state.broadcast_to_room(&room_id, &serde_json::to_string(&out).unwrap());
            } else {
                let _ = tx.send(Message::Text(
                    serde_json::to_string(&ServerMessage::error(
                        "INVALID_PAYLOAD",
                        "Missing text or room context",
                    ))
                    .unwrap(),
                ));
            }
        }

        // ── Game Runtime (server authoritative) ───────────────────
        "game.start" => {
            let room_id = state.player_rooms.get(player_id).map(|r| r.clone());
            if let Some(room_id) = room_id {
                match state.start_game(&room_id, player_id).await {
                    Ok(payload) => {
                        if !state.skip_persistence {
                            let db = state.db.clone();
                            let rid = room_id.clone();
                            let pl = payload.clone();
                            tokio::spawn(async move {
                                let room_uuid = uuid::Uuid::parse_str(&rid).ok();
                                if let Err(e) =
                                    insert_match_event(&db, room_uuid, None, "game.started", pl).await
                                {
                                    tracing::warn!("match_events insert failed: {}", e);
                                }
                            });
                        }
                        let started = ServerMessage::new("game.started", payload);
                        state.broadcast_to_room(
                            &room_id,
                            &serde_json::to_string(&started).unwrap(),
                        );
                        if let Some(room_state) = state.get_room_state(&room_id) {
                            let state_msg = ServerMessage::new("room.state", room_state);
                            state.broadcast_to_room(
                                &room_id,
                                &serde_json::to_string(&state_msg).unwrap(),
                            );
                        }
                    }
                    Err(e) => {
                        let _ = tx.send(Message::Text(
                            serde_json::to_string(&ServerMessage::error("GAME_START_FAILED", &e))
                                .unwrap(),
                        ));
                    }
                }
            } else {
                let _ = tx.send(Message::Text(
                    serde_json::to_string(&ServerMessage::error("NOT_IN_ROOM", "You are not in a room"))
                        .unwrap(),
                ));
            }
        }

        "game.submit_action" => {
            let room_id = state.player_rooms.get(player_id).map(|r| r.clone());
            let request_id = msg.req_id.unwrap_or_else(|| uuid::Uuid::new_v4().to_string());
            let action_type = msg.payload.get("actionType").and_then(|v| v.as_str());
            let target_id = msg
                .payload
                .get("targetId")
                .and_then(|v| v.as_str())
                .map(|s| s.to_string());

            if let (Some(room_id), Some(action_type)) = (room_id, action_type) {
                match state.submit_action(&room_id, player_id, &request_id, action_type, target_id) {
                    Ok((phase_payload, private_result)) => {
                        let ack = ServerMessage::new(
                            "game.action_accepted",
                            json!({ "requestId": request_id }),
                        );
                        let _ = tx.send(Message::Text(serde_json::to_string(&ack).unwrap()));

                        if let Some(result_payload) = private_result {
                            let skill_result = ServerMessage::new("game.skill_result", result_payload);
                            let _ = tx.send(Message::Text(serde_json::to_string(&skill_result).unwrap()));
                        }

                        if let Some(payload) = phase_payload {
                            let phase_msg = ServerMessage::new("game.phase_changed", payload);
                            state.broadcast_to_room(
                                &room_id,
                                &serde_json::to_string(&phase_msg).unwrap(),
                            );
                            if let Some(room_state) = state.get_room_state(&room_id) {
                                let state_msg = ServerMessage::new("room.state", room_state);
                                state.broadcast_to_room(
                                    &room_id,
                                    &serde_json::to_string(&state_msg).unwrap(),
                                );
                            }
                        }
                    }
                    Err(e) => {
                        let _ = tx.send(Message::Text(
                            serde_json::to_string(&ServerMessage::error("ACTION_REJECTED", &e)).unwrap(),
                        ));
                    }
                }
            } else {
                let _ = tx.send(Message::Text(
                    serde_json::to_string(&ServerMessage::error(
                        "INVALID_PAYLOAD",
                        "Missing actionType or room context",
                    ))
                    .unwrap(),
                ));
            }
        }

        "game.vote" => {
            let room_id = state.player_rooms.get(player_id).map(|r| r.clone());
            let request_id = msg.req_id.unwrap_or_else(|| uuid::Uuid::new_v4().to_string());
            let target_id = msg.payload.get("targetId").and_then(|v| v.as_str());

            if let Some(room_id) = room_id {
                match state.submit_vote(&room_id, player_id, &request_id, target_id) {
                    Ok(phase_payload) => {
                        let ack = ServerMessage::new(
                            "game.vote_accepted",
                            json!({ "requestId": request_id, "targetId": target_id }),
                        );
                        let _ = tx.send(Message::Text(serde_json::to_string(&ack).unwrap()));

                        if let Some(payload) = phase_payload {
                            let phase_msg = ServerMessage::new("game.phase_changed", payload);
                            state.broadcast_to_room(
                                &room_id,
                                &serde_json::to_string(&phase_msg).unwrap(),
                            );
                            if let Some(room_state) = state.get_room_state(&room_id) {
                                let state_msg = ServerMessage::new("room.state", room_state);
                                state.broadcast_to_room(
                                    &room_id,
                                    &serde_json::to_string(&state_msg).unwrap(),
                                );
                            }
                        }
                    }
                    Err(e) => {
                        let _ = tx.send(Message::Text(
                            serde_json::to_string(&ServerMessage::error("VOTE_REJECTED", &e)).unwrap(),
                        ));
                    }
                }
            } else {
                let _ = tx.send(Message::Text(
                    serde_json::to_string(&ServerMessage::error(
                        "INVALID_PAYLOAD",
                        "Missing room context",
                    ))
                    .unwrap(),
                ));
            }
        }

        "game.chat" => {
            let room_id = state.player_rooms.get(player_id).map(|r| r.clone());
            let text = msg.payload.get("text").and_then(|v| v.as_str());

            if let (Some(room_id), Some(text)) = (room_id, text) {
                match state.validate_chat_sender(&room_id, player_id) {
                    Ok(_) => {
                        use crate::state::manager::RuntimePhase;
                        let phase_type = state
                            .active_games
                            .get(&room_id)
                            .map(|g| match g.phase {
                                RuntimePhase::Night => "night",
                                RuntimePhase::Day | RuntimePhase::Voting => "day",
                                RuntimePhase::Lobby | RuntimePhase::End => "day",
                            })
                            .unwrap_or("day");
                        let chat_msg = ServerMessage::new(
                            "game.chat_message",
                            json!({
                                "roomId": room_id,
                                "playerId": player_id,
                                "username": username,
                                "text": text,
                                "phaseType": phase_type
                            }),
                        );
                        let payload = serde_json::to_string(&chat_msg).unwrap();
                        let is_night = state
                            .active_games
                            .get(&room_id)
                            .map(|g| g.phase == RuntimePhase::Night)
                            .unwrap_or(false);
                        if is_night {
                            state.broadcast_to_alive_ghost_faction_in_room(&room_id, &payload);
                        } else {
                            state.broadcast_to_alive_in_room(&room_id, &payload);
                        }
                    }
                    Err(e) => {
                        let _ = tx.send(Message::Text(
                            serde_json::to_string(&ServerMessage::error("CHAT_REJECTED", &e)).unwrap(),
                        ));
                    }
                }
            } else {
                let _ = tx.send(Message::Text(
                    serde_json::to_string(&ServerMessage::error(
                        "INVALID_PAYLOAD",
                        "Missing text or room context",
                    ))
                    .unwrap(),
                ));
            }
        }

        // Temporary host-only control for phase progression during integration.
        "game.advance_phase" => {
            let room_id = state.player_rooms.get(player_id).map(|r| r.clone());
            if let Some(room_id) = room_id {
                match state.advance_phase(&room_id, player_id) {
                    Ok(payload) => {
                        let phase_msg = ServerMessage::new("game.phase_changed", payload);
                        state.broadcast_to_room(
                            &room_id,
                            &serde_json::to_string(&phase_msg).unwrap(),
                        );
                        if let Some(room_state) = state.get_room_state(&room_id) {
                            let state_msg = ServerMessage::new("room.state", room_state);
                            state.broadcast_to_room(
                                &room_id,
                                &serde_json::to_string(&state_msg).unwrap(),
                            );
                        }
                    }
                    Err(e) => {
                        let _ = tx.send(Message::Text(
                            serde_json::to_string(&ServerMessage::error("PHASE_ADVANCE_FAILED", &e))
                                .unwrap(),
                        ));
                    }
                }
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

#[cfg(test)]
mod qa_tests;
