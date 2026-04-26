//! Batch night resolution (collect first, resolve in fixed order).
//! See [`crate::game_logic::gm_spec::NIGHT_RESOLUTION_STEPS`] for the full GM checklist.
//! Current implementation: collect kills → protection block → finalize deaths → revive.

use crate::game_logic::gm_spec::NightGmReport;
use crate::game_logic::rules_locked::{DarkShamanProtectPolicy, ReviveConstraints};
use crate::models::{GameAction, GameParticipant};
use std::collections::{HashMap, HashSet};

/// Back-compat name for [`NightGmReport`].
pub type NightResolutionResult = NightGmReport;

pub struct NightResolver;

impl NightResolver {
    /// Deterministic batch resolve. `protect_targets` are player user_ids protected this night.
    pub fn resolve_batch(
        actions: &[GameAction],
        participants: &mut HashMap<String, GameParticipant>,
        protect_targets: &[String],
        revive_target: Option<&str>,
    ) -> NightGmReport {
        let mut out = NightGmReport::default();
        let protected: HashSet<String> = protect_targets.iter().cloned().collect();

        // A — collect kill intents (target user_id)
        let mut kill_targets: Vec<String> = Vec::new();
        let mut ghost_kill_targets: HashSet<String> = HashSet::new();
        for a in actions {
            if a.action_type.eq_ignore_ascii_case("KILL") {
                if let Some(t) = &a.target_id {
                    kill_targets.push(t.clone());
                    let actor_role = participants
                        .get(&a.actor_id)
                        .and_then(|p| p.role.as_deref())
                        .unwrap_or_default();
                    if actor_role.eq_ignore_ascii_case("Ghost")
                        || actor_role.eq_ignore_ascii_case("Ghoul")
                        || actor_role.eq_ignore_ascii_case("G10")
                        || actor_role.eq_ignore_ascii_case("G11")
                        || actor_role.eq_ignore_ascii_case("G12")
                        || actor_role.eq_ignore_ascii_case("G13")
                        || actor_role.eq_ignore_ascii_case("G14")
                    {
                        ghost_kill_targets.insert(t.clone());
                    }
                }
            }
        }

        // B — protection (first kill on protected target consumes one block per policy)
        let mut pending_kills: Vec<String> = Vec::new();
        for t in kill_targets {
            if protected.contains(&t) {
                match DarkShamanProtectPolicy::LOCKED {
                    DarkShamanProtectPolicy::BlockSingleKillSource => {
                        out.logs.push(format!("Kill on {t} blocked by protection (single-source policy)"));
                        out.protected.push(t.clone());
                        // One block only: subsequent kills in same batch would still apply — for MVP we skip one kill per protected target
                        continue;
                    }
                }
            }
            pending_kills.push(t);
        }

        // C — special hooks placeholder (curse/transform) — extend per role doc
        for t in pending_kills.iter() {
            if let Some(p) = participants.get_mut(t) {
                let is_unlucky =
                    p.role.as_deref() == Some("UnluckyMan") || p.role.as_deref() == Some("V9");
                if is_unlucky && !p.transformed_to_ghoul && ghost_kill_targets.contains(t) {
                    p.transformed_to_ghoul = true;
                    p.current_faction = Some("Ghost".to_string());
                    p.role = Some("Ghoul".to_string());
                    out.transformed.push(t.clone());
                    out.logs.push(format!(
                        "Player {} survived first ghost attack and transformed into Ghoul.",
                        p.username
                    ));
                }
            }
        }
        pending_kills.retain(|t| {
            participants
                .get(t)
                .map(|p| !p.transformed_to_ghoul || p.role.as_deref() != Some("Ghoul"))
                .unwrap_or(true)
        });

        // D — finalize deaths
        let mut died: HashSet<String> = HashSet::new();
        for t in pending_kills {
            if let Some(p) = participants.get_mut(&t) {
                if p.is_alive {
                    p.is_alive = false;
                    died.insert(t.clone());
                    out.deaths.push(t.clone());
                    out.logs.push(format!("Player {} died during the night.", p.username));
                }
            }
        }

        // E — revive (same-night deaths only per locked policy)
        if let Some(rt) = revive_target {
            match ReviveConstraints::LOCKED {
                ReviveConstraints::SameNightDeathsOnly => {
                    if died.contains(rt) {
                        if let Some(p) = participants.get_mut(rt) {
                            p.is_alive = true;
                            out.revived.push(rt.to_string());
                            out.logs.push(format!("Player {} revived (same-night policy).", p.username));
                        }
                    }
                }
            }
        }

        out
    }

    /// Back-compat thin wrapper around `resolve_batch` with only PROTECT/KILL from flat actions.
    pub fn resolve(
        actions: &Vec<GameAction>,
        participants: &mut HashMap<String, GameParticipant>,
    ) -> Vec<String> {
        let protects: Vec<String> = actions
            .iter()
            .filter(|a| a.action_type == "PROTECT")
            .filter_map(|a| a.target_id.clone())
            .collect();
        let r = Self::resolve_batch(actions, participants, &protects, None);
        r.logs
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::models::GameParticipant;

    fn participant(id: &str, name: &str) -> GameParticipant {
        GameParticipant {
            session_id: "s".into(),
            room_id: "r".into(),
            user_id: id.into(),
            username: name.into(),
            role: Some("Ghost".into()),
            current_faction: Some("Ghost".into()),
            transformed_to_ghoul: false,
            is_alive: true,
            seat_number: 0,
            joined_at: "".into(),
        }
    }

    #[test]
    fn protect_blocks_kill() {
        let mut m = HashMap::new();
        m.insert("v1".into(), participant("v1", "A"));
        let actions = vec![
            GameAction {
                action_id: "1".into(),
                room_id: "r".into(),
                phase_id: "p".into(),
                actor_id: "g1".into(),
                target_id: Some("v1".into()),
                action_type: "KILL".into(),
                action_result: None,
                created_at: "".into(),
            },
            GameAction {
                action_id: "2".into(),
                room_id: "r".into(),
                phase_id: "p".into(),
                actor_id: "d1".into(),
                target_id: Some("v1".into()),
                action_type: "PROTECT".into(),
                action_result: None,
                created_at: "".into(),
            },
        ];
        let r = NightResolver::resolve_batch(&actions, &mut m, &["v1".into()], None);
        assert!(m["v1"].is_alive);
        assert!(r.deaths.is_empty());
        assert_eq!(r.protected, vec!["v1".to_string()]);
    }
}
