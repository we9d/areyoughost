use std::collections::HashMap;
use crate::game_logic::roles::{Faction, RoleType};
use crate::models::GameParticipant;
use uuid::Uuid;

/// Result returned by `resolve_vote()`.
#[derive(Debug, Clone)]
pub struct VoteResult {
    /// The player_id of the eliminated player, or `None` on a tie.
    pub eliminated: Option<Uuid>,
    /// Additional deaths caused by AvengerGhost drag-to-death.
    pub extra_deaths: Vec<Uuid>,
    /// A special faction win triggered by this vote (Fool or Nemesis).
    pub special_win: Option<Faction>,
}

#[derive(Debug, Clone)]
pub struct VoteSystem {
    votes: HashMap<Uuid, Uuid>, // voter_id -> target_id
}

impl VoteSystem {
    pub fn new() -> Self {
        Self {
            votes: HashMap::new(),
        }
    }

    pub fn cast_vote(&mut self, voter_id: Uuid, target_id: Uuid) {
        self.votes.insert(voter_id, target_id);
    }

    pub fn get_results(&self) -> HashMap<Uuid, i32> {
        let mut counts = HashMap::new();
        for target in self.votes.values() {
            *counts.entry(*target).or_insert(0) += 1;
        }
        counts
    }

    /// Resolves the vote, applies deaths to `participants`, and returns a `VoteResult`.
    pub fn resolve_vote(
        &mut self,
        participants: &mut HashMap<Uuid, crate::game_logic::state::ParticipantInfo>,
    ) -> VoteResult {
        let counts = self.get_results();
        self.reset();

        // Find the maximum vote count.
        let max_votes = match counts.values().copied().max() {
            Some(v) => v,
            None => {
                return VoteResult {
                    eliminated: None,
                    extra_deaths: vec![],
                    special_win: None,
                };
            }
        };

        // Collect all candidates that share the maximum.
        let top: Vec<Uuid> = counts
            .iter()
            .filter(|(_, &v)| v == max_votes)
            .map(|(id, _)| *id)
            .collect();

        // Tie → no elimination.
        if top.len() != 1 {
            return VoteResult {
                eliminated: None,
                extra_deaths: vec![],
                special_win: None,
            };
        }

        let eliminated_id = top.into_iter().next().unwrap();

        // Mark the eliminated player as dead.
        let extra_deaths: Vec<Uuid> = vec![];
        let special_win: Option<Faction> = None;

        if let Some(p) = participants.get_mut(&eliminated_id) {
            if p.model.is_alive {
                p.model.is_alive = false;
            }
            // In the 24-table alignment, role-specific complex logic like Nemesis hidden targets 
            // will need ParticipantState. For now, simplifying to reconcile types.
        }

        VoteResult {
            eliminated: Some(eliminated_id),
            extra_deaths,
            special_win,
        }
    }

    pub fn reset(&mut self) {
        self.votes.clear();
    }
}
