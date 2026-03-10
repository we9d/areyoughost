//! # Auth Routes
//!
//! POST /auth/register  — สร้าง account ใหม่
//! POST /auth/login     — login และรับ JWT access token

use std::sync::Arc;

use axum::{extract::State, http::StatusCode, response::IntoResponse, Json};
use serde::Deserialize;
use uuid::Uuid;

use crate::{
    auth::{hash_password, sign_jwt, verify_password},
    state::manager::AppState,
};

// ─── DB row types for query_as ────────────────────────────────────

#[derive(sqlx::FromRow)]
struct PlayerRow {
    player_id: String,
    username: String,
}

#[derive(sqlx::FromRow)]
struct PlayerAuthRow {
    player_id: String,
    username: String,
    password_hash: String,
}

// ─── Request / Response DTOs ─────────────────────────────────────

#[derive(Deserialize)]
pub struct RegisterRequest {
    pub username: String,
    pub email: String,
    pub password: String,
}

#[derive(Deserialize)]
pub struct LoginRequest {
    pub username: String,
    pub password: String,
}

// ─── Handlers ────────────────────────────────────────────────────

/// POST /auth/register
pub async fn register(
    State(state): State<Arc<AppState>>,
    Json(body): Json<RegisterRequest>,
) -> impl IntoResponse {
    let uname = body.username.trim().to_string();
    let email = body.email.trim().to_string();

    if uname.len() < 3 || uname.len() > 20 {
        return (
            StatusCode::UNPROCESSABLE_ENTITY,
            Json(serde_json::json!({ "error": "username must be 3-20 characters" })),
        );
    }
    if email.is_empty() || !email.contains('@') {
        return (
            StatusCode::UNPROCESSABLE_ENTITY,
            Json(serde_json::json!({ "error": "invalid email format" })),
        );
    }
    if body.password.len() < 6 {
        return (
            StatusCode::UNPROCESSABLE_ENTITY,
            Json(serde_json::json!({ "error": "password must be at least 6 characters" })),
        );
    }

    let password_hash = match hash_password(&body.password) {
        Ok(h) => h,
        Err(e) => {
            tracing::error!("hash_password error: {e}");
            return (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(serde_json::json!({ "error": "internal error" })),
            );
        }
    };

    let new_player_id = Uuid::new_v4().to_string();

    let result = sqlx::query_as::<_, PlayerRow>(
        "INSERT INTO players (player_id, username, email, password_hash, created_at, updated_at) VALUES ($1, $2, $3, $4, now(), now()) RETURNING player_id, username",
    )
    .bind(&new_player_id)
    .bind(&uname)
    .bind(&email)
    .bind(&password_hash)
    .fetch_one(&state.db)
    .await;

    match result {
        Ok(row) => {
            tracing::info!("Registered new player: {}", row.username);
            (
                StatusCode::CREATED,
                Json(serde_json::json!({
                    "player": {
                        "id": row.player_id,
                        "username": row.username,
                        "email": email,
                    }
                })),
            )
        }
        Err(sqlx::Error::Database(e)) if e.constraint() == Some("players_username_key") => (
            StatusCode::CONFLICT,
            Json(serde_json::json!({ "error": "username already taken" })),
        ),
        Err(sqlx::Error::Database(e)) if e.constraint() == Some("players_email_key") => (
            StatusCode::CONFLICT,
            Json(serde_json::json!({ "error": "email already registered" })),
        ),
        Err(e) => {
            tracing::error!("register DB error: {e}");
            (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(serde_json::json!({ "error": format!("internal error: {}", e) })),
            )
        }
    }
}

/// POST /auth/login
pub async fn login(
    State(state): State<Arc<AppState>>,
    Json(body): Json<LoginRequest>,
) -> impl IntoResponse {
    let uname = body.username.trim().to_string();

    let row = sqlx::query_as::<_, PlayerAuthRow>(
        "SELECT player_id, username, password_hash FROM players WHERE username = $1",
    )
    .bind(&uname)
    .fetch_optional(&state.db)
    .await;

    let row = match row {
        Ok(Some(r)) => r,
        Ok(None) => {
            return (
                StatusCode::UNAUTHORIZED,
                Json(serde_json::json!({ "error": "invalid username or password" })),
            )
        }
        Err(e) => {
            tracing::error!("login DB error: {e}");
            return (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(serde_json::json!({ "error": "internal error" })),
            );
        }
    };

    let ok = match verify_password(&body.password, &row.password_hash) {
        Ok(v) => v,
        Err(e) => {
            tracing::error!("verify_password error: {e}");
            return (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(serde_json::json!({ "error": format!("internal error: {}", e) })),
            );
        }
    };

    if !ok {
        return (
            StatusCode::UNAUTHORIZED,
            Json(serde_json::json!({ "error": "invalid username or password" })),
        );
    }

    let player_uuid = Uuid::parse_str(&row.player_id).unwrap_or_default();
    let token = match sign_jwt(player_uuid, &row.username, &state.jwt_secret) {
        Ok(t) => t,
        Err(e) => {
            tracing::error!("sign_jwt error: {e}");
            return (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(serde_json::json!({ "error": "internal error" })),
            );
        }
    };

    tracing::info!("Player {} logged in", row.username);
    (
        StatusCode::OK,
        Json(serde_json::json!({
            "accessToken": token,
            "player": {
                "id": row.player_id,
                "username": row.username,
            }
        })),
    )
}
