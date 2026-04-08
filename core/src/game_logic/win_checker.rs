use crate::game_logic::roles::{Faction, Role};
use crate::models::GameParticipant;
use std::collections::HashMap;
use uuid::Uuid;

pub struct WinChecker;

impl WinChecker {
    /// Evaluates win conditions after each phase resolution.
    pub fn check_win(
        participants: &HashMap<Uuid, crate::game_logic::state::ParticipantInfo>,
        roles: &HashMap<i32, Role>,
    ) -> Option<Faction> {
        let mut living_villagers: u32 = 0;
        let mut living_ghosts: u32 = 0;
        let mut living_sk: u32 = 0;
        let mut living_nemesis: u32 = 0;
        let mut total_alive: u32 = 0;

        for p in participants.values() {
            if p.model.is_alive {
                total_alive += 1;
                if let Some(role) = roles.get(&p.model.role_id) {
                    match role.faction {
                        Faction::Ghost => living_ghosts += 1,
                        Faction::Special => {
                            if role.role_type == crate::game_logic::roles::RoleType::SerialKiller {
                                living_sk += 1;
                            } else if role.role_type == crate::game_logic::roles::RoleType::Nemesis {
                                living_nemesis += 1;
                            }
                        }
                        Faction::Villager => living_villagers += 1,
                        Faction::Draw => {}
                    }
                } else {
                    // No role cached? treat as villager for safety
                    living_villagers += 1;
                }
            }
        }

        // 1. Draw: SK == 1 AND Ghost == 1 AND total == 2
        if total_alive == 2 && living_sk == 1 && living_ghosts == 1 {
            return Some(Faction::Draw);
        }

        // 2. Serial Killer win: SK alive, total <= 2, no ghosts
        if living_sk > 0 && total_alive <= 2 && living_ghosts == 0 {
            return Some(Faction::Special);
        }

        // 3. Villager win: all Ghosts and Serial Killers are dead
        if living_ghosts == 0 && living_sk == 0 {
            return Some(Faction::Villager);
        }

        // 4. Ghost win: ghosts >= villagers + sk
        let _ = living_nemesis; // excluded from denominator
        if living_ghosts >= living_villagers + living_sk {
            return Some(Faction::Ghost);
        }

        None
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::game_logic::roles::{Faction, Role, RoleType};
    use uuid::Uuid;

    fn make_p(role_id: i32, alive: bool) -> crate::game_logic::state::ParticipantInfo {
        crate::game_logic::state::ParticipantInfo {
            model: GameParticipant {
                game_participant_id: Uuid::new_v4(),
                game_id: Uuid::new_v4(),
                player_id: Uuid::new_v4(),
                role_id,
                revealed_role_id: None,
                is_alive: alive,
                seat_number: 0,
                joined_at: chrono::Utc::now(),
                died_at: None,
                death_reason: None,
            },
            username: "TestPlayer".to_string(),
            role: None,
            is_silenced: false,
            protected_by: None,
            hidden_target: None,
        }
    }

    #[test]
    fn test_villager_win() {
        let mut participants = HashMap::new();
        let r1 = 1;
        let r_ghost = 2;
        let roles = HashMap::from([
            (r1, Role::new(RoleType::Villager)),
            (r_ghost, Role::new(RoleType::Ghost)),
        ]);

        let p1_id = Uuid::new_v4();
        participants.insert(p1_id, make_p(r1, true));
        
        let p2_id = Uuid::new_v4();
        participants.insert(p2_id, make_p(r_ghost, false));

        assert_eq!(WinChecker::check_win(&participants, &roles), Some(Faction::Villager));
    }
}
