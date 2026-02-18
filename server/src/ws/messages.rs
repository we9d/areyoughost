use serde::{Deserialize, Serialize};
use serde_json::Value;

#[derive(Debug, Serialize, Deserialize)]
pub struct ClientMessage {
    #[serde(rename = "type")]
    pub msg_type: String,
    pub payload: Value,
    #[serde(default)]
    pub req_id: Option<String>,
}

#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct ServerMessage {
    #[serde(rename = "type")]
    pub msg_type: String,
    pub payload: Value,
    #[serde(default)]
    pub req_id: Option<String>,
}

impl ServerMessage {
    pub fn new(msg_type: &str, payload: Value) -> Self {
        Self {
            msg_type: msg_type.to_string(),
            payload,
            req_id: None,
        }
    }

    pub fn error(code: &str, message: &str) -> Self {
        Self::new(
            "error",
            serde_json::json!({
                "code": code,
                "message": message
            }),
        )
    }
}
