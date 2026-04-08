/// engine.rs — Scalable, data-driven Night/Day resolution engine.
///
/// Design principles:
///  • No per-role `match` statements — skills drive all behavior.
///  • `GameContext` is an atomic scratchpad built each phase.
///  • Extending to 50+ roles = add a row to `build.rs`, done.

use std::collections::{HashMap, HashSet};
use serde_json::Value;
use areyoughost_core::game_logic::roles::SkillType;
use areyoughost_core::models::GameAction;
use areyoughost_core::game_logic::state::ParticipantInfo;
use uuid::Uuid;

pub type PlayerId = Uuid;

// ── GameContext ───────────────────────────────────────────────────
/// Scratch-pad built fresh every phase resolution.
#[derive(Default)]
pub struct GameContext {
    pub pending_kills:  Vec<PlayerId>,
    pub protections:    HashMap<PlayerId, PlayerId>, // target → protector
    pub revives:        Vec<PlayerId>,
    pub silenced:       HashSet<PlayerId>,
    /// Per-player investigation results (actor_id → result_json)
    pub results:        HashMap<PlayerId, Value>,
}

// ── Skill Execution ───────────────────────────────────────────────
/// Generic execution — pure switch on SkillType, no role knowledge needed.
pub fn execute_skill(
    ctx: &mut GameContext,
    skill_type: &SkillType,
    actor_id: &Uuid,
    target_id: Option<&Uuid>,
    participants: &HashMap<Uuid, ParticipantInfo>,
) {
    match skill_type {
        SkillType::Kill => {
            if let Some(t) = target_id {
                ctx.pending_kills.push(*t);
            }
        }
        SkillType::Protect => {
            if let Some(t) = target_id {
                ctx.protections.insert(*t, *actor_id);
            }
        }
        SkillType::CheckFaction => {
            if let Some(t) = target_id {
                let result = participants.get(t)
                    .and_then(|p| p.role.as_ref())
                    .map(|r| r.seer_result.clone())
                    .unwrap_or_else(|| "VILLAGER".to_string());
                ctx.results.insert(*actor_id, serde_json::json!({
                    "type": "faction_check",
                    "target": t,
                    "result": result
                }));
            }
        }
        SkillType::CheckAura => {
            if let Some(t) = target_id {
                let result = participants.get(t)
                    .and_then(|p| p.role.as_ref())
                    .map(|r| r.aura_result.clone())
                    .unwrap_or_else(|| "GOOD".to_string());
                ctx.results.insert(*actor_id, serde_json::json!({
                    "type": "aura_check",
                    "target": t,
                    "result": result
                }));
            }
        }
        SkillType::ViewDead => {
            if let Some(t) = target_id {
                let role_name = participants.get(t)
                    .filter(|p| !p.model.is_alive)
                    .and_then(|p| p.role.as_ref())
                    .map(|r| r.name.clone())
                    .unwrap_or_else(|| "?".to_string());
                ctx.results.insert(*actor_id, serde_json::json!({
                    "type": "view_dead",
                    "target": t,
                    "role": role_name
                }));
            }
        }
        SkillType::Silence => {
            if let Some(t) = target_id {
                ctx.silenced.insert(*t);
            }
        }
        SkillType::Revive => {
            if let Some(t) = target_id {
                ctx.revives.push(*t);
            }
        }
        SkillType::Block => {
            // TODO: Implement block logic
        }
        SkillType::Special => {
            // TODO: Implement special logic
        }
    }
}

// ── Night Resolution ─────────────────────────────────────────────
/// Resolves all night actions in strict priority order.
/// Returns a JSON summary of deaths and investigation results.
pub fn resolve_night(
    participants: &mut HashMap<Uuid, ParticipantInfo>,
    actions: &[GameAction],
) -> Value {
    let mut ctx = GameContext::default();

    // Reset per-phase state
    for p in participants.values_mut() {
        p.protected_by = None;
        p.is_silenced  = false;
    }

    // ── Priority processing ────────────────────────────
    // 1. Ghost Kill (highest group priority)
    for a in actions.iter().filter(|a| a.action_type == "GHOST_KILL") {
        execute_skill(&mut ctx, &SkillType::Kill, &a.actor_id, a.target_id.as_ref(), participants);
    }
    // 2. SK Kill
    for a in actions.iter().filter(|a| a.action_type == "SK_KILL") {
        execute_skill(&mut ctx, &SkillType::Kill, &a.actor_id, a.target_id.as_ref(), participants);
    }
    // 3-5. Investigations (results built into ctx, no state mutation)
    for a in actions.iter().filter(|a| matches!(
        a.action_type.as_str(), "SEER_INSPECT" | "POLICE_CHECK" | "CHECK_AURA"
    )) {
        if let Some(st) = SkillType::from_code(&a.action_type) {
            execute_skill(&mut ctx, &st, &a.actor_id, a.target_id.as_ref(), participants);
        }
    }
    // 6. Doctor
    for a in actions.iter().filter(|a| a.action_type == "DOCTOR_HEAL") {
        execute_skill(&mut ctx, &SkillType::Protect, &a.actor_id, a.target_id.as_ref(), participants);
    }
    // 7-9. Silence / other effects
    for a in actions.iter().filter(|a| !matches!(
        a.action_type.as_str(),
        "GHOST_KILL" | "SK_KILL" | "SEER_INSPECT" | "POLICE_CHECK" | "CHECK_AURA" | "DOCTOR_HEAL"
    )) {
        if let Some(st) = SkillType::from_code(&a.action_type) {
            execute_skill(&mut ctx, &st, &a.actor_id, a.target_id.as_ref(), participants);
        }
    }

    // 10. Resolve deaths (kill - protected - revived)
    let mut deaths = Vec::new();
    for target_id in &ctx.pending_kills {
        if ctx.protections.contains_key(target_id) {
            // Protected — mark who saved them
            if let Some(p) = participants.get_mut(target_id) {
                p.protected_by = ctx.protections.get(target_id).copied();
            }
            continue;
        }
        if ctx.revives.contains(target_id) {
            continue;
        }
        if let Some(p) = participants.get_mut(target_id) {
            if p.model.is_alive {
                p.model.is_alive = false;
                deaths.push(*target_id);
            }
        }
    }

    // 11. Apply silence
    for pid in &ctx.silenced {
        if let Some(p) = participants.get_mut(pid) {
            p.is_silenced = true;
        }
    }

    serde_json::json!({
        "deaths":  deaths,
        "results": ctx.results,
        "silenced": Vec::from_iter(ctx.silenced),
    })
}

