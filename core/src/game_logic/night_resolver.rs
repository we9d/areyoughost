use crate::models::{GameAction, GameParticipant};
use crate::network::message::DeathInfo;
use crate::game_logic::roles::{Role, RoleType};
use std::collections::{HashMap, HashSet};
use uuid::Uuid;

/// Resolve night actions in priority order:
/// 1. PROTECT  — Doctor marks protected_targets
/// 2. INFORMATION — Seer/Police/Monk/Medium inspections
/// 3. KILL — Ghost/SK kills, checked against protected_targets
pub struct NightResolver;

impl NightResolver {
    pub fn resolve(
        participants: &mut HashMap<Uuid, crate::game_logic::state::ParticipantInfo>,
        roles: &HashMap<i32, Role>,
        actions: &[GameAction],
    ) -> Vec<DeathInfo> {
        // ── Phase 1: PROTECT ─────────────────────────────────────────
        let mut protected_targets: HashSet<Uuid> = HashSet::new();

        for action in actions {
            if action.action_type == "DOCTOR_HEAL" || action.action_type == "PROTECT" {
                if let Some(target_id) = &action.target_id {
                    protected_targets.insert(*target_id);
                    // Note: In Phase 5+, protected_by is stored in participant_states table,
                    // not directly on GameParticipant anymore.
                    // For now, we'll track it in the local `protected_targets` set for this resolution.
                }
            }
        }

        // ── Phase 2: INFORMATION ─────────────────────────────────────
        // Monk: block inspection on target (collect blocked targets first)
        let mut monk_blocked: HashSet<Uuid> = HashSet::new();
        for action in actions {
            if action.action_type == "BLOCK_CHECK" {
                if let Some(target_id) = &action.target_id {
                    monk_blocked.insert(*target_id);
                }
            }
        }

        for action in actions {
            match action.action_type.as_str() {
                "INSPECT_FACTION" => {
                    if let Some(target_id) = &action.target_id {
                        if monk_blocked.contains(target_id) {
                            continue;
                        }
                        if let Some(participant) = participants.get(target_id) {
                            if let Some(role) = roles.get(&participant.model.role_id) {
                                let _result = if role.role_type == RoleType::DeceiverGhost {
                                    "VILLAGER"
                                } else {
                                    role.seer_result.as_str()
                                };
                            }
                        }
                    }
                }
                "INSPECT_AURA" => {
                    if let Some(target_id) = &action.target_id {
                        if monk_blocked.contains(target_id) {
                            continue;
                        }
                        if let Some(participant) = participants.get(target_id) {
                            if let Some(role) = roles.get(&participant.model.role_id) {
                                let _result = if role.role_type == RoleType::QueenGhost {
                                    "GOOD"
                                } else {
                                    role.aura_result.as_str()
                                };
                            }
                        }
                    }
                }
                _ => {}
            }
        }

        // ── Phase 3: KILL ────────────────────────────────────────────
        let mut deaths: Vec<DeathInfo> = Vec::new();

        for action in actions {
            if action.action_type != "KILL" {
                continue;
            }
            let target_id = match action.target_id {
                Some(id) => id,
                None => continue,
            };

            // Skip if protected by Doctor
            if protected_targets.contains(&target_id) {
                continue;
            }

            // Soldier self-protect check
            // Note: skill_usage is now in participant_skill_usages, but for 
            // the core resolution we'll assume it's passed or handled via state maps.
            // TEMPORARY: Placeholder for Soldier logic until we integrate fat states.
            let soldier_saved = false;

            if soldier_saved {
                continue; // skip death
            }
            // Apply death
            if let Some(p) = participants.get_mut(&target_id) {
                if p.model.is_alive {
                    p.model.is_alive = false;
                    let role_name = roles.get(&p.model.role_id)
                        .map(|r| r.name.clone())
                        .unwrap_or_else(|| "Unknown".to_string());
                    
                    deaths.push(DeathInfo {
                        player_id: p.model.player_id,
                        username: p.username.clone(),
                        role_name,
                    });
                }
            }
        }

        deaths
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::game_logic::roles::{Role, RoleType};
    use uuid::Uuid;

    fn make_participant(player_id: Uuid, role_id: i32) -> crate::game_logic::state::ParticipantInfo {
        crate::game_logic::state::ParticipantInfo {
            model: GameParticipant {
                game_participant_id: Uuid::new_v4(),
                game_id: Uuid::new_v4(),
                player_id,
                role_id,
                revealed_role_id: None,
                is_alive: true,
                seat_number: 1,
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

    fn make_action(actor_id: Uuid, target_id: Option<Uuid>, action_type: &str) -> GameAction {
        GameAction {
            action_id: Uuid::new_v4(),
            game_id: Uuid::new_v4(),
            phase_id: Uuid::new_v4(),
            actor_id,
            target_id,
            action_type: action_type.to_string(),
            created_at: chrono::Utc::now(),
        }
    }

    #[test]
    fn test_kill_without_protection_causes_death() {
        let mut participants = HashMap::new();
        let p1_id = Uuid::new_v4();
        let role_map = HashMap::from([(1, Role::new(RoleType::Villager))]);
        
        participants.insert(p1_id, make_participant(p1_id, 1));

        let actions = vec![make_action(Uuid::new_v4(), Some(p1_id), "KILL")];
        let deaths = NightResolver::resolve(&mut participants, &role_map, &actions);

        assert_eq!(deaths.len(), 1);
        assert_eq!(deaths[0].player_id, p1_id);
        assert!(!participants[&p1_id].model.is_alive);
    }

    #[test]
    fn test_protect_prevents_kill() {
        let mut participants = HashMap::new();
        let p1_id = Uuid::new_v4();
        let role_map = HashMap::from([(1, Role::new(RoleType::Villager))]);
        
        participants.insert(p1_id, make_participant(p1_id, 1));

        let actions = vec![
            make_action(Uuid::new_v4(), Some(p1_id), "PROTECT"),
            make_action(Uuid::new_v4(), Some(p1_id), "KILL"),
        ];
        let deaths = NightResolver::resolve(&mut participants, &role_map, &actions);

        assert_eq!(deaths.len(), 0);
        assert!(participants[&p1_id].model.is_alive);
    }
}
