use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub enum RoleType {
    Villager,
    Ghost,
    Seer,
    Doctor,
    Fool, // Unlucky in user description
    Soldier,
    Medium, // Shaman
    SerialKiller,
    DarkShaman, // Ghost helper
    Nemesis,    // Jester-like
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Role {
    pub role_type: RoleType,
    pub name: String,
    pub faction: Faction,
    pub description: String,
    pub skill_uses: u32,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub enum Faction {
    Villager,
    Ghost,
    Neutral,
}

impl Role {
    pub fn new(role_type: RoleType) -> Self {
        match role_type {
            RoleType::Villager => Role {
                role_type,
                name: "Villager".to_string(),
                faction: Faction::Villager,
                description: "Find the ghosts and vote them out.".to_string(),
                skill_uses: 0,
            },
            RoleType::Ghost => Role {
                role_type,
                name: "Ghost".to_string(),
                faction: Faction::Ghost,
                description: "Kill villagers at night. Don't get caught.".to_string(),
                skill_uses: 99, // Unlimited team kill
            },
            RoleType::Seer => Role {
                role_type,
                name: "Seer".to_string(),
                faction: Faction::Villager,
                description: "Inspect one player each night to see their faction.".to_string(),
                skill_uses: 99,
            },
            RoleType::Doctor => Role {
                role_type,
                name: "Doctor".to_string(),
                faction: Faction::Villager,
                description: "Protect one player each night from being killed.".to_string(),
                skill_uses: 99,
            },
            // Add other roles as needed
            _ => Role {
                role_type,
                name: "Unknown".to_string(),
                faction: Faction::Neutral,
                description: "Custom role".to_string(),
                skill_uses: 0,
            },
        }
    }
}
