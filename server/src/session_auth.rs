//! First-message authentication shared by WebSocket and framed TCP.

use std::sync::Arc;

use crate::auth::verify_jwt;
use crate::state::manager::AppState;
use crate::ws::messages::{ClientMessage, ServerMessage};

/// Parse the first client text line/body as `auth.hello` or `session.resume` (same contract as `/ws`).
pub async fn authenticate_first_message(
    text: &str,
    state: &Arc<AppState>,
) -> Result<(String, String), ServerMessage> {
    let text = text.trim();
    let msg: ClientMessage = serde_json::from_str(text).map_err(|_| {
        ServerMessage::error(
            "UNAUTHORIZED",
            "First message must be auth.hello { token } or session.resume { resumeToken }",
        )
    })?;

    match msg.msg_type.as_str() {
        "auth.hello" => {
            let token = match msg.payload.get("token").and_then(|v| v.as_str()) {
                Some(t) => t,
                None => {
                    return Err(ServerMessage::error(
                        "INVALID_AUTH",
                        "Missing token in auth.hello payload",
                    ));
                }
            };

            match verify_jwt(token, &state.jwt_secret) {
                Ok(claims) => Ok((claims.sub, claims.username)),
                Err(e) => {
                    tracing::warn!("JWT verify failed: {e}");
                    Err(ServerMessage::error(
                        "UNAUTHORIZED",
                        "Invalid or expired token",
                    ))
                }
            }
        }
        "session.resume" => {
            let resume_token = match msg.payload.get("resumeToken").and_then(|v| v.as_str()) {
                Some(t) => t,
                None => {
                    return Err(ServerMessage::error(
                        "INVALID_RESUME",
                        "Missing resumeToken in session.resume payload",
                    ));
                }
            };

            let player_id = match state.consume_resume_token(resume_token) {
                Some(pid) => pid,
                None => {
                    return Err(ServerMessage::error(
                        "INVALID_RESUME",
                        "Invalid or expired resume token",
                    ));
                }
            };

            match state.get_username(&player_id).await {
                Some(username) => Ok((player_id, username)),
                None => Err(ServerMessage::error(
                    "INVALID_RESUME",
                    "Player not found for resume token",
                )),
            }
        }
        _ => Err(ServerMessage::error(
            "UNAUTHORIZED",
            "First message must be auth.hello { token } or session.resume { resumeToken }",
        )),
    }
}
