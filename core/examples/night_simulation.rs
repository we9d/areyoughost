use std::collections::HashMap;

use areyoughost_core::game_logic::role_engine::{
    resolve_night, EngineNightAction, EnginePlayerState, NightActionType, SkillUsageState,
};

fn main() {
    let mut players = HashMap::new();
    players.insert(
        "ghost_1".to_string(),
        EnginePlayerState {
            alive: true,
            role: "ผีปอบ".to_string(),
            cursed_silenced_today: false,
        },
    );
    players.insert(
        "doctor_1".to_string(),
        EnginePlayerState {
            alive: true,
            role: "แพทย์".to_string(),
            cursed_silenced_today: false,
        },
    );
    players.insert(
        "ghost_2".to_string(),
        EnginePlayerState {
            alive: true,
            role: "ผีกระสือใหญ่".to_string(),
            cursed_silenced_today: false,
        },
    );
    players.insert(
        "villager_1".to_string(),
        EnginePlayerState {
            alive: true,
            role: "ชาวบ้าน".to_string(),
            cursed_silenced_today: false,
        },
    );
    players.insert(
        "unlucky_1".to_string(),
        EnginePlayerState {
            alive: true,
            role: "คนดวงซวย".to_string(),
            cursed_silenced_today: false,
        },
    );

    let actions = vec![
        EngineNightAction {
            actor_id: "ghost_1".to_string(),
            action: NightActionType::GhostKill,
            target_id: Some("villager_1".to_string()),
        },
        EngineNightAction {
            actor_id: "ghost_2".to_string(),
            action: NightActionType::GhostKill,
            target_id: Some("villager_1".to_string()),
        },
        EngineNightAction {
            actor_id: "doctor_1".to_string(),
            action: NightActionType::DoctorProtect,
            target_id: Some("villager_1".to_string()),
        },
        EngineNightAction {
            actor_id: "ghost_1".to_string(),
            action: NightActionType::GhostKill,
            target_id: Some("unlucky_1".to_string()),
        },
    ];

    let mut skill_usage = HashMap::<String, SkillUsageState>::new();
    let summary = resolve_night(&mut players, &actions, &mut skill_usage);

    println!("Night summary:");
    println!("deaths = {:?}", summary.deaths);
    println!("protected = {:?}", summary.protected);
    println!("transformed = {:?}", summary.transformed);
    println!("revived = {:?}", summary.revived);
}
