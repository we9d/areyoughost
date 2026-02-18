use crate::models::{ChatMessage, GameAction, GameParticipant};
use std::collections::HashMap;

#[derive(Debug, Clone)]
pub struct GameState {
    pub room_id: String,
    pub game_id: String, // DB game_id
    pub participants: HashMap<String, GameParticipant>,
    pub phase_machine: super::phase_machine::PhaseMachine,
    pub chat_history: Vec<ChatMessage>,
    pub action_history: Vec<GameAction>,
    pub vote_system: super::vote_system::VoteSystem,
}

impl GameState {
    pub fn new(room_id: String) -> Self {
        Self {
            room_id,
            game_id: String::new(), // Initialized later
            participants: HashMap::new(),
            phase_machine: super::phase_machine::PhaseMachine::new(),
            chat_history: Vec::new(),
            action_history: Vec::new(),
            vote_system: super::vote_system::VoteSystem::new(),
        }
    }
}
