//! Day vote tally: one vote per alive voter; tie on top count => no execution.

use std::collections::HashMap;

pub struct VoteResolver;

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum VoteOutcome {
    /// Exactly one candidate has strictly more votes than any other.
    Execute { victim_id: String },
    /// Two or more candidates tie for the maximum vote count, or no votes cast.
    NoExecution,
}

impl VoteResolver {
    pub fn tally(votes: &HashMap<String, String>) -> VoteOutcome {
        if votes.is_empty() {
            return VoteOutcome::NoExecution;
        }
        let mut counts: HashMap<&str, u32> = HashMap::new();
        for target in votes.values() {
            *counts.entry(target.as_str()).or_insert(0) += 1;
        }
        let max = counts.values().copied().max().unwrap_or(0);
        if max == 0 {
            return VoteOutcome::NoExecution;
        }
        let leaders: Vec<_> = counts
            .iter()
            .filter(|(_, c)| **c == max)
            .map(|(id, _)| (*id).to_string())
            .collect();
        if leaders.len() == 1 {
            VoteOutcome::Execute {
                victim_id: leaders[0].clone(),
            }
        } else {
            VoteOutcome::NoExecution
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn tie_is_no_execution() {
        let mut v = HashMap::new();
        v.insert("a".into(), "x".into());
        v.insert("b".into(), "y".into());
        assert_eq!(VoteResolver::tally(&v), VoteOutcome::NoExecution);
    }

    #[test]
    fn unique_leader_executes() {
        let mut v = HashMap::new();
        v.insert("a".into(), "x".into());
        v.insert("b".into(), "x".into());
        v.insert("c".into(), "y".into());
        match VoteResolver::tally(&v) {
            VoteOutcome::Execute { victim_id } => assert_eq!(victim_id, "x"),
            _ => panic!("expected execute"),
        }
    }

    #[test]
    fn sixteen_players_unanimous_vote() {
        let mut v = HashMap::new();
        for i in 0..16 {
            v.insert(format!("p{i}"), "target".into());
        }
        match VoteResolver::tally(&v) {
            VoteOutcome::Execute { victim_id } => assert_eq!(victim_id, "target"),
            _ => panic!("expected execute"),
        }
    }
}
