use crate::models::{User, Role, Skill};
use sqlx::{
    postgres::{PgPool, PgPoolOptions},
    Row,
};
use uuid::Uuid;
use chrono::{DateTime, Utc};

pub type DbResult<T> = sqlx::Result<T>;

#[derive(Clone)]
pub struct PostgresDb {
    pool: PgPool,
}

impl PostgresDb {
    pub async fn new(database_url: &str) -> DbResult<Self> {
        let pool = PgPoolOptions::new()
            .max_connections(5)
            .acquire_timeout(std::time::Duration::from_secs(10))
            .idle_timeout(std::time::Duration::from_secs(600))
            .max_lifetime(std::time::Duration::from_secs(1800))
            .connect(database_url)
            .await?;

        // Run migrations
        sqlx::migrate!("./migrations").run(&pool).await?;

        Ok(Self { pool })
    }

    /// Create a new player
    pub async fn create_player(&self, username: &str, password_hash: &str) -> DbResult<User> {
        let player_id = Uuid::new_v4();
        let now = Utc::now();

        sqlx::query(
            "INSERT INTO players (player_id, username, password_hash, created_at, updated_at) 
             VALUES ($1, $2, $3, $4, $4)",
        )
        .bind(player_id)
        .bind(username)
        .bind(password_hash)
        .bind(now)
        .execute(&self.pool)
        .await?;

        Ok(User {
            player_id,
            username: username.to_string(),
            email: None,
            password_hash: password_hash.to_string(),
            created_at: now,
            updated_at: now,
            last_login: None,
        })
    }

    /// Get player by username
    pub async fn get_player_by_username(&self, username: &str) -> DbResult<Option<User>> {
        let row = sqlx::query(
            "SELECT player_id, username, email, password_hash, created_at, updated_at, last_login 
             FROM players WHERE username = $1",
        )
        .bind(username)
        .fetch_optional(&self.pool)
        .await?;

        if let Some(row) = row {
            Ok(Some(User {
                player_id: row.try_get("player_id")?,
                username: row.try_get("username")?,
                email: row.try_get("email")?,
                password_hash: row.try_get("password_hash")?,
                created_at: row.try_get("created_at")?,
                updated_at: row.try_get("updated_at")?,
                last_login: row.try_get("last_login")?,
            }))
        } else {
            Ok(None)
        }
    }

    /// Update last login
    pub async fn update_last_login(&self, player_id: Uuid) -> DbResult<()> {
        let now = Utc::now();
        sqlx::query("UPDATE players SET last_login = $1 WHERE player_id = $2")
            .bind(now)
            .bind(player_id)
            .execute(&self.pool)
            .await?;
        Ok(())
    }

    /// Update username
    pub async fn update_username(&self, player_id: Uuid, new_username: &str) -> DbResult<()> {
        let now = Utc::now();
        sqlx::query("UPDATE players SET username = $1, updated_at = $2 WHERE player_id = $3")
            .bind(new_username)
            .bind(now)
            .bind(player_id)
            .execute(&self.pool)
            .await?;
        Ok(())
    }

    /// Create a new game
    pub async fn create_game(&self, room_id: Uuid, room_type: &str, player_count: i32) -> DbResult<Uuid> {
        let game_id = Uuid::new_v4();
        let now = Utc::now();
        let seed: i64 = rand::random();

        sqlx::query(
            "INSERT INTO games (game_id, room_id, room_type, player_count, started_at, game_status, random_seed)
             VALUES ($1, $2, $3, $4, $5, 'ONGOING', $6)",
        )
        .bind(game_id)
        .bind(room_id)
        .bind(room_type)
        .bind(player_count)
        .bind(now)
        .bind(seed)
        .execute(&self.pool)
        .await?;

        // Update room status
        sqlx::query("UPDATE rooms SET room_status = 'PLAYING', updated_at = $1 WHERE room_id = $2")
            .bind(now)
            .bind(room_id)
            .execute(&self.pool)
            .await?;

        Ok(game_id)
    }

    /// Add participant to game
    pub async fn add_game_participant(
        &self,
        game_id: Uuid,
        player_id: Uuid,
        role_id: i32,
        seat_number: i32,
    ) -> DbResult<()> {
        let game_participant_id = Uuid::new_v4();
        let now = Utc::now();

        sqlx::query(
            "INSERT INTO game_participants 
             (game_participant_id, game_id, player_id, role_id, is_alive, seat_number, joined_at)
             VALUES ($1, $2, $3, $4, true, $5, $6)",
        )
        .bind(game_participant_id)
        .bind(game_id)
        .bind(player_id)
        .bind(role_id)
        .bind(seat_number)
        .bind(now)
        .execute(&self.pool)
        .await?;

        Ok(())
    }

    /// End game
    pub async fn end_game(&self, game_id: Uuid, winner_faction: &str) -> DbResult<()> {
        let now = Utc::now();

        sqlx::query(
            "UPDATE games SET ended_at = $1, game_status = 'FINISHED', winner_faction = $2 
             WHERE game_id = $3",
        )
        .bind(now)
        .bind(winner_faction)
        .bind(game_id)
        .execute(&self.pool)
        .await?;

        Ok(())
    }

    /// Save chat message
    pub async fn save_chat_message(
        &self,
        game_id: Uuid,
        phase_id: Option<Uuid>,
        sender_id: Option<Uuid>,
        chat_scope: &str,
        message: &str,
    ) -> DbResult<()> {
        let message_id = Uuid::new_v4();
        let now = Utc::now();

        sqlx::query(
            "INSERT INTO chat_messages 
             (message_id, game_id, phase_id, sender_id, chat_scope, message_text, created_at)
             VALUES ($1, $2, $3, $4, $5, $6, $7)",
        )
        .bind(message_id)
        .bind(game_id)
        .bind(phase_id)
        .bind(sender_id)
        .bind(chat_scope)
        .bind(message)
        .bind(now)
        .execute(&self.pool)
        .await?;

        Ok(())
    }
}
