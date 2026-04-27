//! Append-only persistence helpers (Supabase / Postgres).

use serde_json::Value;
use sqlx::PgPool;
use uuid::Uuid;

pub async fn insert_match_event(
    pool: &PgPool,
    room_id: Option<Uuid>,
    game_id: Option<Uuid>,
    event_type: &str,
    payload: Value,
) -> Result<(), sqlx::Error> {
    sqlx::query(
        r#"INSERT INTO match_events (event_id, room_id, game_id, event_type, payload)
           VALUES ($1, $2, $3, $4, $5)"#,
    )
    .bind(Uuid::new_v4())
    .bind(room_id)
    .bind(game_id)
    .bind(event_type)
    .bind(payload)
    .execute(pool)
    .await?;
    Ok(())
}
