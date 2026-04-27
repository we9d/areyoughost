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

    pub fn unvote(&mut self, voter_id: &str) {
        self.votes.remove(voter_id);
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

#[cfg(test)]
mod tests {
    use super::VoteSystem;

    #[test]
    fn cast_change_and_unvote_are_supported() {
        let mut votes = VoteSystem::new();
        votes.cast_vote("p1".to_string(), "p2".to_string());
        let first = votes.get_results();
        assert_eq!(first.get("p2"), Some(&1));

        votes.cast_vote("p1".to_string(), "p3".to_string());
        let changed = votes.get_results();
        assert!(changed.get("p2").is_none());
        assert_eq!(changed.get("p3"), Some(&1));

        votes.unvote("p1");
        let unvoted = votes.get_results();
        assert!(unvoted.is_empty());
    }
}
