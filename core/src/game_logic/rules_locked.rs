//! Single source of truth for ambiguous rules from the product spec.
//! All engine / server runtime code should import from here.

/// Ghost faction wins when this comparison holds against non-ghost living count.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum GhostWinComparator {
    /// Standard werewolf-style: ghosts win when `ghosts_alive >= non_ghosts_alive`.
    GhostsGteNonGhosts,
}

impl GhostWinComparator {
    pub const LOCKED: Self = Self::GhostsGteNonGhosts;

    #[inline]
    pub fn ghost_wins(self, ghosts_alive: u32, non_ghosts_alive: u32) -> bool {
        match self {
            Self::GhostsGteNonGhosts => ghosts_alive >= non_ghosts_alive,
        }
    }
}

/// When Dark Shaman (G14) protects a ghost kill target and multiple kill sources hit the same target.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum DarkShamanProtectPolicy {
    /// The protect blocks exactly one kill instance; remaining kills still apply in batch order.
    BlockSingleKillSource,
}

impl DarkShamanProtectPolicy {
    pub const LOCKED: Self = Self::BlockSingleKillSource;
}

/// Who may be revived by V7-style revive after night resolution.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum ReviveConstraints {
    /// Only players who died during the same night batch, before finalize deaths, are eligible.
    SameNightDeathsOnly,
}

impl ReviveConstraints {
    pub const LOCKED: Self = Self::SameNightDeathsOnly;
}

/// Chat: "dead" means `is_alive == false` — ghost faction night chat is for **living** ghost-aligned only.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum GhostNightChatEligibility {
    LivingGhostAlignedOnly,
}

impl GhostNightChatEligibility {
    pub const LOCKED: Self = Self::LivingGhostAlignedOnly;
}

/// Win evaluation priority (first match wins).
#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord)]
pub enum WinPriority {
    KarmaSolo = 0,
    SerialKillerSolo = 1,
    VillagerFaction = 2,
    GhostFaction = 3,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn ghost_win_uses_gte() {
        assert!(GhostWinComparator::LOCKED.ghost_wins(3, 3));
        assert!(!GhostWinComparator::LOCKED.ghost_wins(2, 3));
        assert!(GhostWinComparator::LOCKED.ghost_wins(4, 2));
    }
}
