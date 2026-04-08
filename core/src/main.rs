//! # Are You Ghost? — Main Server Binary
//!
//! Wires the authoritative game server: initializes the database connection pool,
//! constructs the shared application state, creates the connection registry,
//! instantiates the dispatcher, and runs the TCP server on port 8888.
//!
//! ## Architecture
//!
//! - **Tracing**: Structured logging via `tracing_subscriber`
//! - **Database**: PostgreSQL connection pool via `sqlx`
//! - **AppState**: Shared `Arc<RwLock<AppState>>` holding all rooms, sessions, and the DB pool
//! - **Connection Registry**: `Arc<DashMap<PlayerId, UnboundedSender<Bytes>>>` for outbound channels
//! - **Dispatcher**: Routes inbound messages to game-logic handlers
//! - **TCP Server**: Listens on 0.0.0.0:8888, accepts connections, spawns per-connection tasks
//!
//! ## Requirements
//!
//! - Requirement 1.1: Connection Registry with DashMap
//! - Requirement 4.1: Dispatcher routes all opcodes
//! - Requirement 28.2: Main server binary initialization

use anyhow::Result;
use areyoughost_core::game_logic::state::AppState;
use areyoughost_core::network::TcpServer;
use tracing_subscriber;

#[tokio::main]
async fn main() -> Result<()> {
    // ─── 1. Initialize tracing_subscriber for structured logging ──────────────
    tracing_subscriber::fmt()
        .with_max_level(tracing::Level::INFO)
        .with_target(true)
        .with_thread_ids(true)
        .with_file(true)
        .with_line_number(true)
        .init();

    tracing::info!("Are You Ghost? Server starting...");

    // ─── 2. Load DATABASE_URL from environment ──────────────────────────────
    // Load .env from server directory (parent of core)
    dotenvy::from_filename("../server/.env").ok();
    dotenvy::dotenv().ok();
    
    let active_db = std::env::var("ACTIVE_DB").unwrap_or_else(|_| "LOCAL".to_string());
    let database_url = if active_db == "SUPABASE" {
        std::env::var("DATABASE_URL_SUPABASE")
            .unwrap_or_else(|_| "postgres://localhost/areyoughost".to_string())
    } else {
        std::env::var("DATABASE_URL_LOCAL")
            .unwrap_or_else(|_| "postgres://localhost/areyoughost".to_string())
    };

    tracing::info!(active_db = %active_db, database_url = %database_url, "Connecting to database...");

    // ─── 3. Create sqlx::PgPool from DATABASE_URL ───────────────────────────
    let db_pool = sqlx::postgres::PgPoolOptions::new()
        .max_connections(5)  // Reduced for Supabase pooler compatibility
        .acquire_timeout(std::time::Duration::from_secs(30))  // Increased from 10 to 30 seconds
        .idle_timeout(std::time::Duration::from_secs(600))
        .max_lifetime(std::time::Duration::from_secs(1800))
        .connect(&database_url)
        .await
        .map_err(|e| {
            tracing::error!(error = %e, "Failed to connect to database — check DATABASE_URL and Port (Pooler=6543, Direct=5432)");
            e
        })?;

    tracing::info!("Database connection pool created");

    // ─── 4. Create Arc<RwLock<AppState>> with the pool ──────────────────────
    let app_state = AppState::new(db_pool);
    tracing::info!("AppState initialized");

    // ─── 5. Create Arc<DashMap<String, UnboundedSender<Bytes>>> registry ─────
    // (This is created inside TcpServer::bind, but we could also create it here
    // and pass it in. For now, TcpServer creates it internally.)

    // ─── 6. Bind TcpServer to 0.0.0.0:8888 ──────────────────────────────────
    let server = TcpServer::bind("0.0.0.0:8888", app_state).await?;
    tracing::info!("TCP server bound to 0.0.0.0:8888");

    // ─── 7. Run the server with server.run().await ──────────────────────────
    tracing::info!("Starting TCP server accept loop...");
    server.run().await;

    // ─── 8. Graceful shutdown (server.run() is infinite, so this is unreachable
    //        unless we implement a shutdown signal handler)
    tracing::info!("Server shutting down");
    Ok(())
}
