use crate::game_logic::roles::{Role, RoleType};
use rand::seq::SliceRandom;
use rand::SeedableRng;

pub struct RoleDistributor;

/// Roles that may only appear once in any pool (is_unique).
fn is_unique(role_type: &RoleType) -> bool {
    matches!(
        role_type,
        RoleType::SerialKiller
            | RoleType::Nemesis
            | RoleType::Fool
            | RoleType::Soldier
            | RoleType::Seer
            | RoleType::Doctor
            | RoleType::Police
            | RoleType::Monk
            | RoleType::Medium
            | RoleType::Undertaker
            | RoleType::QueenGhost
            | RoleType::AvengerGhost
            | RoleType::DeceiverGhost
            | RoleType::DarkShaman
    )
}

/// Build a role pool for the given player count using proper faction ratios.
///
/// Faction ratio guidelines:
///  4–6  players : 1 Ghost,  0 SK,  0 Nemesis, rest Villager faction
///  7–9  players : 2 Ghosts, 0–1 SK, 0 Nemesis, rest Villager faction
/// 10–12 players : 3 Ghosts, 1 SK,  0 Nemesis, rest Villager faction
/// 13–16 players : 4 Ghosts, 1 SK,  1 Nemesis, rest Villager faction
///
/// "Villager faction" slots are filled with special roles first (Seer, Doctor,
/// Soldier, Police, Monk, Medium, Undertaker, Fool) then plain Villagers.
fn build_pool(player_count: usize) -> Vec<Role> {
    if player_count == 0 {
        return vec![];
    }

    // Determine faction counts based on player count.
    let (ghost_count, sk_count, nemesis_count) = match player_count {
        4..=6   => (1, 0, 0),
        7..=9   => (2, 1, 0),
        10..=12 => (3, 1, 0),
        13..=16 => (4, 1, 1),
        // Fallback for counts outside 4–16: scale proportionally.
        _ => {
            let g = (player_count as f32 * 0.25).round() as usize;
            let s = if player_count >= 7 { 1 } else { 0 };
            let n = if player_count >= 13 { 1 } else { 0 };
            (g.max(1), s, n)
        }
    };

    let special_count = sk_count + nemesis_count;
    let villager_faction_count = player_count
        .saturating_sub(ghost_count)
        .saturating_sub(special_count);

    let mut pool: Vec<Role> = Vec::with_capacity(player_count);

    // ── Ghost faction ─────────────────────────────────────────────
    // Fill ghost slots: prefer unique ghost variants first, then plain Ghost.
    let unique_ghosts = [
        RoleType::QueenGhost,
        RoleType::AvengerGhost,
        RoleType::DeceiverGhost,
        RoleType::DarkShaman,
    ];
    for i in 0..ghost_count {
        if i < unique_ghosts.len() {
            pool.push(Role::new(unique_ghosts[i].clone()));
        } else {
            pool.push(Role::new(RoleType::Ghost));
        }
    }

    // ── Special faction ───────────────────────────────────────────
    if sk_count > 0 {
        pool.push(Role::new(RoleType::SerialKiller));
    }
    if nemesis_count > 0 {
        pool.push(Role::new(RoleType::Nemesis));
    }

    // ── Villager faction ──────────────────────────────────────────
    // Priority list of unique special villager roles.
    let special_villagers = [
        RoleType::Seer,
        RoleType::Doctor,
        RoleType::Soldier,
        RoleType::Police,
        RoleType::Monk,
        RoleType::Medium,
        RoleType::Undertaker,
        RoleType::Fool,
    ];

    let mut villager_slots = villager_faction_count;
    for role_type in &special_villagers {
        if villager_slots == 0 {
            break;
        }
        pool.push(Role::new(role_type.clone()));
        villager_slots -= 1;
    }

    // Fill remaining villager slots with plain Villagers (non-unique, stackable).
    for _ in 0..villager_slots {
        pool.push(Role::new(RoleType::Villager));
    }

    // Sanity: truncate or pad to exactly player_count.
    pool.truncate(player_count);
    while pool.len() < player_count {
        pool.push(Role::new(RoleType::Villager));
    }

    pool
}

