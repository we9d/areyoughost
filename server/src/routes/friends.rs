use std::sync::Arc;

use axum::{
    extract::ws::Message,
    extract::{Query, State},
    http::StatusCode,
    response::IntoResponse,
    Json,
};
use serde::Deserialize;
use serde::Serialize;
use uuid::Uuid;

use crate::state::manager::AppState;

#[derive(Deserialize)]
pub struct FriendsOverviewQuery {
    pub user_id: String,
}

#[derive(Deserialize)]
pub struct SendFriendRequestBody {
    pub from_user_id: String,
    pub to_user_id: String,
}

#[derive(Deserialize)]
pub struct RespondFriendRequestBody {
    pub friendship_id: String,
    pub user_id: String,
    pub action: String,
}

#[derive(sqlx::FromRow)]
struct IncomingRow {
    friendship_id: Uuid,
    player_id: Uuid,
    username: String,
}

#[derive(sqlx::FromRow)]
struct FriendRow {
    player_id: Uuid,
    username: String,
}

#[derive(sqlx::FromRow)]
struct OutgoingRow {
    player_id: Uuid,
    username: String,
}

#[derive(sqlx::FromRow)]
struct UsernameRow {
    username: String,
}

#[derive(sqlx::FromRow)]
struct RequestOwnerRow {
    requester_id: Uuid,
}

#[derive(Serialize)]
struct IncomingDto {
    friendship_id: String,
    player_id: String,
    username: String,
}

#[derive(Serialize)]
struct FriendDto {
    player_id: String,
    username: String,
    is_online: bool,
}

#[derive(Serialize)]
struct OutgoingDto {
    player_id: String,
    username: String,
}

pub async fn overview(
    State(state): State<Arc<AppState>>,
    Query(query): Query<FriendsOverviewQuery>,
) -> impl IntoResponse {
    let user_id = match Uuid::parse_str(query.user_id.trim()) {
        Ok(v) => v,
        Err(_) => {
            return (
                StatusCode::BAD_REQUEST,
                Json(serde_json::json!({ "error": "invalid user_id format" })),
            )
        }
    };

    let incoming_rows = sqlx::query_as::<_, IncomingRow>(
        r#"
        SELECT f.friendship_id, p.player_id, p.username
        FROM friendships f
        JOIN players p ON p.player_id = f.requester_id
        WHERE f.addressee_id = $1
          AND f.status = 'PENDING'
        ORDER BY f.created_at DESC
        "#,
    )
    .bind(user_id)
    .fetch_all(&state.db)
    .await;

    let friends_rows = sqlx::query_as::<_, FriendRow>(
        r#"
        SELECT
          CASE WHEN f.requester_id = $1 THEN p2.player_id ELSE p1.player_id END AS player_id,
          CASE WHEN f.requester_id = $1 THEN p2.username  ELSE p1.username  END AS username
        FROM friendships f
        JOIN players p1 ON p1.player_id = f.requester_id
        JOIN players p2 ON p2.player_id = f.addressee_id
        WHERE (f.requester_id = $1 OR f.addressee_id = $1)
          AND f.status = 'ACCEPTED'
        ORDER BY username ASC
        "#,
    )
    .bind(user_id)
    .fetch_all(&state.db)
    .await;

    let outgoing_rows = sqlx::query_as::<_, OutgoingRow>(
        r#"
        SELECT p.player_id, p.username
        FROM friendships f
        JOIN players p ON p.player_id = f.addressee_id
        WHERE f.requester_id = $1
          AND f.status = 'PENDING'
        ORDER BY f.created_at DESC
        "#,
    )
    .bind(user_id)
    .fetch_all(&state.db)
    .await;

    match (incoming_rows, friends_rows, outgoing_rows) {
        (Ok(incoming), Ok(friends), Ok(outgoing)) => {
            let incoming_dto: Vec<IncomingDto> = incoming
                .into_iter()
                .map(|r| IncomingDto {
                    friendship_id: r.friendship_id.to_string(),
                    player_id: r.player_id.to_string(),
                    username: r.username,
                })
                .collect();

            let friends_dto: Vec<FriendDto> = friends
                .into_iter()
                .map(|r| {
                    let pid = r.player_id.to_string();
                    FriendDto {
                        player_id: pid.clone(),
                        username: r.username,
                        is_online: state.connections.contains_key(&pid),
                    }
                })
                .collect();

            let outgoing_dto: Vec<OutgoingDto> = outgoing
                .into_iter()
                .map(|r| OutgoingDto {
                    player_id: r.player_id.to_string(),
                    username: r.username,
                })
                .collect();

            (
                StatusCode::OK,
                Json(serde_json::json!({
                    "incoming_requests": incoming_dto,
                    "friends": friends_dto,
                    "outgoing_requests": outgoing_dto,
                })),
            )
        }
        _ => (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(serde_json::json!({ "error": "internal error" })),
        ),
    }
}

