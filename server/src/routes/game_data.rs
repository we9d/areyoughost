use axum::{extract::State, Json};
use serde::Serialize;
use std::sync::Arc;
use crate::state::manager::{AppState, CachedRole, CachedSkill};

#[derive(Serialize)]
pub struct GameDataResponse {
    pub roles: Vec<CachedRole>,
    pub skills: Vec<CachedSkill>,
}

pub async fn get_game_data(
    State(state): State<Arc<AppState>>,
) -> Json<GameDataResponse> {
    Json(GameDataResponse {
        roles: state.cached_roles.clone(),
        skills: state.cached_skills.clone(),
    })
}
