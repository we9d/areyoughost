use crate::models::{GameAction, GameParticipant};
use std::collections::HashMap;

/// Resolve night actions (Kill, Heal, Inspect)
pub struct NightResolver;

impl NightResolver {
    pub fn resolve(
        actions: &Vec<GameAction>,
        participants: &mut HashMap<String, GameParticipant>,
    ) -> Vec<String> {
        let mut logs = Vec::new();
        let mut kills = HashMap::new(); // target_id -> killer_role
        let mut protected = Vec::new(); // target_id

        // 1. Process Protections (Doctor)
        for action in actions {
            if action.action_type == "PROTECT" {
                if let Some(target) = &action.target_id {
                    protected.push(target.clone());
                }
            }
        }

        // 2. Process Kills (Ghost, Serial Killer)
        for action in actions {
            if action.action_type == "KILL" {
                if let Some(target) = &action.target_id {
                    // Check if protected
                    if protected.contains(target) {
                        logs.push(format!("Player {} was attacked but protected!", target));
                    } else {
                        kills.insert(target.clone(), "Unknown");
                    }
                }
            }
        }

        // 3. Apply Deaths
        for (target, _killer) in kills {
            if let Some(p) = participants.get_mut(&target) {
                p.is_alive = false;
                logs.push(format!("Player {} died during the night.", p.username));
            }
        }

        logs
    }
}
