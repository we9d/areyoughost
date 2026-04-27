//! # Game Master (GM) specification — Are You Ghost? / Werewolf-style
//!
//! This module is the **authoritative checklist** for deterministic resolution.
//! Runtime code should follow these orders; do not leak secret info (roles,
//! night targets, private skills) in public channels — only outcomes below.
//!
//! ## Win conditions (check after night resolve, after vote, after specials)
//! - **Villagers**: all ghost-faction eliminated.
//! - **Ghosts**: `ghosts_alive >= villagers_alive` (non-ghosts); see [`crate::game_logic::rules_locked::GhostWinComparator`].
//! - **Serial killer (S15)**: wins when alone (solo neutral).
//! - **เจ้ากรรมนายเวร (S16)**: instant win when secret **nemesis target** dies — requires hidden state not yet on `GameParticipant`.
//!
//! ## Night pipeline (fixed order — GM must not reorder)
//! Information skills (Seer, Detective, Aura) **do not** change kill math; they
//! only produce **private** results to the actor. Resolution math runs after
//! all intents are collected, in priority: kill intents → protections →
//! specials → transforms → finalize deaths → witch revive.
pub const NIGHT_RESOLUTION_STEPS: &[&str] = &[
    "STEP_1_GHOST_KILL",      // G10–G14 team: one merged kill target
    "STEP_2_SERIAL_KILLER",   // S15 separate kill
    "STEP_3_SEER",            // V2 — private
    "STEP_4_DETECTIVE",       // V5 — private
    "STEP_5_AURA",            // V6 — private
    "STEP_6_DOCTOR",          // V3 protect
    "STEP_7_BODYGUARD",       // V4 redirect / die instead
    "STEP_8_DARK_SHAMAN",     // G14 protect ghost OR curse
    "STEP_9_WITCH",           // V7 revive / poison
    "STEP_10_RESOLVE",        // merge kills, apply protections, V9 transform, finalize, revive
];

use serde::{Deserialize, Serialize};

/// **Public** night outcome (no roles / no night targets). Safe to broadcast as summary IDs.
#[derive(Clone, Debug, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct NightGmReport {
    pub deaths: Vec<String>,
    /// Player IDs that **survived a kill** because of protection this night.
    pub protected: Vec<String>,
    pub cursed: Vec<String>,
    pub transformed: Vec<String>,
    pub revived: Vec<String>,
    /// Internal / moderator log lines (still must not echo secret choices).
    pub logs: Vec<String>,
}

/// **Public** day outcome after vote (and G12 chain if applicable).
#[derive(Clone, Debug, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct DayGmReport {
    pub executed: Option<String>,
    pub extra_death: Option<String>,
}