// ── Day/Vote Resolution ──────────────────────────────────────────
/// Executes the vote target. Returns deaths + events.
pub fn resolve_vote(
    participants: &mut HashMap<Uuid, ParticipantInfo>,
    target_id: Option<&Uuid>,
) -> Value {
    let mut deaths = Vec::new();
    let mut events = Vec::new();

    if let Some(tid) = target_id {
        if let Some(p) = participants.get_mut(tid) {
            if p.model.is_alive {
                p.model.is_alive = false;
                deaths.push(*tid);

                // G12 (AvengerGhost) extra kill triggered by vote death
                let is_avenger = p.role.as_ref()
                    .map(|r| r.role_code == "AVENGERGHOST")
                    .unwrap_or(false);

                if is_avenger {
                    events.push(serde_json::json!({ "type": "avenger_triggered" }));
                    // Actual random extra kill must be resolved by the caller
                    // (needs access to participants after borrow is released)
                }
            }
        }
    }

    serde_json::json!({
        "deaths": deaths,
        "events": events,
    })
}

// ── Win Condition Engine ─────────────────────────────────────────
/// Checks in strict priority order as defined by the master guide.
/// Returns faction string or null.
pub fn check_win(
    participants: &HashMap<Uuid, ParticipantInfo>,
    target_voted_out: Option<&Uuid>,   // for Nemesis/Vengeful check
) -> Option<String> {
    let alive: Vec<&ParticipantInfo> = participants.values()
        .filter(|p| p.model.is_alive)
        .collect();

    // 1. Nemesis (Vengeful Spirit) — target was voted out
    if let Some(tv) = target_voted_out {
        // Find any Nemesis whose hidden_target == voted player
        let nemesis_wins = participants.values().any(|p| {
            p.role.as_ref().map(|r| r.role_code == "NEMESIS").unwrap_or(false)
                && p.hidden_target == Some(*tv)
        });
        if nemesis_wins {
            return Some("SPECIAL".to_string());
        }
    }

    // 2. Fool (wins when voted out — handled as SPECIAL faction win too)
    // (already applied during vote resolution)

    // 3. Draw Case 1: 2 alive, one is Nemesis + its target
    if alive.len() == 2 {
        let has_nemesis = alive.iter().any(|p| {
            p.role.as_ref().map(|r| r.role_code == "NEMESIS").unwrap_or(false)
        });
        let has_sk = alive.iter().any(|p| {
            p.role.as_ref().map(|r| r.role_code == "SERIALKILLER").unwrap_or(false)
        });
        let has_ghost_type = alive.iter().any(|p| {
            p.role.as_ref().map(|r| {
                matches!(r.role_code.as_str(), "GHOST" | "QUEENGHOST" | "AVENGERGHOST" | "DECEIVERGHOST" | "DARKSHAMAN")
            }).unwrap_or(false)
        });

        // Draw if SK vs Ghost, or Nemesis vs its target (goodie)
        if has_sk && has_ghost_type {
            return Some("DRAW".to_string());
        }
        if has_nemesis {
            return Some("DRAW".to_string());
        }
    }

    // 4. Serial Killer: last one standing
    if alive.len() == 1 {
        let is_sk = alive[0].role.as_ref()
            .map(|r| r.role_code == "SERIALKILLER")
            .unwrap_or(false);
        if is_sk {
            return Some("SPECIAL".to_string());
        }
    }

    // 5. Villager: no ghosts alive
    let ghost_alive = alive.iter().any(|p| {
        p.role.as_ref().map(|r| r.aura_result == "EVIL" && r.seer_result == "GHOST").unwrap_or(false)
    });
    if !ghost_alive {
        return Some("VILLAGER".to_string());
    }

    // 6. Ghost: outnumber villagers
    let ghost_count = alive.iter().filter(|p| {
        p.role.as_ref().map(|r| r.aura_result == "EVIL" && r.seer_result == "GHOST").unwrap_or(false)
    }).count();
    let villager_count = alive.iter().filter(|p| {
        p.role.as_ref().map(|r| !(r.aura_result == "EVIL" && r.seer_result == "GHOST")).unwrap_or(true)
    }).count();
    if ghost_count >= villager_count {
        return Some("GHOST".to_string());
    }

    None
}
