//! # HTTP/WebSocket Server
//!
//! Standalone server for Are You Ghost game.
//! Binds to 0.0.0.0:3000 with health check, auth, and WebSocket endpoints.

use std::{net::SocketAddr, sync::Arc};

use axum::{routing::{get, post}, Router};
use sqlx::postgres::{PgPoolOptions, PgConnectOptions};
use std::str::FromStr;
use tower_http::cors::CorsLayer;
use tokio::net::TcpListener;

mod auth;
mod routes;
mod state;
pub mod game_logic; // Scalable Role & Skill Engine (Phase 8)
pub mod network;    // Phase 5 Custom Sockets

use routes::health::health_check;
use routes::auth::{login, register, update_username};
use state::manager::AppState;

#[tokio::main]
async fn main() {
    // Load .env file (next to the binary, or in cwd)
    dotenvy::from_filename("server/.env").ok();
    dotenvy::from_filename(".env").ok();

    // Initialize tracing
    tracing_subscriber::fmt::init();

    // ── Read required env vars ────────────────────────────────────
    let active_db = std::env::var("ACTIVE_DB").unwrap_or_else(|_| "LOCAL".to_string());
    
    let database_url = if active_db.to_uppercase() == "SUPABASE" {
        tracing::info!("🌐 Mode: SUPABASE (Production)");
        std::env::var("DATABASE_URL_SUPABASE")
            .expect("DATABASE_URL_SUPABASE must be set in .env for SUPABASE mode")
    } else {
        tracing::info!("💻 Mode: LOCAL (Development)");
        std::env::var("DATABASE_URL_LOCAL")
            .expect("DATABASE_URL_LOCAL must be set in .env for LOCAL mode")
    };

    // DEBUG (safe): show which DB user/host we are actually using (no password printed)
    let db_host = database_url.split('@').nth(1).unwrap_or("<none>");
    tracing::info!("Connecting to DB host: {}", db_host);

    let jwt_secret = std::env::var("JWT_SECRET")
        .expect("JWT_SECRET must be set in .env or environment");

    println!("Starting server in {} mode", active_db);

    // ── Connect to Postgres (Supabase) ────────────────────────────
    tracing::info!("Connecting to database…");
    
    let connection_options = PgConnectOptions::from_str(&database_url)
        .expect("Failed to parse DATABASE_URL")
        .statement_cache_capacity(0);

    let db = PgPoolOptions::new()
        .max_connections(5)
        .acquire_timeout(std::time::Duration::from_secs(15))
        .idle_timeout(std::time::Duration::from_secs(30))
        .connect_with(connection_options)
        .await
        .expect("Failed to connect to database — check DATABASE_URL and Port (Pooler=6543, Direct=5432)");

    println!("Database connection established ✅");
    tracing::info!("Database connection established ✅");
    
    // ── Cleanup Orphaned Rooms ────────────────────────────────────
    if let Err(e) = AppState::cleanup_stale_rooms(&db).await {
        tracing::warn!("Failed to cleanup stale rooms: {}", e);
    } else {
        tracing::info!("Cleaned up stale rooms from previous sessions ✅");
    }

    // ── Build shared state ────────────────────────────────────────
    tracing::info!("JWT_SECRET loaded: {} chars", jwt_secret.len());
    let state: Arc<AppState> = AppState::new(db, jwt_secret).await;

    // ── Build router ──────────────────────────────────────────────
    let app = Router::new()
        .route("/", get(|| async { "Are You Ghost? Server Online" }))
        .route("/health", get(health_check))
        // Auth
        .route("/auth/register", post(register))
        .route("/auth/login", post(login))
        .route("/auth/username", axum::routing::put(update_username))
        // Game Data
        .route("/game-data", get(routes::game_data::get_game_data))
        .layer(CorsLayer::permissive())
        .with_state(state.clone());

    // ── Bind and serve ────────────────────────────────────────────
    let addr = SocketAddr::from(([0, 0, 0, 0], 3000));
    tracing::info!("HTTP/REST Server listening on {addr} (Management Only)");
    tracing::info!("POST /auth/register  — create account");
    tracing::info!("POST /auth/login     — get JWT");

    // ── Start Areyoughost Binary Protocol Sockets ─────────────────
    // Using Port 8888 (TCP) and 8889 (UDP) to avoid conflicts on host system
    tokio::spawn(network::tcp_server::start_tcp_server(state.clone(), 8888));
    tokio::spawn(network::udp_server::start_udp_server(state.clone(), 8889));

    let listener = TcpListener::bind(addr)
        .await
        .expect("Failed to bind to 0.0.0.0:3000");

    axum::serve(listener, app)
        .await
        .expect("Failed to start server");
}
