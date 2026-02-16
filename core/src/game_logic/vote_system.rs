use crate::models::Vote;
use std::collections::HashMap;

#[derive(Debug, Clone)]
pub struct VoteSystem {
    votes: HashMap<String, String>, // voter_id -> target_id
}

impl VoteSystem {
    pub fn new() -> Self {
        Self {
            votes: HashMap::new(),
        }
    }

    pub fn cast_vote(&mut self, voter_id: String, target_id: String) {
        self.votes.insert(voter_id, target_id);
    }

    pub fn get_results(&self) -> HashMap<String, i32> {
        let mut counts = HashMap::new();
        for target in self.votes.values() {
            *counts.entry(target.clone()).or_insert(0) += 1;
        }
        counts
    }

    pub fn reset(&mut self) {
        self.votes.clear();
    }
}
