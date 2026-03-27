//! # HTTP/WebSocket Server
//!
//! Standalone server for Are You Ghost game.
//! Binds to 0.0.0.0:3000 with health check, auth, and WebSocket endpoints.

use std::{net::SocketAddr, sync::Arc};

use axum::{routing::{get, post}, Router};
use sqlx::postgres::PgPoolOptions;
use tower_http::cors::CorsLayer;
use tokio::net::TcpListener;

mod auth;
mod routes;
mod state;
mod ws;
pub mod network; // Phase 5 Custom Sockets

use routes::health::health_check;
use routes::auth::{login, register};
use state::manager::AppState;

#[tokio::main]
async fn main() {
    // Load .env file (next to the binary, or in cwd)
    dotenvy::from_filename("server/.env").ok();
    dotenvy::from_filename(".env").ok();

    // Initialize tracing
    tracing_subscriber::fmt::init();

    // ── Read required env vars ────────────────────────────────────
    let database_url = std::env::var("DATABASE_URL")
        .expect("DATABASE_URL must be set in .env or environment");

    // DEBUG (safe): show which DB user/host we are actually using (no password printed)
    let db_user = database_url.split("://").nth(1).unwrap_or("")
        .split(':').next().unwrap_or("<none>");
    let db_host = database_url.split('@').nth(1).unwrap_or("<none>");
    tracing::info!("DB user = {}", db_user);
    tracing::info!("DB host = {}", db_host);

    let jwt_secret = std::env::var("JWT_SECRET")
        .expect("JWT_SECRET must be set in .env or environment");

    // ── Connect to Postgres (Supabase) ────────────────────────────
    tracing::info!("Connecting to database…");
    let db = PgPoolOptions::new()
        .max_connections(10)
        .connect(&database_url)
        .await
        .expect("Failed to connect to database — check DATABASE_URL");

    // Quick sanity check
    sqlx::query("SELECT 1")
        .execute(&db)
        .await
        .expect("Database health-check failed");

    tracing::info!("Database connection established ✅");

    // DEBUG SCHEMA
    let rows = sqlx::query("SELECT column_name, data_type FROM information_schema.columns WHERE table_name = 'rooms'")
        .fetch_all(&db)
        .await
        .unwrap();
    tracing::info!("--- rooms table schema ---");
    use sqlx::Row;
    for r in rows {
        let col: String = r.get("column_name");
        let ty: String = r.get("data_type");
        tracing::info!("Col: {:<15} Type: {}", col, ty);
    }
    tracing::info!("--------------------------");

    // ── Build shared state ────────────────────────────────────────
    tracing::info!("JWT_SECRET loaded: {} chars", jwt_secret.len());
    let state: Arc<AppState> = AppState::new(db, jwt_secret);

    // ── Build router ──────────────────────────────────────────────
    let app = Router::new()
        .route("/", get(|| async { "Are You Ghost? Server Online" }))
        .route("/health", get(health_check))
        // Auth
        .route("/auth/register", post(register))
        .route("/auth/login", post(login))
        // WebSocket
        .route("/ws", get(ws::ws_handler))
        .layer(CorsLayer::permissive())
        .with_state(state.clone());

    // ── Bind and serve ────────────────────────────────────────────
    let addr = SocketAddr::from(([0, 0, 0, 0], 3000));
    tracing::info!("HTTP Server listening on {addr}");
    tracing::info!("POST /auth/register  — create account");
    tracing::info!("POST /auth/login     — get JWT");
    tracing::info!("WS   /ws             — WebSocket (Legacy)");

    // ── Start Phase 5 Custom Sockets ──────────────────────────────
    tokio::spawn(network::tcp_server::start_tcp_server(state.clone(), 3001));
    tokio::spawn(network::udp_server::start_udp_server(state.clone(), 3002));

    let listener = TcpListener::bind(addr)
        .await
        .expect("Failed to bind to 0.0.0.0:3000");

    axum::serve(listener, app)
        .await
        .expect("Failed to start server");
}
