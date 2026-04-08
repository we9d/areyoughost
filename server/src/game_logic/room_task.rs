use std::sync::Arc;
use tokio::time::{sleep, Duration};
use tracing::{info, error, warn};
use crate::state::manager::AppState;
use areyoughost_core::game_logic::phase_machine::PhaseType;
use areyoughost_core::network::message::{Message, MessageType, GamePhaseChange};
// No serialize import needed here since we use Message::from_binary

use uuid::Uuid;

#[derive(Debug)]
pub enum RoomAction {
    Vote { voter_id: Uuid, target_id: Uuid },
    NightAction { actor_id: Uuid, target_id: Option<Uuid>, action_type: areyoughost_core::game_logic::roles::SkillType },
}

pub async fn run_game_loop(state: Arc<AppState>, room_id: Uuid, mut action_rx: tokio::sync::mpsc::UnboundedReceiver<RoomAction>) {
    info!("Starting Game Loop for Room {}", room_id);

    loop {
        // Check game end condition first
        let duration = {
            if let Some(game) = state.games.get(&room_id) {
                let win_result = crate::game_logic::engine::check_win(&game.participants, None);
                if let Some(winner) = win_result {
                    info!("Room {} ended! Winner: {:?}", room_id, winner);
                    
                    // TODO: Broadcast Game Finished Event
                    
                    break;
                }
                
                let now = std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).unwrap().as_secs();
                if game.phase_machine.phase_end_time > now {
                     game.phase_machine.phase_end_time - now
                } else {
                    0
                }
            } else {
                warn!("Game state missing for Room {}", room_id);
                break;
            }
        };

        let deadline = sleep(Duration::from_secs(duration + 1));
        tokio::pin!(deadline);

        tokio::select! {
            _ = &mut deadline => {
                info!("Room {} timer hit threshold for phase transition", room_id);
                advance_phase(&state, &room_id).await;
            }
            Some(action) = action_rx.recv() => {
                info!("Room {} received an action: {:?}", room_id, action);
                
                match action {
                    RoomAction::Vote { voter_id, target_id } => {
                        if let Some(mut game) = state.games.get_mut(&room_id) {
                            game.vote_system.cast_vote(voter_id, target_id);
                        }
                    }
                    RoomAction::NightAction { actor_id, target_id, action_type } => {
                        if let Some(mut game) = state.games.get_mut(&room_id) {
                            let action_log = areyoughost_core::models::GameAction {
                                action_id: uuid::Uuid::new_v4(),
                                game_id: game.game_id,
                                phase_id: uuid::Uuid::from_u128(game.phase_machine.day_number as u128),
                                actor_id,
                                target_id,
                                action_type: action_type.to_string(),
                                action_result: None,
                                created_at: chrono::Utc::now()
                            };
                            game.action_history.push(action_log);
                        }
                    }
                }
                
                // Check if all active players acted, e.g. all alive players voted
                let should_skip_timer = {
                    if let Some(game) = state.games.get(&room_id) {
                         if game.phase_machine.current_phase == PhaseType::Vote {
                             let alive_count = game.participants.values().filter(|p| p.model.is_alive).count();
                             let cast_count: i32 = game.vote_system.get_results().into_values().sum();
                             cast_count as usize >= alive_count
                         } else {
                             false
                         }
                    } else { false }
                };

                if should_skip_timer {
                    info!("All players voted, skipping remaining timer for room {}", room_id);
                    advance_phase(&state, &room_id).await;
                }
            }
        }
    }

    info!("Room {} specific loop has shutdown.", room_id);
}

async fn advance_phase(state: &Arc<AppState>, room_id: &Uuid) {
    let mut phase_to_broadcast = PhaseType::Day;
    let mut day_number = 1;
    let mut duration_secs = 0;

    if let Some(mut game) = state.games.get_mut(room_id) {
        let old_phase = game.phase_machine.current_phase.clone();
        
        // Resolve End of Phase logic
        if old_phase == PhaseType::Night {
             let current_day_uuid = uuid::Uuid::from_u128(game.phase_machine.day_number as u128);
             let night_actions: Vec<_> = game.action_history.iter()
                 .filter(|a| a.phase_id == current_day_uuid)
                 .cloned()
                 .collect();
             crate::game_logic::engine::resolve_night(
                 &mut game.participants,
                 &night_actions,
             );
        } else if old_phase == PhaseType::Vote {
             let mut tmp_vs = std::mem::replace(
                 &mut game.vote_system,
                 areyoughost_core::game_logic::vote_system::VoteSystem::new(),
             );
             tmp_vs.resolve_vote(&mut game.participants);
        }

        // Transition logic
        game.phase_machine.next_phase();
        
        phase_to_broadcast = game.phase_machine.current_phase.clone();
        day_number = game.phase_machine.day_number;
        let now = std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).unwrap().as_secs();
        if game.phase_machine.phase_end_time > now {
             duration_secs = (game.phase_machine.phase_end_time - now) as u32;
        }
    }

    // Broadcast GamePhaseChange (0x33) packet!
    let server_timestamp = std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).unwrap().as_secs();
    let change = GamePhaseChange {
        phase: phase_to_broadcast.clone(),
        day_number,
        duration_secs,
        server_timestamp,
        night_chat_history: None,
    };
    
    if let Ok(msg) = Message::from_json(MessageType::GamePhaseChange, &change) {
        state.broadcast_to_room(room_id, msg.to_bytes());
        info!("Room {}: Transitioned to {:?} Day {} (Duration: {}s)", room_id, phase_to_broadcast, day_number, duration_secs);
    } else {
        error!("Failed to serialize GamePhaseChange for Room {}", room_id);
    }
}
