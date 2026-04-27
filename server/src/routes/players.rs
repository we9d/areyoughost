use std::sync::Arc;

use axum::{
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
pub struct SearchPlayersQuery {
    pub q: Option<String>,
    pub exclude: Option<String>,
}

#[derive(sqlx::FromRow, Serialize)]
struct PlayerSearchRow {
    player_id: String,
    username: String,
}

pub async fn search_players(
    State(state): State<Arc<AppState>>,
    Query(query): Query<SearchPlayersQuery>,
) -> impl IntoResponse {
    let keyword = query.q.unwrap_or_default().trim().to_string();
    if keyword.len() < 2 {
        return (
            StatusCode::OK,
            Json(serde_json::json!({ "players": Vec::<serde_json::Value>::new() })),
        );
    }

    let exclude_uuid = query
        .exclude
        .as_deref()
        .and_then(|s| Uuid::parse_str(s).ok());

    let rows = if let Some(exclude_id) = exclude_uuid {
        sqlx::query_as::<_, PlayerSearchRow>(
            r#"
            SELECT player_id::text AS player_id, username
            FROM players
            WHERE username ILIKE $1
              AND player_id <> $2
            ORDER BY username ASC
            LIMIT 20
            "#,
        )
        .bind(format!("%{}%", keyword))
        .bind(exclude_id)
        .fetch_all(&state.db)
        .await
    } else {
        sqlx::query_as::<_, PlayerSearchRow>(
            r#"
            SELECT player_id::text AS player_id, username
            FROM players
            WHERE username ILIKE $1
            ORDER BY username ASC
            LIMIT 20
            "#,
        )
        .bind(format!("%{}%", keyword))
        .fetch_all(&state.db)
        .await
    };

    match rows {
        Ok(players) => (StatusCode::OK, Json(serde_json::json!({ "players": players }))),
        Err(e) => {
            tracing::error!("search_players DB error: {e}");
            (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(serde_json::json!({ "error": "internal error" })),
            )
        }
    }
}
