use crate::game_logic::roles::{Role, RoleType};
use rand::seq::SliceRandom;
use rand::thread_rng;

pub struct RoleDistributor;

impl RoleDistributor {
    pub fn assign_roles(player_count: usize) -> Vec<Role> {
        let mut roles = Vec::new();

        // Base distribution based on player count
        // 6: 3 Villager, 2 Ghost, 1 Special
        // 8: 4 Villager, 3 Ghost, 1 Special
        // ... (Implement logic based on user spec)

        let (villagers, ghosts, specials) = match player_count {
            6 => (3, 2, 1),
            7 => (3, 2, 2),
            8 => (4, 3, 1),
            9 => (4, 3, 2),
            10 => (5, 3, 2),
            11 => (5, 3, 3),
            12 => (6, 4, 2),
            // Fallback / larger groups
            n => (n / 2, n / 3, n - (n / 2 + n / 3)),
        };

        // Add Villagers
        for _ in 0..villagers {
            roles.push(Role::new(RoleType::Villager));
        }

        // Add Ghosts
        for _ in 0..ghosts {
            roles.push(Role::new(RoleType::Ghost));
        }

        // Add Specials
        // For now, simple logic: Seer > Doctor > etc.
        let special_pool = vec![
            RoleType::Seer,
            RoleType::Doctor,
            RoleType::Medium,
            RoleType::SerialKiller,
        ];

        for i in 0..specials {
            if i < special_pool.len() {
                roles.push(Role::new(special_pool[i].clone()));
            } else {
                // Fallback if out of specials
                roles.push(Role::new(RoleType::Villager));
            }
        }

        // Shuffle
        let mut rng = thread_rng();
        roles.shuffle(&mut rng);

        roles
    }
}
