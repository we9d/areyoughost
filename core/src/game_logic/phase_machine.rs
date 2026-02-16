use serde::{Deserialize, Serialize};
use std::time::{SystemTime, UNIX_EPOCH};

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub enum PhaseType {
    Day,
    Vote,
    Night,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PhaseMachine {
    pub current_phase: PhaseType,
    pub day_number: u32,
    pub phase_end_time: u64, // Unix timestamp
}

impl PhaseMachine {
    pub fn new() -> Self {
        Self {
            current_phase: PhaseType::Day,
            day_number: 1,
            phase_end_time: Self::now() + 60, // Start with Day 60s
        }
    }

    fn now() -> u64 {
        SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_secs()
    }

    pub fn get_remaining_time(&self) -> i64 {
        let n = Self::now();
        if self.phase_end_time > n {
            (self.phase_end_time - n) as i64
        } else {
            0
        }
    }

    pub fn next_phase(&mut self) {
        match self.current_phase {
            PhaseType::Day => {
                self.current_phase = PhaseType::Vote;
                self.phase_end_time = Self::now() + 15;
            }
            PhaseType::Vote => {
                self.current_phase = PhaseType::Night;
                self.phase_end_time = Self::now() + 20;
            }
            PhaseType::Night => {
                self.current_phase = PhaseType::Day;
                self.day_number += 1;
                self.phase_end_time = Self::now() + 60;
            }
        }
    }

    /// Check if Ghosts are allowed to vote (Night phase + last 15 seconds)
    pub fn is_ghost_vote_active(&self) -> bool {
        if self.current_phase != PhaseType::Night {
            return false;
        }
        // Night is 20s total. Ghost vote starts after 5s (remaining <= 15s)
        self.get_remaining_time() <= 15
    }
}
