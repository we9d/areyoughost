//! # SQLite Database Implementation
//!
//! This module provides the SQLite-specific implementation of the Database trait.
//! It handles all database operations including schema creation, migrations,
//! and data persistence for the game.
//!
//! # Concurrency Model
//!
//! Uses an Actor Model where `SqliteDb` is a handle sending messages to
//! a dedicated background thread running `DbActor`. This ensures all DB
//! operations are serialized and non-blocking to the async runtime.

use rusqlite::{Connection, Result as SqlResult, params};
use tokio::sync::{mpsc, oneshot};
use uuid::Uuid;
use std::thread;
use std::error::Error as StdError;
use std::sync::{Arc, Mutex};
use std::sync::atomic::{AtomicBool, Ordering};
use std::time::Duration;

pub type DbResult<T> = SqlResult<T>;

fn channel_err(msg: &'static str) -> rusqlite::Error {
    rusqlite::Error::ToSqlConversionFailure(Box::<dyn StdError + Send + Sync>::from(msg))
}

fn closed_err() -> rusqlite::Error {
    channel_err("db handle is closed")
}

/// Messages sent to the DbActor
enum DbMessage {
    Init {
        resp: oneshot::Sender<DbResult<()>>,
    },
    LogNetworkEvent {
        game_id: Option<String>,
        session_id: Option<String>,
        direction: String,
        msg_type: String,
        bytes: i64,
        dropped: bool,
        latency_ms: Option<i64>,
        resp: oneshot::Sender<DbResult<()>>,
    },
    CountNetworkLogs {
        resp: oneshot::Sender<DbResult<i64>>,
    },
    /// Graceful shutdown with ACK so caller can avoid hanging forever.
    Shutdown {
        resp: oneshot::Sender<()>,
    },
}

/// The Actor running in a background thread
struct DbActor {
    conn: Connection,
    rx: mpsc::Receiver<DbMessage>,
    enable_wal: bool,
}

impl DbActor {
    fn new(conn: Connection, rx: mpsc::Receiver<DbMessage>, enable_wal: bool) -> Self {
        Self { conn, rx, enable_wal }
    }

    fn run(mut self) {
        // Enforce foreign keys and timeout immediately on start
        let mut pragmas = String::from(
            "PRAGMA foreign_keys = ON;
             PRAGMA busy_timeout = 5000;
             PRAGMA synchronous = NORMAL;"
        );
        
        if self.enable_wal {
            pragmas.push_str("PRAGMA journal_mode = WAL;");
        }
        
        // Execute PRAGMAs (log in debug so failures are visible)
        if let Err(e) = self.conn.execute_batch(&pragmas) {
            #[cfg(debug_assertions)]
            eprintln!("DB PRAGMA failed: {e}");
        }

        while let Some(msg) = self.rx.blocking_recv() {
            match msg {
                DbMessage::Init { resp } => {
                    let r = self.init_schema();
                    let _ = resp.send(r);
                }
                DbMessage::LogNetworkEvent {
                    game_id,
                    session_id,
                    direction,
                    msg_type,
                    bytes,
                    dropped,
                    latency_ms,
                    resp,
                } => {
                    let r = self.log_network_event_impl(
                        game_id.as_deref(),
                        session_id.as_deref(),
                        &direction,
                        &msg_type,
                        bytes,
                        dropped,
                        latency_ms,
                    );
                    let _ = resp.send(r);
                }
                DbMessage::CountNetworkLogs { resp } => {
                    let r = self.count_network_logs_impl();
                    let _ = resp.send(r);
                }
                DbMessage::Shutdown { resp } => {
                    // ACK immediately so caller can proceed even if join blocks
                    let _ = resp.send(());
                    break;
                }
            }
        }
    }

    fn init_schema(&self) -> DbResult<()> {
        self.conn.execute_batch(
            r#"
            -- =========================
            -- 1) PLAYERS
            -- player_name: allow Unicode/Thai/spaces; DB keeps basic length guard
            -- =========================
            CREATE TABLE IF NOT EXISTS players (
              player_id     TEXT PRIMARY KEY,
              player_name   TEXT NOT NULL UNIQUE
                           CHECK (length(player_name) BETWEEN 3 AND 20),
              password_hash TEXT NOT NULL,
              created_at    TEXT NOT NULL,
              updated_at    TEXT NOT NULL,
              last_login    TEXT
            );

            -- =========================
            -- 2) PLAYER_SESSIONS
            -- =========================
            CREATE TABLE IF NOT EXISTS player_sessions (
              session_id           TEXT PRIMARY KEY,
              player_id            TEXT NOT NULL,
              refresh_token_hash   TEXT,
              created_at           TEXT NOT NULL,
              expires_at           TEXT NOT NULL,
              revoked_at           TEXT,
              FOREIGN KEY (player_id) REFERENCES players(player_id) ON DELETE CASCADE
            );
            
