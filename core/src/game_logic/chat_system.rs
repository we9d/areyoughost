use std::collections::HashMap;
use uuid::Uuid;
use chrono::Utc;

use crate::models::ChatMessage;
use crate::network::message::PhaseType;
use crate::game_logic::roles::Faction;

/// Errors that can occur when adding a chat message.
#[derive(Debug)]
pub enum ChatError {
    /// A dead player attempted to send a chat message.
    DeadPlayerCannotChat,
    /// A Villager-faction player attempted to chat during the Night phase.
    NightChatRestrictedToGhosts,
}

/// Scope of a chat message — used as part of the storage key.
#[derive(Debug, Clone, PartialEq, Eq, Hash)]
pub enum ChatScope {
    /// Visible to all alive players (day chat).
    Public,
    /// Visible only to Ghost-faction players during the night.
    Ghost,
}

/// Composite key for the message store: (room_id, day_number, scope).
#[derive(Debug, Clone, PartialEq, Eq, Hash)]
struct MessageKey {
    room_id: Uuid,
    day_number: u32,
    scope: ChatScope,
}

/// Manages in-game chat with phase-aware validation and per-day history.
///
/// Messages are stored keyed by `(room_id, day_number, scope)` so that
/// history can be replayed on reconnection (Requirement 20.4).
pub struct ChatSystem {
    /// Primary store: (room_id, day_number, scope) → ordered list of messages.
    messages: std::collections::HashMap<MessageKey, Vec<ChatMessage>>,
}

impl ChatSystem {
    pub fn new() -> Self {
        Self {
            messages: std::collections::HashMap::new(),
        }
    }

    /// Add a message with phase-aware validation.
    ///
    /// # Errors
    /// - `ChatError::DeadPlayerCannotChat` — `is_alive` is `false`.
    /// - `ChatError::NightChatRestrictedToGhosts` — phase is Night and
    ///   `sender_faction` is `Faction::Villager`.
    ///
    /// Requirements: 16.2, 16.3, 20.1, 20.2
    pub fn add_message(
        &mut self,
        msg: ChatMessage,
        phase: &PhaseType,
        sender_faction: &Faction,
        is_alive: bool,
        day_number: u32,
    ) -> Result<(), ChatError> {
        // Requirement 16.3 / 20.2: dead players cannot chat.
        if !is_alive {
            return Err(ChatError::DeadPlayerCannotChat);
        }

        // Requirement 20.1 / 20.2: during Night, only Ghost/Special may chat.
        if *phase == PhaseType::Night && *sender_faction == Faction::Villager {
            return Err(ChatError::NightChatRestrictedToGhosts);
        }

        // Determine scope from the current phase.
        let scope = match phase {
            PhaseType::Night => ChatScope::Ghost,
            _ => ChatScope::Public,
        };

        let key = MessageKey {
            room_id: msg.game_id,
            day_number,
            scope,
        };

        self.messages.entry(key).or_default().push(msg);
        Ok(())
    }

    /// Return all public (day) messages for the given day number.
    ///
    /// Requirement 20.3, 20.4
    pub fn get_day_history(&self, room_id: &Uuid, day_number: u32) -> Vec<&ChatMessage> {
        let key = MessageKey {
            room_id: *room_id,
            day_number,
            scope: ChatScope::Public,
        };
        self.messages
            .get(&key)
            .map(|v| v.iter().collect::<Vec<&ChatMessage>>())
            .unwrap_or_default()
    }

    /// Return all ghost-only (night) messages for the given day number.
    ///
    /// Requirement 20.1, 20.4
    pub fn get_night_history(&self, room_id: &Uuid, day_number: u32) -> Vec<&ChatMessage> {
        let key = MessageKey {
            room_id: *room_id,
            day_number,
            scope: ChatScope::Ghost,
        };
        self.messages
            .get(&key)
            .map(|v| v.iter().collect::<Vec<&ChatMessage>>())
            .unwrap_or_default()
    }

    /// Return the night ghost chat history for Villager review at day start.
    ///
    /// This is the same data as `get_night_history` but is exposed under a
    /// distinct name to make the intent clear at call sites (Requirement 20.3).
    pub fn get_night_history_for_villagers(
        &self,
        room_id: &Uuid,
        day_number: u32,
    ) -> Vec<&ChatMessage> {
        self.get_night_history(room_id, day_number)
    }

    /// Return the most recent `limit` messages across all scopes (legacy helper).
    pub fn get_recent(&self, limit: usize) -> Vec<&ChatMessage> {
        let mut all: Vec<&ChatMessage> = self
            .messages
            .values()
            .flat_map(|v| v.iter())
            .collect::<Vec<&ChatMessage>>();
        // Sort by created_at
        all.sort_by(|a, b| a.created_at.cmp(&b.created_at));
        let len = all.len();
        if len <= limit {
            all
        } else {
            all[len - limit..].to_vec()
        }
    }
}

// ── Unit tests ────────────────────────────────────────────────────────────────

#[cfg(test)]
mod tests {
    use super::*;

