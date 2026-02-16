use crate::game_logic::roles::Faction;
use crate::models::GameParticipant;
use std::collections::HashMap;

pub struct WinChecker;

impl WinChecker {
    pub fn check_win(participants: &HashMap<String, GameParticipant>) -> Option<Faction> {
        let mut living_villagers = 0;
        let mut living_ghosts = 0;
        let mut living_neutrals = 0; // SK, etc.

        for p in participants.values() {
            if p.is_alive {
                // Simplified faction check based on role string for now
                // In real implementation, map role string to Faction enum
                if p.role.as_deref() == Some("Ghost") {
                    living_ghosts += 1;
                } else if p.role.as_deref() == Some("SerialKiller") {
                    living_neutrals += 1;
                } else {
                    living_villagers += 1;
                }
            }
        }

        if living_ghosts == 0 && living_neutrals == 0 {
            return Some(Faction::Villager);
        }

        if living_ghosts >= living_villagers + living_neutrals {
            return Some(Faction::Ghost);
        }

        if living_neutrals > 0 && living_ghosts == 0 && living_villagers <= 1 {
            // Simplified SK win condition
            return Some(Faction::Neutral);
        }

        None
    }
}
