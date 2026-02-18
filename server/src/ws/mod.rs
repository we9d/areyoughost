use std::sync::Arc;
use axum::extract::ws::{WebSocketUpgrade, WebSocket, Message};
use axum::{extract::State, response::IntoResponse};
use tokio::sync::mpsc;
use futures::{StreamExt, SinkExt};
use serde_json::json;

use crate::state::manager::GameRoomManager;

pub mod messages;

use messages::{ClientMessage, ServerMessage};

pub async fn ws_handler(
    State(manager): State<Arc<GameRoomManager>>,
    ws: WebSocketUpgrade,
) -> impl IntoResponse {
    ws.on_upgrade(move |socket| handle_socket(socket, manager))
}

pub async fn handle_socket(socket: WebSocket, manager: Arc<GameRoomManager>) {
    tracing::info!("New WebSocket connection established");

    let (mut sender, mut receiver) = socket.split();
    let (tx, mut rx) = mpsc::unbounded_channel::<Message>();

    // Spawn task to forward messages to WebSocket
    let mut send_task = tokio::spawn(async move {
        while let Some(msg) = rx.recv().await {
            if sender.send(msg).await.is_err() {
                break;
            }
        }
    });

    // Wait for auth.hello message (must be first)
    let player_id = match wait_for_auth(&mut receiver, &tx).await {
        Some(id) => id,
        None => {
            tracing::warn!("Connection closed before authentication");
            return;
        }
    };

    tracing::info!("Player {} authenticated", player_id);

    // Register connection
    manager.connections.insert(player_id.clone(), tx.clone());

    // Send authentication success
    let auth_response = ServerMessage::new("auth.authenticated", json!({
        "playerId": player_id,
        "status": "ok"
    }));
    let _ = tx.send(Message::Text(serde_json::to_string(&auth_response).unwrap()));

    // Message handling loop
    while let Some(msg) = receiver.next().await {
        match msg {
            Ok(Message::Text(text)) => {
                // Parse client message
                match serde_json::from_str::<ClientMessage>(&text) {
                    Ok(client_msg) => {
                        tracing::info!("Received message type: {}", client_msg.msg_type);
                        handle_client_message(client_msg, &player_id, &manager, &tx).await;
                    }
                    Err(e) => {
                        tracing::error!("Failed to parse message: {:?}", e);
                        let error_msg = ServerMessage::error("INVALID_MESSAGE", "Failed to parse JSON");
                        let _ = tx.send(Message::Text(serde_json::to_string(&error_msg).unwrap()));
                    }
                }
            }
            Ok(Message::Close(_)) => {
                tracing::info!("Player {} closed connection", player_id);
                break;
            }
            Err(e) => {
                tracing::error!("WebSocket error: {:?}", e);
                break;
            }
            _ => {}
        }
    }

    // Cleanup on disconnect
    tracing::info!("Cleaning up connection for player {}", player_id);
    manager.connections.remove(&player_id);
    
    // Remove from queue if present
    {
        let mut queue = manager.queue.lock().await;
        queue.retain(|id| id != &player_id);
    }
    
    // Leave room if in one
    if let Some((_, room_id)) = manager.player_rooms.remove(&player_id) {
        if let Some(mut room) = manager.rooms.get_mut(&room_id) {
            room.players.retain(|p| p.player_id != player_id);
            // Broadcast player left
            // TODO: Implement in Commit 5
        }
    }

    send_task.abort();
}

