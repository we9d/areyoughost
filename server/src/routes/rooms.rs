use std::sync::Arc;

use axum::{extract::State, Json};

use crate::state::manager::AppState;

pub async fn list_public_rooms(State(state): State<Arc<AppState>>) -> Json<serde_json::Value> {
    Json(state.list_public_rooms())
}
