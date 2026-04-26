use std::collections::{HashMap, HashSet};

#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub enum Team {
    Villagers,
    Ghosts,
    Special,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub enum RoleId {
    Villager,
    Seer,
    Doctor,
    Soldier,
    Police,
    Monk,
    Witch,
    Undertaker,
    Unlucky,
    Ghoul,
    Krasue,
    DeathOmen,
    Pret,
    DarkShaman,
    SerialKiller,
    Karma,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub enum NightActionType {
    GhostKill,
    SerialKill,
    SeerCheck,
    PoliceCheck,
    MonkAura,
    DoctorProtect,
    SoldierGuard,
    DarkProtect,
    DarkCurse,
    WitchRevive,
    WitchPoison,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct EngineNightAction {
    pub actor_id: String,
    pub action: NightActionType,
    pub target_id: Option<String>,
}

#[derive(Clone, Debug, Default)]
pub struct EnginePlayerState {
    pub alive: bool,
    pub role: String,
    pub cursed_silenced_today: bool,
}

#[derive(Clone, Debug, Default)]
pub struct SkillUsageState {
    pub doctor_success_used: bool,
    pub witch_revive_used: bool,
    pub witch_poison_used: bool,
}

#[derive(Clone, Debug, Default)]
pub struct NightResolutionSummary {
    pub deaths: Vec<String>,
    pub revived: Vec<String>,
    pub transformed: Vec<String>,
    pub protected: Vec<String>,
    pub cursed: Vec<String>,
    pub actions_by_type: HashMap<String, usize>,
}

pub fn role_from_th_name(name: &str) -> RoleId {
    match name {
        "ชาวบ้าน" => RoleId::Villager,
        "ร่างทรง" => RoleId::Seer,
        "แพทย์" => RoleId::Doctor,
        "ทหาร" => RoleId::Soldier,
        "ตำรวจ" => RoleId::Police,
        "พระธุดงค์" => RoleId::Monk,
        "หมอผีคุณไสย" => RoleId::Witch,
        "สัปเหร่อ" => RoleId::Undertaker,
        "คนดวงซวย" => RoleId::Unlucky,
        "ผีปอบ" => RoleId::Ghoul,
        "ผีกระสือใหญ่" => RoleId::Krasue,
        "ผีตายโหง" => RoleId::DeathOmen,
        "ผีเปรต" => RoleId::Pret,
        "หมอผีดำ" => RoleId::DarkShaman,
        "ฆาตกรต่อเนื่อง" => RoleId::SerialKiller,
        "เจ้ากรรมนายเวร" => RoleId::Karma,
        _ => RoleId::Villager,
    }
}

pub fn team_of_role(role_name: &str) -> Team {
    match role_from_th_name(role_name) {
        RoleId::Ghoul
        | RoleId::Krasue
        | RoleId::DeathOmen
        | RoleId::Pret
        | RoleId::DarkShaman => Team::Ghosts,
        RoleId::SerialKiller | RoleId::Karma => Team::Special,
        _ => Team::Villagers,
    }
}

pub fn resolve_night(
    players: &mut HashMap<String, EnginePlayerState>,
    actions: &[EngineNightAction],
    skill_usage: &mut HashMap<String, SkillUsageState>,
) -> NightResolutionSummary {
    let mut out = NightResolutionSummary::default();
    let mut ghost_targets = Vec::new();
    let mut serial_kills = Vec::new();
    let mut witch_poisons = Vec::new();
    let mut doctor_protect = HashSet::new();
    let mut soldier_guards: HashMap<String, String> = HashMap::new();
    let mut dark_protect = HashSet::new();
    let mut dark_curse = HashSet::new();
    let mut witch_revive = HashSet::new();

    for action in actions {
        *out.actions_by_type
            .entry(format!("{:?}", action.action))
            .or_insert(0) += 1;
        match action.action {
            NightActionType::GhostKill => {
                if let Some(t) = &action.target_id {
                    ghost_targets.push(t.clone());
                }
            }
            NightActionType::SerialKill => {
                if let Some(t) = &action.target_id {
                    serial_kills.push(t.clone());
                }
            }
            NightActionType::DoctorProtect => {
                if let Some(t) = &action.target_id {
                    let used = skill_usage
                        .get(&action.actor_id)
                        .map(|s| s.doctor_success_used)
                        .unwrap_or(false);
                    if !used {
                        doctor_protect.insert(t.clone());
                    }
                }
            }
            NightActionType::SoldierGuard => {
                if let Some(t) = &action.target_id {
                    soldier_guards.insert(t.clone(), action.actor_id.clone());
                }
            }
            NightActionType::DarkProtect => {
                if let Some(t) = &action.target_id {
                    dark_protect.insert(t.clone());
                }
            }
            NightActionType::DarkCurse => {
                if let Some(t) = &action.target_id {
                    dark_curse.insert(t.clone());
                }
            }
            NightActionType::WitchRevive => {
                if let Some(t) = &action.target_id {
                    let used = skill_usage
                        .get(&action.actor_id)
                        .map(|s| s.witch_revive_used)
                        .unwrap_or(false);
                    if !used {
                        witch_revive.insert(t.clone());
                    }
                }
            }
            NightActionType::WitchPoison => {
                if let Some(t) = &action.target_id {
                    let used = skill_usage
                        .get(&action.actor_id)
                        .map(|s| s.witch_poison_used)
                        .unwrap_or(false);
                    if !used {
                        witch_poisons.push((action.actor_id.clone(), t.clone()));
                    }
                }
            }
            NightActionType::SeerCheck | NightActionType::PoliceCheck | NightActionType::MonkAura => {}
        }
    }

    let ghost_kill = majority_target(&ghost_targets);
    let mut kill_intents: Vec<(Option<String>, String)> = Vec::new();
    if let Some(target) = ghost_kill {
        kill_intents.push((None, target));
    }
    for t in serial_kills {
        kill_intents.push((None, t));
    }
    for (actor_id, t) in witch_poisons {
        if let Some(s) = skill_usage.get_mut(&actor_id) {
            s.witch_poison_used = true;
        } else {
            skill_usage.insert(
                actor_id,
                SkillUsageState {
                    witch_poison_used: true,
                    ..SkillUsageState::default()
                },
            );
        }
        kill_intents.push((None, t));
    }

    let mut deaths = HashSet::<String>::new();
    let mut doctor_consumed = false;

    for (_, target) in kill_intents {
        if !players.get(&target).map(|p| p.alive).unwrap_or(false) {
            continue;
        }

        if dark_protect.contains(&target) {
            out.protected.push(target);
            continue;
        }

        if doctor_protect.contains(&target) {
            out.protected.push(target.clone());
            doctor_consumed = true;
            continue;
        }

        if let Some(guard_id) = soldier_guards.get(&target) {
            if players.get(guard_id).map(|p| p.alive).unwrap_or(false) {
                deaths.insert(guard_id.clone());
                continue;
            }
        }

        deaths.insert(target);
    }

    for target in dark_curse {
        if let Some(p) = players.get_mut(&target) {
            if p.alive {
                p.cursed_silenced_today = true;
                out.cursed.push(target);
            }
        }
    }

    for target in deaths.clone() {
        let is_unlucky = players
            .get(&target)
            .map(|p| role_from_th_name(&p.role) == RoleId::Unlucky)
            .unwrap_or(false);
        if is_unlucky {
            if let Some(p) = players.get_mut(&target) {
                p.role = "ผีปอบ".to_string();
                out.transformed.push(target.clone());
            }
            deaths.remove(&target);
        }
    }

    for target in &deaths {
        if let Some(p) = players.get_mut(target) {
            p.alive = false;
        }
    }

    for target in witch_revive {
        if deaths.contains(&target) {
            deaths.remove(&target);
            if let Some(p) = players.get_mut(&target) {
                p.alive = true;
                out.revived.push(target);
            }
        }
    }

    out.deaths = deaths.into_iter().collect();
    if doctor_consumed {
        for action in actions {
            if action.action == NightActionType::DoctorProtect {
                let entry = skill_usage.entry(action.actor_id.clone()).or_default();
                entry.doctor_success_used = true;
            }
        }
    }
    for action in actions {
        if action.action == NightActionType::WitchRevive
            && action.target_id.is_some()
            && out.revived.iter().any(|id| Some(id) == action.target_id.as_ref())
        {
            let entry = skill_usage.entry(action.actor_id.clone()).or_default();
            entry.witch_revive_used = true;
        }
    }
    out
}

pub fn check_win(players: &HashMap<String, EnginePlayerState>) -> Option<&'static str> {
    let mut villagers = 0usize;
    let mut ghosts = 0usize;
    let mut serial = 0usize;
    let mut karma = 0usize;

    for p in players.values() {
        if !p.alive {
            continue;
        }
        match role_from_th_name(&p.role) {
            RoleId::Ghoul | RoleId::Krasue | RoleId::DeathOmen | RoleId::Pret | RoleId::DarkShaman => ghosts += 1,
            RoleId::SerialKiller => serial += 1,
            RoleId::Karma => karma += 1,
            _ => villagers += 1,
        }
    }

    if ghosts == 0 && serial == 0 && karma == 0 {
        return Some("villagers");
    }
    if serial == 1 && ghosts == 0 && villagers == 0 && karma == 0 {
        return Some("serial_killer");
    }
    if ghosts > 0 && ghosts >= villagers + serial + karma {
        return Some("ghosts");
    }
    None
}

fn majority_target(targets: &[String]) -> Option<String> {
    if targets.is_empty() {
        return None;
    }
    let mut counts = HashMap::<&str, usize>::new();
    for t in targets {
        *counts.entry(t.as_str()).or_insert(0) += 1;
    }
    let max = counts.values().copied().max().unwrap_or(0);
    let leaders: Vec<_> = counts
        .iter()
        .filter(|(_, c)| **c == max)
        .map(|(t, _)| (*t).to_string())
        .collect();
    if leaders.len() == 1 {
        Some(leaders[0].clone())
    } else {
        None
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn unlucky_transforms_on_first_night_kill() {
        let mut players = HashMap::new();
        players.insert(
            "u".to_string(),
            EnginePlayerState {
                alive: true,
                role: "คนดวงซวย".to_string(),
                cursed_silenced_today: false,
            },
        );
        players.insert(
            "g".to_string(),
            EnginePlayerState {
                alive: true,
                role: "ผีปอบ".to_string(),
                cursed_silenced_today: false,
            },
        );
        let actions = vec![EngineNightAction {
            actor_id: "g".to_string(),
            action: NightActionType::GhostKill,
            target_id: Some("u".to_string()),
        }];
        let mut usage = HashMap::new();
        let out = resolve_night(&mut players, &actions, &mut usage);
        assert!(out.deaths.is_empty());
        assert_eq!(players["u"].role, "ผีปอบ");
    }
}