pub async fn send_request(
    State(state): State<Arc<AppState>>,
    Json(body): Json<SendFriendRequestBody>,
) -> impl IntoResponse {
    let from_id = match Uuid::parse_str(body.from_user_id.trim()) {
        Ok(v) => v,
        Err(_) => {
            return (
                StatusCode::BAD_REQUEST,
                Json(serde_json::json!({ "error": "invalid from_user_id format" })),
            )
        }
    };
    let to_id = match Uuid::parse_str(body.to_user_id.trim()) {
        Ok(v) => v,
        Err(_) => {
            return (
                StatusCode::BAD_REQUEST,
                Json(serde_json::json!({ "error": "invalid to_user_id format" })),
            )
        }
    };
    if from_id == to_id {
        return (
            StatusCode::UNPROCESSABLE_ENTITY,
            Json(serde_json::json!({ "error": "cannot add yourself" })),
        );
    }

    let existing = sqlx::query_scalar::<_, i64>(
        r#"
        SELECT COUNT(1)
        FROM friendships
        WHERE (requester_id = $1 AND addressee_id = $2)
           OR (requester_id = $2 AND addressee_id = $1)
        "#,
    )
    .bind(from_id)
    .bind(to_id)
    .fetch_one(&state.db)
    .await;

    let existing_count = match existing {
        Ok(v) => v,
        Err(_) => {
            return (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(serde_json::json!({ "error": "internal error" })),
            )
        }
    };

    if existing_count > 0 {
        return (
            StatusCode::CONFLICT,
            Json(serde_json::json!({ "error": "friendship already exists or pending" })),
        );
    }

    let inserted = sqlx::query(
        r#"
        INSERT INTO friendships (requester_id, addressee_id, status)
        VALUES ($1, $2, 'PENDING')
        "#,
    )
    .bind(from_id)
    .bind(to_id)
    .execute(&state.db)
    .await;

    match inserted {
        Ok(_) => {
            // Push realtime event to target if online.
            let from_name = sqlx::query_as::<_, UsernameRow>(
                "SELECT username FROM players WHERE player_id = $1",
            )
            .bind(from_id)
            .fetch_optional(&state.db)
            .await
            .ok()
            .flatten()
            .map(|r| r.username)
            .unwrap_or_else(|| "เพื่อน".to_string());

            let to_key = to_id.to_string();
            if let Some(target_tx) = state.connections.get(&to_key) {
                let event = serde_json::json!({
                    "type": "friend.request.received",
                    "payload": {
                        "fromUserId": from_id.to_string(),
                        "fromUsername": from_name,
                    }
                });
                let _ = target_tx.send(Message::Text(event.to_string()));
            }

            (StatusCode::OK, Json(serde_json::json!({ "success": true })))
        }
        Err(_) => (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(serde_json::json!({ "error": "internal error" })),
        ),
    }
}

pub async fn respond_request(
    State(state): State<Arc<AppState>>,
    Json(body): Json<RespondFriendRequestBody>,
) -> impl IntoResponse {
    let friendship_id = match Uuid::parse_str(body.friendship_id.trim()) {
        Ok(v) => v,
        Err(_) => {
            return (
                StatusCode::BAD_REQUEST,
                Json(serde_json::json!({ "error": "invalid friendship_id format" })),
            )
        }
    };
    let user_id = match Uuid::parse_str(body.user_id.trim()) {
        Ok(v) => v,
        Err(_) => {
            return (
                StatusCode::BAD_REQUEST,
                Json(serde_json::json!({ "error": "invalid user_id format" })),
            )
        }
    };

    let next_status = match body.action.trim().to_ascii_uppercase().as_str() {
        "ACCEPT" => "ACCEPTED",
        "REJECT" => "DECLINED",
        _ => {
            return (
                StatusCode::UNPROCESSABLE_ENTITY,
                Json(serde_json::json!({ "error": "action must be ACCEPT or REJECT" })),
            )
        }
    };

    let owner = sqlx::query_as::<_, RequestOwnerRow>(
        "SELECT requester_id FROM friendships WHERE friendship_id = $1",
    )
    .bind(friendship_id)
    .fetch_optional(&state.db)
    .await
    .ok()
    .flatten();

    let updated = sqlx::query(
        r#"
        UPDATE friendships
        SET status = $1, updated_at = now()
        WHERE friendship_id = $2
          AND addressee_id = $3
          AND status = 'PENDING'
        "#,
    )
    .bind(next_status)
    .bind(friendship_id)
    .bind(user_id)
    .execute(&state.db)
    .await;

    match updated {
        Ok(result) if result.rows_affected() == 1 => {
            // Notify requester if online.
            if let Some(owner_row) = owner {
                let requester_key = owner_row.requester_id.to_string();
                if let Some(requester_tx) = state.connections.get(&requester_key) {
                    let event = serde_json::json!({
                        "type": "friend.request.responded",
                        "payload": {
                            "byUserId": user_id.to_string(),
                            "status": next_status,
                        }
                    });
                    let _ = requester_tx.send(Message::Text(event.to_string()));
                }
            }
            (StatusCode::OK, Json(serde_json::json!({ "success": true })))
        }
        Ok(_) => (
            StatusCode::NOT_FOUND,
            Json(serde_json::json!({ "error": "pending request not found" })),
        ),
        Err(_) => (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(serde_json::json!({ "error": "internal error" })),
        ),
    }
}
