use crate::game_logic::roles::Faction;
use crate::game_logic::rules_locked::GhostWinComparator;
use crate::models::GameParticipant;
use std::collections::HashMap;

/// Win evaluation — role codes V1–V9 / G10–G14 / S15–S16 are documented in
/// [`crate::game_logic::gm_spec`]. This checker uses coarse `GameParticipant.role` strings until roles are normalized.
pub struct WinChecker;

impl WinChecker {
    fn is_ghost_faction(p: &GameParticipant) -> bool {
        matches!(p.current_faction.as_deref(), Some("Ghost"))
            || p.role.as_deref() == Some("Ghost")
            || p.role.as_deref() == Some("Ghoul")
            || p.transformed_to_ghoul
    }

    /// Returns winning faction if the game should end, else `None`.
    pub fn check_win(participants: &HashMap<String, GameParticipant>) -> Option<Faction> {
        let mut living_villagers = 0u32;
        let mut living_ghosts = 0u32;
        let mut living_neutrals = 0u32;

        for p in participants.values() {
            if !p.is_alive {
                continue;
            }
            if Self::is_ghost_faction(p) {
                living_ghosts += 1;
            } else if p.role.as_deref() == Some("SerialKiller") {
                living_neutrals += 1;
            } else {
                living_villagers += 1;
            }
        }

        if living_ghosts == 0 && living_neutrals == 0 {
            return Some(Faction::Villager);
        }

        let non_ghost = living_villagers + living_neutrals;
        if GhostWinComparator::LOCKED.ghost_wins(living_ghosts, non_ghost) {
            return Some(Faction::Ghost);
        }

        if living_neutrals > 0 && living_ghosts == 0 && living_villagers <= 1 {
            return Some(Faction::Neutral);
        }

        None
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::models::GameParticipant;

    fn p(id: &str, role: Option<&str>, alive: bool) -> GameParticipant {
        GameParticipant {
            session_id: "s".into(),
            room_id: "r".into(),
            user_id: id.into(),
            username: "u".into(),
            role: role.map(String::from),
            current_faction: role.map(String::from),
            transformed_to_ghoul: false,
            is_alive: alive,
            seat_number: 0,
            joined_at: "".into(),
        }
    }

    #[test]
    fn ghost_wins_at_parity_with_non_ghosts() {
        let mut m = HashMap::new();
        m.insert("1".into(), p("1", Some("Ghost"), true));
        m.insert("2".into(), p("2", Some("Villager"), true));
        assert_eq!(WinChecker::check_win(&m), Some(Faction::Ghost));
    }
}
