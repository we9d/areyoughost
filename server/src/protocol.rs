//! JSON protocol helpers (TCP + WS aligned): `type`, optional `request_id`, body as `data` or `payload`.

use serde::{Deserialize, Serialize};
use serde_json::Value;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Envelope {
    #[serde(rename = "type")]
    pub msg_type: String,
    #[serde(default)]
    pub request_id: Option<String>,
    #[serde(default)]
    pub data: Option<Value>,
    #[serde(default)]
    pub payload: Option<Value>,
}

impl Envelope {
    pub fn body(&self) -> Value {
        self.data
            .clone()
            .or_else(|| self.payload.clone())
            .unwrap_or(Value::Null)
    }
}

/// Stable error codes for clients (do not rename without versioning).
pub mod error_code {
    pub const INVALID_MESSAGE: &str = "INVALID_MESSAGE";
    pub const UNAUTHORIZED: &str = "UNAUTHORIZED";
    pub const INVALID_RESUME: &str = "INVALID_RESUME";
    pub const DUPLICATE_REQUEST: &str = "DUPLICATE_REQUEST";
    pub const WRONG_PHASE: &str = "WRONG_PHASE";
    pub const NOT_ALIVE: &str = "NOT_ALIVE";
    pub const FRAME_TOO_LARGE: &str = "FRAME_TOO_LARGE";
}

pub fn error_envelope(code: &str, message: &str) -> Value {
    serde_json::json!({
        "type": "error",
        "payload": { "code": code, "message": message },
        "data": { "code": code, "message": message },
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn envelope_prefers_data_then_payload() {
        let e: Envelope =
            serde_json::from_str(r#"{"type":"ping","request_id":"r1","data":{"k":1}}"#).unwrap();
        assert_eq!(e.msg_type, "ping");
        assert_eq!(e.request_id.as_deref(), Some("r1"));
        assert_eq!(e.body()["k"], 1);
        let e2: Envelope =
            serde_json::from_str(r#"{"type":"p2","payload":{"x":2}}"#).unwrap();
        assert_eq!(e2.body()["x"], 2);
    }
}
