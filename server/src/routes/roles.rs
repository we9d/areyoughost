use std::sync::Arc;

use axum::{extract::State, http::StatusCode, response::IntoResponse, Json};
use serde::Serialize;

use crate::state::manager::AppState;

#[derive(sqlx::FromRow, Serialize)]
struct RoleRow {
    role_code: String,
    role_name: String,
    faction: String,
    description: Option<String>,
    skill_1: Option<String>,
    skill_2: Option<String>,
}

#[derive(sqlx::FromRow)]
struct RoleRowLegacy {
    role_code: String,
    role_name: String,
    faction: String,
    description: Option<String>,
}

pub async fn list_roles(State(state): State<Arc<AppState>>) -> impl IntoResponse {
    let rows = sqlx::query_as::<_, RoleRow>(
        r#"
        SELECT role_code, role_name, faction, description, skill_1, skill_2
        FROM roles
        ORDER BY role_id ASC
        "#,
    )
    .fetch_all(&state.db)
    .await;

    match rows {
        Ok(roles) => (StatusCode::OK, Json(serde_json::json!({ "roles": roles }))),
        Err(e) => {
            let missing_skill_columns = e
                .to_string()
                .contains("column \"skill_1\" does not exist");

            if missing_skill_columns {
                tracing::warn!(
                    "roles table missing skill columns; serving fallback response without skill_1/skill_2"
                );

                let legacy_rows = sqlx::query_as::<_, RoleRowLegacy>(
                    r#"
                    SELECT role_code, role_name, faction, description
                    FROM roles
                    ORDER BY role_id ASC
                    "#,
                )
                .fetch_all(&state.db)
                .await;

                return match legacy_rows {
                    Ok(rows) => {
                        let roles: Vec<RoleRow> = rows
                            .into_iter()
                            .map(|r| RoleRow {
                                role_code: r.role_code,
                                role_name: r.role_name,
                                faction: r.faction,
                                description: r.description,
                                skill_1: None,
                                skill_2: None,
                            })
                            .collect();
                        (StatusCode::OK, Json(serde_json::json!({ "roles": roles })))
                    }
                    Err(fallback_err) => {
                        tracing::error!("list_roles fallback DB error: {fallback_err}");
                        (
                            StatusCode::INTERNAL_SERVER_ERROR,
                            Json(serde_json::json!({ "error": "internal error" })),
                        )
                    }
                };
            }

            tracing::error!("list_roles DB error: {e}");
            (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(serde_json::json!({ "error": "internal error" })),
            )
        }
    }
}

