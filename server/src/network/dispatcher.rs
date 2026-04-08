use bytes::Bytes;
use std::sync::Arc;
use tracing::{info, warn, error};
use uuid::Uuid;
use crate::state::manager::{AppState};
use areyoughost_core::network::message::{Message, MessageType, StartGameRequest, CastVoteRequest, NightActionRequest, ChatMessageRequest};
use crate::game_logic::room_task::RoomAction;

pub async fn dispatch_command(
    msg: Message,
    state: &Arc<AppState>,
    current_player_id: &Option<Uuid>,
    _tx: &tokio::sync::mpsc::UnboundedSender<Bytes>,
) {
    if current_player_id.is_none() {
        warn!("Received a command before login: {:?}", msg.msg_type);
        return;
    }
    let player_id = current_player_id.unwrap(); // Current player UUID

    if msg.msg_type == MessageType::QuickJoinRequest {
        info!("Player {} requested Quick Join", player_id);
        
        let st = state.clone();
        
        tokio::spawn(async move {
            // Retrieve username from DB
            let username_res = sqlx::query_scalar::<_, String>("SELECT username FROM users WHERE user_id = $1")
                .bind(player_id)
                .fetch_optional(&st.db).await;
                
            let username = match username_res {
                Ok(Some(u)) => u,
                _ => "Player".to_string(), // fallback
            };
            
            match st.clone().quick_play(player_id, username).await {
                Ok(room_id) => {
                    info!("Player {} assigned to QuickPlay room {}", player_id, room_id);
                    st.broadcast_room_state_sync(&room_id).await;
                }
                Err(e) => {
                    error!("QuickJoin failed for {}: {}", player_id, e);
                }
            }
        });
        return;
    }

    let room_id = match state.player_rooms.get(&player_id) {
        Some(r) => *r,
        None => {
            warn!("Player {} sent command but is not in any room", player_id);
            return;
        }
    };

    // --- Validation Layer ---
    // Ensure room exists in state manager
    if !state.rooms.contains_key(&room_id) && !state.games.contains_key(&room_id) {
        warn!("Player {} sent command for invalid or closed room {}", player_id, room_id);
        return;
    }

    match msg.msg_type {
        MessageType::StartGame => {
            if let Ok(req) = msg.parse_binary::<StartGameRequest>() {
                if req.room_id != room_id {
                    warn!("Player {} attempted to start room {} but is in room {}", player_id, req.room_id, room_id);
                    return;
                }
                
                info!("Player {} requested to start game in room {}", player_id, room_id);
                let st = state.clone();
                tokio::spawn(async move {
                    if let Err(e) = st.start_game(&player_id, &room_id).await {
                        error!("Failed to start game: {}", e);
                    }
                });
            }
        }
        MessageType::CastVote => {
            if let Ok(vote) = msg.parse_binary::<CastVoteRequest>() {
                if vote.room_id != room_id { return; }
                
                info!("Player {} cast a vote for {}", player_id, vote.target_id);
                if let Some(tx) = state.room_tx.get(&room_id) {
                    let _ = tx.send(RoomAction::Vote {
                        voter_id: player_id,
                        target_id: vote.target_id,
                    });
                }
            }
        }
        MessageType::NightAction => {
            if let Ok(action) = msg.parse_binary::<NightActionRequest>() {
                if action.room_id != room_id { return; }
                
                info!("Player {} requested night action: {:?}", player_id, action.action_type);
                if let Some(tx) = state.room_tx.get(&room_id) {
                    let _ = tx.send(RoomAction::NightAction {
                        actor_id: player_id,
                        target_id: action.target_id,
                        action_type: action.action_type,
                    });
                }
            }
        }
        MessageType::ChatMessage => {
            if let Ok(chat) = msg.parse_binary::<ChatMessageRequest>() {
                if chat.room_id != room_id { return; }
                
                info!("Player {} sent chat for room {}: {}", player_id, room_id, chat.message_text);
                
                // Retrieve username
                let st = state.clone();
                let pid = player_id;
                tokio::spawn(async move {
                    let username_res: Result<Option<String>, sqlx::Error> = sqlx::query_scalar::<_, String>("SELECT username FROM users WHERE user_id = $1")
                        .bind(pid)
                        .fetch_optional(&st.db).await;
                    
                    let uname = username_res.ok().flatten().unwrap_or_else(|| "Unknown".to_string());
                    
                    let entry = areyoughost_core::network::message::ChatEntry {
                        sender_username: uname,
                        message_text: chat.message_text,
                        timestamp: std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).unwrap().as_secs(),
                    };
                    
                    if let Ok(out_msg) = Message::from_binary(MessageType::ChatMessage, &entry) {
                        st.broadcast_to_room(&room_id, out_msg.to_bytes());
                    }
                });
            }
        }
        _ => {
            warn!("Unhandled message type in dispatcher: {:?}", msg.msg_type);
        }
    }
}