            -- (Remaining tables omitted for brevity as they are unchanged)
            -- Ideally we would include them, but to fit context limit we rely on previous content
            -- Correct approach is to keep existing content or replace whole file if needed.
            -- Since previous content was correct for tables 3-15, I will re-include them to be safe.
            
            -- =========================
            -- 3) FRIENDSHIPS
            -- =========================
            CREATE TABLE IF NOT EXISTS friendships (
              friendship_id  TEXT PRIMARY KEY,
              requester_id   TEXT NOT NULL,
              addressee_id   TEXT NOT NULL,
              status         TEXT NOT NULL CHECK (status IN ('PENDING','ACCEPTED','BLOCKED')),
              created_at     TEXT NOT NULL,
              updated_at     TEXT NOT NULL,
              FOREIGN KEY (requester_id) REFERENCES players(player_id) ON DELETE CASCADE,
              FOREIGN KEY (addressee_id) REFERENCES players(player_id) ON DELETE CASCADE,
              CHECK (requester_id <> addressee_id)
            );

            CREATE UNIQUE INDEX IF NOT EXISTS ux_friendships_pair
            ON friendships(requester_id, addressee_id);

            -- =========================
            -- 4) ROOMS
            -- =========================
            CREATE TABLE IF NOT EXISTS rooms (
              room_id       TEXT PRIMARY KEY,
              owner_id      TEXT NOT NULL,
              room_name     TEXT NOT NULL,
              max_players   INTEGER NOT NULL CHECK (max_players BETWEEN 1 AND 16),
              is_public     INTEGER NOT NULL CHECK (is_public IN (0,1)),
              room_status   TEXT NOT NULL CHECK (room_status IN ('WAITING','PLAYING','CLOSED')),
              created_at    TEXT NOT NULL,
              updated_at    TEXT NOT NULL,
              FOREIGN KEY (owner_id) REFERENCES players(player_id) ON DELETE CASCADE
            );

            -- =========================
            -- 5) ROOM_MEMBERS
            -- =========================
            CREATE TABLE IF NOT EXISTS room_members (
              room_member_id  TEXT PRIMARY KEY,
              room_id         TEXT NOT NULL,
              player_id       TEXT NOT NULL,
              member_status   TEXT NOT NULL CHECK (member_status IN ('JOINED','LEFT','KICKED','LOST')),
              joined_at       TEXT NOT NULL,
              left_at         TEXT,
              lost_at         TEXT,
              FOREIGN KEY (room_id) REFERENCES rooms(room_id) ON DELETE CASCADE,
              FOREIGN KEY (player_id) REFERENCES players(player_id) ON DELETE CASCADE
            );

            CREATE UNIQUE INDEX IF NOT EXISTS ux_room_members_room_player
            ON room_members(room_id, player_id);

            CREATE INDEX IF NOT EXISTS ix_room_members_room
            ON room_members(room_id);

            -- =========================
            -- 6) ROOM_INVITES
            -- =========================
            CREATE TABLE IF NOT EXISTS room_invites (
              invite_id     TEXT PRIMARY KEY,
              room_id       TEXT NOT NULL,
              inviter_id    TEXT NOT NULL,
              invitee_id    TEXT NOT NULL,
              status        TEXT NOT NULL CHECK (status IN ('PENDING','ACCEPTED','DECLINED','CANCELED')),
              created_at    TEXT NOT NULL,
              responded_at  TEXT,
              FOREIGN KEY (room_id) REFERENCES rooms(room_id) ON DELETE CASCADE,
              FOREIGN KEY (inviter_id) REFERENCES players(player_id) ON DELETE CASCADE,
              FOREIGN KEY (invitee_id) REFERENCES players(player_id) ON DELETE CASCADE,
              CHECK (inviter_id <> invitee_id)
            );

            CREATE INDEX IF NOT EXISTS ix_room_invites_room
            ON room_invites(room_id);

            -- =========================
            -- 7) ROLES
            -- =========================
            CREATE TABLE IF NOT EXISTS roles (
              role_id      INTEGER PRIMARY KEY,
              role_code    TEXT NOT NULL UNIQUE,
              role_name    TEXT NOT NULL,
              faction      TEXT NOT NULL CHECK (faction IN ('VILLAGER','GHOST','SPECIAL')),
              description  TEXT,
              skill_1      TEXT,
              skill_2      TEXT
            );

            -- =========================
            -- 8) GAMES
            -- =========================
            CREATE TABLE IF NOT EXISTS games (
              game_id        TEXT PRIMARY KEY,
              room_id        TEXT NOT NULL,
              started_at     TEXT NOT NULL,
              ended_at       TEXT,
              game_status    TEXT NOT NULL CHECK (game_status IN ('ONGOING','FINISHED')),
              winner_faction TEXT,
              random_seed    INTEGER NOT NULL,
              FOREIGN KEY (room_id) REFERENCES rooms(room_id) ON DELETE CASCADE
            );

            CREATE INDEX IF NOT EXISTS ix_games_room
            ON games(room_id);

            -- =========================
            -- 9) GAME_PARTICIPANTS
            -- =========================
            CREATE TABLE IF NOT EXISTS game_participants (
              game_participant_id  TEXT PRIMARY KEY,
              game_id              TEXT NOT NULL,
              player_id            TEXT NOT NULL,
              role_id              INTEGER NOT NULL,
              is_alive             INTEGER NOT NULL CHECK (is_alive IN (0,1)),
              seat_number          INTEGER NOT NULL,
              joined_at            TEXT NOT NULL,
              died_at              TEXT,
              FOREIGN KEY (game_id) REFERENCES games(game_id) ON DELETE CASCADE,
              FOREIGN KEY (player_id) REFERENCES players(player_id) ON DELETE CASCADE,
              FOREIGN KEY (role_id) REFERENCES roles(role_id),
              UNIQUE (game_id, player_id),
              UNIQUE (game_id, seat_number)
            );

            CREATE INDEX IF NOT EXISTS ix_game_participants_game
            ON game_participants(game_id);

            -- =========================
            -- 10) GAME_PHASES
            -- =========================
            CREATE TABLE IF NOT EXISTS game_phases (
              phase_id     TEXT PRIMARY KEY,
              game_id      TEXT NOT NULL,
              phase_type   TEXT NOT NULL CHECK (phase_type IN ('NIGHT','DAY','VOTE')),
              vote_scope   TEXT CHECK (vote_scope IN ('DAY','GHOST')),
              phase_order  INTEGER NOT NULL,
              started_at   TEXT NOT NULL,
              ended_at     TEXT,
              FOREIGN KEY (game_id) REFERENCES games(game_id) ON DELETE CASCADE,
              UNIQUE (game_id, phase_order),
              CHECK (
                (phase_type = 'VOTE' AND vote_scope IS NOT NULL)
                OR
                (phase_type <> 'VOTE' AND vote_scope IS NULL)
              )
            );

            CREATE INDEX IF NOT EXISTS ix_game_phases_game
            ON game_phases(game_id, phase_order);

            -- =========================
            -- 11) GAME_ACTIONS
            -- =========================
            CREATE TABLE IF NOT EXISTS game_actions (
              action_id     TEXT PRIMARY KEY,
              game_id       TEXT NOT NULL,
              phase_id      TEXT NOT NULL,
              actor_id      TEXT NOT NULL,
              target_id     TEXT,
              action_type   TEXT NOT NULL,
              action_result INTEGER NOT NULL CHECK (action_result IN (0,1)),
              payload       TEXT,
              created_at    TEXT NOT NULL,
              FOREIGN KEY (game_id) REFERENCES games(game_id) ON DELETE CASCADE,
              FOREIGN KEY (phase_id) REFERENCES game_phases(phase_id) ON DELETE CASCADE,
              FOREIGN KEY (actor_id) REFERENCES players(player_id) ON DELETE CASCADE,
              FOREIGN KEY (target_id) REFERENCES players(player_id) ON DELETE SET NULL
            );

            CREATE INDEX IF NOT EXISTS ix_game_actions_game_phase
            ON game_actions(game_id, phase_id);

            -- =========================
            -- 12) VOTES
            -- =========================
            CREATE TABLE IF NOT EXISTS votes (
              vote_id     TEXT PRIMARY KEY,
              game_id     TEXT NOT NULL,
              phase_id    TEXT NOT NULL,
              voter_id    TEXT NOT NULL,
              target_id   TEXT NOT NULL,
              created_at  TEXT NOT NULL,
              FOREIGN KEY (game_id) REFERENCES games(game_id) ON DELETE CASCADE,
              FOREIGN KEY (phase_id) REFERENCES game_phases(phase_id) ON DELETE CASCADE,
              FOREIGN KEY (voter_id) REFERENCES players(player_id) ON DELETE CASCADE,
              FOREIGN KEY (target_id) REFERENCES players(player_id) ON DELETE CASCADE,
              UNIQUE (game_id, phase_id, voter_id),
              CHECK (voter_id <> target_id)
            );

            CREATE INDEX IF NOT EXISTS ix_votes_game_phase
            ON votes(game_id, phase_id);

            -- =========================
            -- 13) CHAT_MESSAGES
            -- =========================
            CREATE TABLE IF NOT EXISTS chat_messages (
              message_id  TEXT PRIMARY KEY,
              game_id     TEXT NOT NULL,
              phase_id    TEXT,
              sender_id   TEXT NOT NULL,
              chat_scope  TEXT NOT NULL CHECK (chat_scope IN ('LOBBY','DAY_PUBLIC','NIGHT_GHOST')),
              message     TEXT NOT NULL,
              created_at  TEXT NOT NULL,
              FOREIGN KEY (game_id) REFERENCES games(game_id) ON DELETE CASCADE,
              FOREIGN KEY (phase_id) REFERENCES game_phases(phase_id) ON DELETE SET NULL,
              FOREIGN KEY (sender_id) REFERENCES players(player_id) ON DELETE CASCADE
            );

            CREATE INDEX IF NOT EXISTS ix_chat_game_time
            ON chat_messages(game_id, created_at);

            CREATE INDEX IF NOT EXISTS ix_chat_game_scope_time
            ON chat_messages(game_id, chat_scope, created_at);

            -- =========================
            -- 14) GAME_RESULTS
            -- =========================
            CREATE TABLE IF NOT EXISTS game_results (
              game_id        TEXT PRIMARY KEY,
              winner_faction TEXT NOT NULL,
              total_phases   INTEGER NOT NULL,
              ended_reason   TEXT,
              created_at     TEXT NOT NULL,
              FOREIGN KEY (game_id) REFERENCES games(game_id) ON DELETE CASCADE
            );

            -- =========================
            -- 15) NETWORK_LOGS
            -- =========================
            CREATE TABLE IF NOT EXISTS network_logs (
              log_id      TEXT PRIMARY KEY,
              game_id     TEXT,
              session_id  TEXT,
              direction   TEXT NOT NULL CHECK (direction IN ('C2S','S2C')),
              msg_type    TEXT NOT NULL,
              bytes       INTEGER NOT NULL,
              dropped     INTEGER NOT NULL CHECK (dropped IN (0,1)),
              latency_ms  INTEGER,
              created_at  TEXT NOT NULL,
              FOREIGN KEY (game_id) REFERENCES games(game_id) ON DELETE SET NULL,
              FOREIGN KEY (session_id) REFERENCES player_sessions(session_id) ON DELETE SET NULL
            );

            CREATE INDEX IF NOT EXISTS ix_netlogs_game_time
            ON network_logs(game_id, created_at);
            "#
        )?;
        Ok(())
    }

    fn log_network_event_impl(
        &self,
        game_id: Option<&str>,
        session_id: Option<&str>,
        direction: &str,
        msg_type: &str,
        bytes: i64,
        dropped: bool,
        latency_ms: Option<i64>,
    ) -> DbResult<()> {
        let log_id = Uuid::new_v4().to_string();

        self.conn.execute(
            r#"
            INSERT INTO network_logs (
              log_id, game_id, session_id, direction, msg_type, bytes, dropped, latency_ms, created_at
            ) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, strftime('%Y-%m-%dT%H:%M:%SZ','now'))
            "#,
            params![
                log_id,
                game_id,
                session_id,
                direction,
                msg_type,
                bytes,
                if dropped { 1 } else { 0 },
                latency_ms
            ],
        )?;

        Ok(())
    }

    fn count_network_logs_impl(&self) -> DbResult<i64> {
        self.conn.query_row(
            "SELECT count(*) FROM network_logs",
            [],
            |row| row.get(0)
        )
    }
}