    fn make_msg(room_id: Uuid, sender_id: Uuid, text: &str) -> ChatMessage {
        ChatMessage {
            message_id: Uuid::new_v4(),
            room_id,
            game_id: Uuid::new_v4(),
            phase_id: Some(Uuid::new_v4()),
            sender_id: Some(sender_id),
            chat_scope: "Public".to_string(),
            message_text: text.to_string(),
            created_at: Utc::now(),
        }
    }

    #[test]
    fn dead_player_cannot_chat() {
        let mut cs = ChatSystem::new();
        let r1 = Uuid::new_v4();
        let p1 = Uuid::new_v4();
        let msg = make_msg(r1, p1, "hello");
        let result = cs.add_message(msg, &PhaseType::Day, &Faction::Villager, false, 1);
        assert!(matches!(result, Err(ChatError::DeadPlayerCannotChat)));
    }

    #[test]
    fn villager_cannot_chat_at_night() {
        let mut cs = ChatSystem::new();
        let r1 = Uuid::new_v4();
        let p1 = Uuid::new_v4();
        let msg = make_msg(r1, p1, "hello");
        let result = cs.add_message(msg, &PhaseType::Night, &Faction::Villager, true, 1);
        assert!(matches!(result, Err(ChatError::NightChatRestrictedToGhosts)));
    }

    #[test]
    fn ghost_can_chat_at_night() {
        let mut cs = ChatSystem::new();
        let r1 = Uuid::new_v4();
        let p1 = Uuid::new_v4();
        let msg = make_msg(r1, p1, "boo");
        let result = cs.add_message(msg, &PhaseType::Night, &Faction::Ghost, true, 1);
        assert!(result.is_ok());
    }

    #[test]
    fn villager_can_chat_during_day() {
        let mut cs = ChatSystem::new();
        let r1 = Uuid::new_v4();
        let p1 = Uuid::new_v4();
        let msg = make_msg(r1, p1, "hi");
        let result = cs.add_message(msg, &PhaseType::Day, &Faction::Villager, true, 1);
        assert!(result.is_ok());
    }

    #[test]
    fn day_history_returns_correct_messages() {
        let mut cs = ChatSystem::new();
        let r1 = Uuid::new_v4();
        let p1 = Uuid::new_v4();
        let p2 = Uuid::new_v4();
        let msg1 = make_msg(r1, p1, "msg1");
        let msg2 = make_msg(r1, p2, "msg2");
        cs.add_message(msg1, &PhaseType::Day, &Faction::Villager, true, 2).unwrap();
        cs.add_message(msg2, &PhaseType::Day, &Faction::Villager, true, 2).unwrap();

        let history = cs.get_day_history(&r1, 2);
        assert_eq!(history.len(), 2);
    }

    #[test]
    fn night_history_returns_ghost_messages_only() {
        let mut cs = ChatSystem::new();
        let r1 = Uuid::new_v4();
        let p_ghost = Uuid::new_v4();
        let ghost_msg = make_msg(r1, p_ghost, "night whisper");
        cs.add_message(ghost_msg, &PhaseType::Night, &Faction::Ghost, true, 1).unwrap();

        let history = cs.get_night_history(&r1, 1);
        assert_eq!(history.len(), 1);
        assert_eq!(history[0].sender_id, Some(p_ghost));
    }

    #[test]
    fn night_history_for_villagers_matches_night_history() {
        let mut cs = ChatSystem::new();
        let r1 = Uuid::new_v4();
        let p_ghost = Uuid::new_v4();
        let ghost_msg = make_msg(r1, p_ghost, "secret");
        cs.add_message(ghost_msg, &PhaseType::Night, &Faction::Ghost, true, 3).unwrap();
 
        let for_villagers = cs.get_night_history_for_villagers(&r1, 3);
        let night = cs.get_night_history(&r1, 3);
        assert_eq!(for_villagers.len(), night.len());
    }
 
    #[test]
    fn messages_keyed_by_room_and_day() {
        let mut cs = ChatSystem::new();
        let r1 = Uuid::new_v4();
        let r2 = Uuid::new_v4();
        let p1 = Uuid::new_v4();
        let msg_r1_d1 = make_msg(r1, p1, "day1");
        let msg_r1_d2 = make_msg(r1, p1, "day2");
        let msg_r2_d1 = make_msg(r2, p1, "other room");
 
        cs.add_message(msg_r1_d1, &PhaseType::Day, &Faction::Villager, true, 1).unwrap();
        cs.add_message(msg_r1_d2, &PhaseType::Day, &Faction::Villager, true, 2).unwrap();
        cs.add_message(msg_r2_d1, &PhaseType::Day, &Faction::Villager, true, 1).unwrap();
 
        assert_eq!(cs.get_day_history(&r1, 1).len(), 1);
        assert_eq!(cs.get_day_history(&r1, 2).len(), 1);
        assert_eq!(cs.get_day_history(&r2, 1).len(), 1);
        assert_eq!(cs.get_day_history(&r1, 3).len(), 0);
    }
 
    #[test]
    fn special_faction_can_chat_at_night() {
        let mut cs = ChatSystem::new();
        let r1 = Uuid::new_v4();
        let p_sk = Uuid::new_v4();
        let msg = make_msg(r1, p_sk, "I am watching");
        let result = cs.add_message(msg, &PhaseType::Night, &Faction::Special, true, 1);
        assert!(result.is_ok());
    }
}
