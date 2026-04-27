//! Day-phase side effects (mute flags, announcements). Runtime applies chat gating separately.

use crate::models::GameParticipant;
use std::collections::HashMap;

#[derive(Clone, Debug, Default)]
pub struct DayMuteState {
    /// Player ids who cannot send global day chat (cursed), but may read if alive.
    pub muted_player_ids: Vec<String>,
}

pub struct DayResolver;

impl DayResolver {
    /// Apply curse marks for the next day (caller stores `muted_player_ids` on game state).
    pub fn apply_curse_marks(_participants: &HashMap<String, GameParticipant>, cursed: &[String]) -> DayMuteState {
        DayMuteState {
            muted_player_ids: cursed.to_vec(),
        }
    }

    pub fn can_send_global_day_chat(
        participant: &GameParticipant,
        muted: &[String],
    ) -> bool {
        participant.is_alive && !muted.contains(&participant.user_id)
    }

    pub fn can_vote_in_day(participant: &GameParticipant) -> bool {
        participant.is_alive
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::models::GameParticipant;

    fn p(id: &str, alive: bool) -> GameParticipant {
        GameParticipant {
            session_id: "s".into(),
            room_id: "r".into(),
            user_id: id.into(),
            username: id.into(),
            role: None,
            current_faction: Some("Villager".into()),
            transformed_to_ghoul: false,
            is_alive: alive,
            seat_number: 0,
            joined_at: "".into(),
        }
    }

    #[test]
    fn muted_alive_cannot_send() {
        let pl = p("u1", true);
        assert!(!DayResolver::can_send_global_day_chat(&pl, &["u1".into()]));
        assert!(DayResolver::can_send_global_day_chat(&pl, &[]));
    }
}
