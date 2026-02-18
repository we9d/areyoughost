use crate::models::User;
use sqlx::{
    postgres::{PgPool, PgPoolOptions},
    Row,
};
use uuid::Uuid;

pub type DbResult<T> = sqlx::Result<T>;

#[derive(Clone)]
pub struct PostgresDb {
    pool: PgPool,
}

impl PostgresDb {
    pub async fn new(database_url: &str) -> DbResult<Self> {
        let pool = PgPoolOptions::new()
            .max_connections(20)
            .connect(database_url)
            .await?;

        // Run migrations
        sqlx::migrate!("./migrations").run(&pool).await?;

        Ok(Self { pool })
    }

    /// Create a new player
    pub async fn create_player(&self, username: &str, password_hash: &str) -> DbResult<User> {
        let user_id = Uuid::new_v4().to_string();
        let now = chrono::Utc::now().to_rfc3339();

        sqlx::query(
            "INSERT INTO players (player_id, username, password_hash, created_at, updated_at) 
             VALUES ($1, $2, $3, $4, $4)",
        )
        .bind(&user_id)
        .bind(username)
        .bind(password_hash)
        .bind(&now)
        .execute(&self.pool)
        .await?;

        Ok(User {
            user_id,
            username: username.to_string(),
            password_hash: password_hash.to_string(),
            created_at: now,
            last_login: None,
        })
    }

    /// Get player by username
    pub async fn get_player_by_username(&self, username: &str) -> DbResult<Option<User>> {
        let row = sqlx::query(
            "SELECT player_id, username, password_hash, created_at, last_login 
             FROM players WHERE username = $1",
        )
        .bind(username)
        .fetch_optional(&self.pool)
        .await?;

        if let Some(row) = row {
            Ok(Some(User {
                user_id: row.try_get("player_id")?,
                username: row.try_get("username")?,
                password_hash: row.try_get("password_hash")?,
                created_at: row.try_get("created_at")?,
                last_login: row.try_get("last_login")?,
            }))
        } else {
            Ok(None)
        }
    }

    /// Update last login
    pub async fn update_last_login(&self, user_id: &str) -> DbResult<()> {
        let now = chrono::Utc::now().to_rfc3339();
        sqlx::query("UPDATE players SET last_login = $1 WHERE player_id = $2")
            .bind(&now)
            .bind(user_id)
            .execute(&self.pool)
            .await?;
        Ok(())
    }

    /// Update username
    pub async fn update_username(&self, user_id: &str, new_username: &str) -> DbResult<()> {
        let now = chrono::Utc::now().to_rfc3339();
        sqlx::query("UPDATE players SET username = $1, updated_at = $2 WHERE player_id = $3")
            .bind(new_username)
            .bind(&now)
            .bind(user_id)
            .execute(&self.pool)
            .await?;
        Ok(())
    }

    /// Create a new game
    pub async fn create_game(&self, room_id: &str) -> DbResult<String> {
        let game_id = Uuid::new_v4().to_string();
        let now = chrono::Utc::now().to_rfc3339();
        // Use a random seed (can be passed in, or generated here)
        let seed: i64 = rand::random();

        sqlx::query(
            "INSERT INTO games (game_id, room_id, started_at, game_status, random_seed)
             VALUES ($1, $2, $3, 'ONGOING', $4)",
        )
        .bind(&game_id)
        .bind(room_id)
        .bind(&now)
        .bind(seed)
        .execute(&self.pool)
        .await?;

        // Update room status
        sqlx::query("UPDATE rooms SET room_status = 'PLAYING', updated_at = $1 WHERE room_id = $2")
            .bind(&now)
            .bind(room_id)
            .execute(&self.pool)
            .await?;

        Ok(game_id)
    }

    /// Add participant to game
    pub async fn add_game_participant(
        &self,
        game_id: &str,
        player_id: &str,
        role_name: &str,
        is_alive: bool,
        seat_number: i32,
    ) -> DbResult<()> {
        let participant_id = Uuid::new_v4().to_string();
        let now = chrono::Utc::now().to_rfc3339();

        // Need role_id from role_name
        let role_id: i32 = sqlx::query("SELECT role_id FROM roles WHERE role_name = $1")
            .bind(role_name)
            .fetch_optional(&self.pool)
            .await?
            .map(|row| row.get(0))
            .unwrap_or(0); // Fallback or error handling

        sqlx::query(
            "INSERT INTO game_participants 
             (game_participant_id, game_id, player_id, role_id, is_alive, seat_number, joined_at)
             VALUES ($1, $2, $3, $4, $5, $6, $7)",
        )
        .bind(&participant_id)
        .bind(game_id)
        .bind(player_id)
        .bind(role_id)
        .bind(is_alive as i32) // Postgres boolean vs integer check? Schema used INTEGER NOT NULL CHECK (is_alive IN (0,1))
        .bind(seat_number)
        .bind(&now)
        .execute(&self.pool)
        .await?;

        Ok(())
    }

    /// End game
    pub async fn end_game(&self, game_id: &str, winner_faction: &str) -> DbResult<()> {
        let now = chrono::Utc::now().to_rfc3339();

        sqlx::query(
            "UPDATE games SET ended_at = $1, game_status = 'FINISHED', winner_faction = $2 
             WHERE game_id = $3",
        )
        .bind(&now)
        .bind(winner_faction)
        .bind(game_id)
        .execute(&self.pool)
        .await?;

        Ok(())
    }

    /// Save chat message
    pub async fn save_chat_message(
        &self,
        game_id: &str,
        phase_id: Option<&str>,
        sender_id: &str,
        chat_scope: &str,
        message: &str,
    ) -> DbResult<()> {
        let message_id = Uuid::new_v4().to_string();
        let now = chrono::Utc::now().to_rfc3339();

        sqlx::query(
            "INSERT INTO chat_messages 
             (message_id, game_id, phase_id, sender_id, chat_scope, message_text, created_at)
             VALUES ($1, $2, $3, $4, $5, $6, $7)",
        )
        .bind(&message_id)
        .bind(game_id)
        .bind(phase_id)
        .bind(sender_id)
        .bind(chat_scope)
        .bind(message)
        .bind(&now)
        .execute(&self.pool)
        .await?;

        Ok(())
    }
}