/// Helper struct to interact with DbActor
#[derive(Clone)]
pub struct SqliteDb {
    tx: mpsc::Sender<DbMessage>,
    // allow shutdown to join actor thread
    join: Arc<Mutex<Option<std::thread::JoinHandle<()>>>>,
    closed: Arc<AtomicBool>,
}

impl SqliteDb {
    /// Create a new database connection (spawns actor)
    pub async fn new(db_path: &str) -> DbResult<Self> {
        let conn = Connection::open(db_path)?;
        let (tx, rx) = mpsc::channel::<DbMessage>(256);

        // WAL is enabled for file-based DB
        let join = thread::spawn(move || {
            let actor = DbActor::new(conn, rx, true);
            actor.run();
        });

        Ok(Self {
            tx,
            join: Arc::new(Mutex::new(Some(join))),
            closed: Arc::new(AtomicBool::new(false)),
        })
    }

    /// Create in-memory database (spawns actor)
    pub async fn in_memory() -> DbResult<Self> {
        let conn = Connection::open_in_memory()?;
        let (tx, rx) = mpsc::channel::<DbMessage>(256);

        // WAL is disabled for in-memory DB
        let join = thread::spawn(move || {
            let actor = DbActor::new(conn, rx, false);
            actor.run();
        });

        Ok(Self {
            tx,
            join: Arc::new(Mutex::new(Some(join))),
            closed: Arc::new(AtomicBool::new(false)),
        })
    }

