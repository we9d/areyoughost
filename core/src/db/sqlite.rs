//! # SQLite Database Implementation
//!
//! This module provides the SQLite-specific implementation of the Database trait.
//! It handles all database operations including schema creation, migrations,
//! and data persistence for the game.

use rusqlite::{Connection, Result};
use super::Database;

/// SQLite database implementation
///
/// Manages the SQLite connection and provides methods for
/// database initialization and operations.
pub struct SqliteDb {
    conn: Connection,
}

impl SqliteDb {
    pub fn new(db_path: &str) -> Result<Self> {
        let conn = Connection::open(db_path)?;
        Ok(SqliteDb { conn })
    }

    pub fn in_memory() -> Result<Self> {
        let conn = Connection::open_in_memory()?;
        Ok(SqliteDb { conn })
    }
}

impl Database for SqliteDb {
    fn init(&self) -> Result<()> {
        // Create users table
        self.conn.execute(
            "CREATE TABLE IF NOT EXISTS users (
                user_id INTEGER PRIMARY KEY AUTOINCREMENT,
                username TEXT NOT NULL UNIQUE,
                password_hash TEXT NOT NULL,
                created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
                last_login DATETIME
            )",
            [],
        )?;

        // Create rooms table
        self.conn.execute(
            "CREATE TABLE IF NOT EXISTS rooms (
                room_id TEXT PRIMARY KEY,
                room_name TEXT NOT NULL,
                max_players INTEGER NOT NULL,
                current_players INTEGER DEFAULT 0,
                is_public BOOLEAN DEFAULT 1,
                status TEXT DEFAULT 'waiting',
                created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
                started_at DATETIME,
                ended_at DATETIME
            )",
            [],
        )?;

        // Create game_sessions table
        self.conn.execute(
            "CREATE TABLE IF NOT EXISTS game_sessions (
                session_id INTEGER PRIMARY KEY AUTOINCREMENT,
                room_id TEXT NOT NULL,
                user_id INTEGER NOT NULL,
                role TEXT,
                is_alive BOOLEAN DEFAULT 1,
                joined_at DATETIME DEFAULT CURRENT_TIMESTAMP,
                FOREIGN KEY (room_id) REFERENCES rooms(room_id),
                FOREIGN KEY (user_id) REFERENCES users(user_id)
            )",
            [],
        )?;

        // Create game_history table
        self.conn.execute(
            "CREATE TABLE IF NOT EXISTS game_history (
                history_id INTEGER PRIMARY KEY AUTOINCREMENT,
                room_id TEXT NOT NULL,
                winner_team TEXT,
                total_rounds INTEGER,
                ended_at DATETIME DEFAULT CURRENT_TIMESTAMP,
                FOREIGN KEY (room_id) REFERENCES rooms(room_id)
            )",
            [],
        )?;

        Ok(())
    }

    fn migrate(&self) -> Result<()> {
        // Future migrations will go here
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_db_creation() {
        let db = SqliteDb::in_memory().unwrap();
        assert!(db.init().is_ok());
    }
}
