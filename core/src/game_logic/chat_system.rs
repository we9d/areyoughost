use crate::models::ChatMessage;

pub struct ChatSystem {
    history: Vec<ChatMessage>,
}

impl ChatSystem {
    pub fn new() -> Self {
        Self {
            history: Vec::new(),
        }
    }

    pub fn add_message(&mut self, msg: ChatMessage) {
        // Here we could implement checks for Day/Night chat permissions
        self.history.push(msg);
    }

    pub fn get_recent(&self, limit: usize) -> Vec<ChatMessage> {
        self.history
            .iter()
            .rev()
            .take(limit)
            .rev()
            .cloned()
            .collect()
    }
}