async fn wait_for_auth(
    receiver: &mut futures::stream::SplitStream<WebSocket>,
    tx: &mpsc::UnboundedSender<Message>,
) -> Option<String> {
    // Wait for first message (must be auth.hello)
    match receiver.next().await {
        Some(Ok(Message::Text(text))) => {
            match serde_json::from_str::<ClientMessage>(&text) {
                Ok(msg) if msg.msg_type == "auth.hello" => {
                    // Extract player_id from payload
                    if let Some(player_id) = msg.payload.get("playerId").and_then(|v| v.as_str()) {
                        Some(player_id.to_string())
                    } else {
                        let error_msg = ServerMessage::error("INVALID_AUTH", "Missing playerId");
                        let _ = tx.send(Message::Text(serde_json::to_string(&error_msg).unwrap()));
                        None
                    }
                }
                _ => {
                    let error_msg = ServerMessage::error("UNAUTHORIZED", "First message must be auth.hello");
                    let _ = tx.send(Message::Text(serde_json::to_string(&error_msg).unwrap()));
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
    manager: &Arc<GameRoomManager>,
    tx: &mpsc::UnboundedSender<Message>,
) {
    match msg.msg_type.as_str() {
        "mm.join_queue" => {
            tracing::info!("Player {} joining queue", player_id);
            
            // Extract username from payload (optional)
            let username = msg.payload.get("username")
                .and_then(|v| v.as_str())
                .unwrap_or(player_id)
                .to_string();

            // Join queue and try to match
            match manager.join_queue(player_id.to_string(), username).await {
                Some(room_id) => {
                    // Match found! Notify all players in the room
                    tracing::info!("Match found! Room: {}", room_id);
                    
                    if let Some(room_state) = manager.get_room_state(&room_id) {
                        // Send mm.matched to all players
                        let matched_msg = ServerMessage::new("mm.matched", json!({
                            "roomId": room_id
                        }));
                        manager.broadcast_to_room(&room_id, &serde_json::to_string(&matched_msg).unwrap());
                        
                        // Send room.state to all players
                        let state_msg = ServerMessage::new("room.state", room_state);
                        manager.broadcast_to_room(&room_id, &serde_json::to_string(&state_msg).unwrap());
                    }
                }
                None => {
                    // Still in queue, waiting for more players
                    let queue_size = manager.queue.lock().await.len();
                    let response = ServerMessage::new("mm.queued", json!({
                        "status": "waiting",
                        "queueSize": queue_size
                    }));
                    let _ = tx.send(Message::Text(serde_json::to_string(&response).unwrap()));
                }
            }
        }
        "mm.leave_queue" => {
            tracing::info!("Player {} leaving queue", player_id);
            let mut queue = manager.queue.lock().await;
            queue.retain(|id| id != player_id);
            let response = ServerMessage::new("mm.left_queue", json!({"status": "ok"}));
            let _ = tx.send(Message::Text(serde_json::to_string(&response).unwrap()));
        }
        "room.create" => {
            tracing::info!("Player {} creating room", player_id);
            
            let username = msg.payload.get("username")
                .and_then(|v| v.as_str())
                .unwrap_or(player_id)
                .to_string();
            
            let max_players = msg.payload.get("maxPlayers")
                .and_then(|v| v.as_u64())
                .unwrap_or(16) as usize;
            
            let room_id = manager.create_room(player_id.to_string(), username, max_players);
            
            if let Some(room_state) = manager.get_room_state(&room_id) {
                let response = ServerMessage::new("room.created", json!({
                    "roomId": room_id,
                    "room": room_state
                }));
                let _ = tx.send(Message::Text(serde_json::to_string(&response).unwrap()));
            }
        }
        "room.join" => {
            tracing::info!("Player {} joining room", player_id);
            // TODO: Implement in next phase
            let error_msg = ServerMessage::error("NOT_IMPLEMENTED", "Room joining not yet implemented");
            let _ = tx.send(Message::Text(serde_json::to_string(&error_msg).unwrap()));
        }
        "room.leave" => {
            tracing::info!("Player {} leaving room", player_id);
            if let Some((_, room_id)) = manager.player_rooms.remove(player_id) {
                if let Some(mut room) = manager.rooms.get_mut(&room_id) {
                    room.players.retain(|p| p.player_id != player_id);
                    
                    // Broadcast player left
                    let left_msg = ServerMessage::new("room.player_left", json!({
                        "playerId": player_id
                    }));
                    manager.broadcast_to_room(&room_id, &serde_json::to_string(&left_msg).unwrap());
                    
                    // Send updated room state
                    if let Some(room_state) = manager.get_room_state(&room_id) {
                        let state_msg = ServerMessage::new("room.state", room_state);
                        manager.broadcast_to_room(&room_id, &serde_json::to_string(&state_msg).unwrap());
                    }
                }
                let response = ServerMessage::new("room.left", json!({"status": "ok"}));
                let _ = tx.send(Message::Text(serde_json::to_string(&response).unwrap()));
            } else {
                let error_msg = ServerMessage::error("NOT_IN_ROOM", "You are not in a room");
                let _ = tx.send(Message::Text(serde_json::to_string(&error_msg).unwrap()));
            }
        }
        _ => {
            tracing::warn!("Unknown message type: {}", msg.msg_type);
            let error_msg = ServerMessage::error("UNKNOWN_MESSAGE_TYPE", &format!("Unknown type: {}", msg.msg_type));
            let _ = tx.send(Message::Text(serde_json::to_string(&error_msg).unwrap()));
        }
    }
}