impl RoleDistributor {
    /// Assign exactly `player_count` roles, one per player, with no duplicate
    /// `is_unique` roles.  Pass `random_seed` for reproducible shuffles.
    pub fn assign_roles(player_count: usize, random_seed: Option<u64>) -> Vec<Role> {
        if player_count == 0 {
            return vec![];
        }

        let mut pool = build_pool(player_count);

        // Shuffle the pool.
        if let Some(seed) = random_seed {
            let mut rng = rand::rngs::StdRng::seed_from_u64(seed);
            pool.shuffle(&mut rng);
        } else {
            let mut rng = rand::rngs::StdRng::from_entropy();
            pool.shuffle(&mut rng);
        }

        pool
    }
}

// ── Uniqueness invariant check (used in tests) ────────────────────────────────
pub fn has_duplicate_unique_roles(roles: &[Role]) -> bool {
    let mut seen = std::collections::HashSet::new();
    for role in roles {
        if is_unique(&role.role_type) && !seen.insert(role.role_type.clone()) {
            return true;
        }
    }
    false
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_assign_roles_returns_correct_count() {
        for n in 1..=16 {
            let roles = RoleDistributor::assign_roles(n, Some(42));
            assert_eq!(roles.len(), n, "player_count={n}");
        }
    }

    #[test]
    fn test_zero_players_returns_empty() {
        assert!(RoleDistributor::assign_roles(0, None).is_empty());
    }

    #[test]
    fn test_no_duplicate_unique_roles() {
        for n in 4..=16 {
            let roles = RoleDistributor::assign_roles(n, Some(99));
            assert!(
                !has_duplicate_unique_roles(&roles),
                "duplicate unique role found for player_count={n}"
            );
        }
    }

    #[test]
    fn test_seeded_is_reproducible() {
        let a = RoleDistributor::assign_roles(8, Some(12345));
        let b = RoleDistributor::assign_roles(8, Some(12345));
        let codes_a: Vec<_> = a.iter().map(|r| r.role_code.clone()).collect();
        let codes_b: Vec<_> = b.iter().map(|r| r.role_code.clone()).collect();
        assert_eq!(codes_a, codes_b);
    }

    #[test]
    fn test_faction_ratios_4_to_6() {
        for n in 4..=6 {
            let roles = RoleDistributor::assign_roles(n, Some(1));
            let ghosts = roles
                .iter()
                .filter(|r| matches!(r.role_type, RoleType::Ghost | RoleType::QueenGhost | RoleType::AvengerGhost | RoleType::DeceiverGhost | RoleType::DarkShaman))
                .count();
            let sk = roles.iter().filter(|r| r.role_type == RoleType::SerialKiller).count();
            assert_eq!(ghosts, 1, "n={n}");
            assert_eq!(sk, 0, "n={n}");
        }
    }

    #[test]
    fn test_faction_ratios_13_to_16() {
        for n in 13..=16 {
            let roles = RoleDistributor::assign_roles(n, Some(7));
            let ghosts = roles
                .iter()
                .filter(|r| matches!(r.role_type, RoleType::Ghost | RoleType::QueenGhost | RoleType::AvengerGhost | RoleType::DeceiverGhost | RoleType::DarkShaman))
                .count();
            let sk = roles.iter().filter(|r| r.role_type == RoleType::SerialKiller).count();
            let nemesis = roles.iter().filter(|r| r.role_type == RoleType::Nemesis).count();
            assert_eq!(ghosts, 4, "n={n}");
            assert_eq!(sk, 1, "n={n}");
            assert_eq!(nemesis, 1, "n={n}");
        }
    }
}