    /// Initialize the database schema
    pub async fn init(&self) -> DbResult<()> {
        if self.closed.load(Ordering::Acquire) {
            return Err(closed_err());
        }

        let (resp_tx, resp_rx) = oneshot::channel();
        self.tx.send(DbMessage::Init { resp: resp_tx }).await
            .map_err(|_| channel_err("db actor channel closed"))?;

        resp_rx.await.map_err(|_| channel_err("db actor dropped response"))?
    }

    /// Log a network event to the database
    pub async fn log_network_event(
        &self,
        game_id: Option<&str>,
        session_id: Option<&str>,
        direction: &str,
        msg_type: &str,
        bytes: usize,
        dropped: bool,
        latency_ms: Option<u64>,
    ) -> DbResult<()> {
        if self.closed.load(Ordering::Acquire) {
            return Err(closed_err());
        }

        let (resp_tx, resp_rx) = oneshot::channel();

        let msg = DbMessage::LogNetworkEvent {
            game_id: game_id.map(|s| s.to_string()),
            session_id: session_id.map(|s| s.to_string()),
            direction: direction.to_string(),
            msg_type: msg_type.to_string(),
            bytes: bytes as i64,
            dropped,
            latency_ms: latency_ms.map(|v| v as i64),
            resp: resp_tx,
        };

        self.tx.send(msg).await
            .map_err(|_| channel_err("db actor channel closed"))?;

        resp_rx.await.map_err(|_| channel_err("db actor dropped response"))?
    }

    /// Shutdown the database actor
    pub async fn shutdown(self) {
        self.closed.store(true, Ordering::Release);

        // 1) send shutdown + wait ack (bounded)
        let (ack_tx, ack_rx) = oneshot::channel();
        let _ = self.tx.send(DbMessage::Shutdown { resp: ack_tx }).await;

        let _ = tokio::time::timeout(Duration::from_secs(2), ack_rx).await;

        // 2) join only once (best-effort)
        if let Some(handle) = self.join.lock().unwrap().take() {
            let _ = handle.join();
        }
    }

    /// Count network logs (helper for testing)
    pub async fn count_network_logs(&self) -> DbResult<i64> {
        if self.closed.load(Ordering::Acquire) {
            return Err(closed_err());
        }

        let (resp_tx, resp_rx) = oneshot::channel();
        self.tx.send(DbMessage::CountNetworkLogs { resp: resp_tx }).await
            .map_err(|_| channel_err("db actor channel closed"))?;
        
        resp_rx.await.map_err(|_| channel_err("db actor dropped response"))?
    }
}

// Remove impl Database for SqliteDb since sync trait doesn't match async actor

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn test_db_creation() {
        let db = SqliteDb::in_memory().await.unwrap();
        assert!(db.init().await.is_ok());
        db.shutdown().await;
    }

    #[tokio::test]
    async fn test_log_network() {
        let db = SqliteDb::in_memory().await.unwrap();
        db.init().await.unwrap();

        db.log_network_event(
            None,
            None,
            "C2S",
            "PING",
            32,
            false,
            Some(10)
        ).await.unwrap();
        
        // Assert count
        let count = db.count_network_logs().await.unwrap();
        assert_eq!(count, 1);

        db.shutdown().await;
    }
}
