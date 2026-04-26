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
mod game_tcp_std;
mod session_auth;
mod tcp_framing_async;
mod tcp_framing_std;
mod persistence;
mod protocol;
mod routes;
mod state;
mod ws;
mod raw_tcp;

use routes::health::health_check;
use routes::auth::{login, register, update_username};
use routes::friends::{overview as friends_overview, respond_request, send_request};
use routes::players::search_players;
use routes::roles::list_roles;
use state::manager::AppState;

async fn connect_db_with_retry(database_url: &str) -> sqlx::PgPool {
    let max_attempts = std::env::var("DB_CONNECT_MAX_ATTEMPTS")
        .ok()
        .and_then(|v| v.parse::<u32>().ok())
        .unwrap_or(8);
    let connect_timeout_secs = std::env::var("DB_CONNECT_TIMEOUT_SECS")
        .ok()
        .and_then(|v| v.parse::<u64>().ok())
        .unwrap_or(10);
    let base_delay_ms = std::env::var("DB_CONNECT_RETRY_BASE_MS")
        .ok()
        .and_then(|v| v.parse::<u64>().ok())
        .unwrap_or(1000);
    let max_delay_ms = std::env::var("DB_CONNECT_RETRY_MAX_MS")
        .ok()
        .and_then(|v| v.parse::<u64>().ok())
        .unwrap_or(30_000);

    let mut attempt: u32 = 0;
    let mut delay_ms = base_delay_ms.max(100);
    loop {
        attempt += 1;
        tracing::info!(
            "Connecting to database… attempt {}/{} (connect_timeout={}s)",
            attempt,
            max_attempts,
            connect_timeout_secs
        );
        let result = PgPoolOptions::new()
            .max_connections(10)
            .acquire_timeout(std::time::Duration::from_secs(connect_timeout_secs))
            .connect(database_url)
            .await;

        match result {
            Ok(pool) => return pool,
            Err(e) => {
                if attempt >= max_attempts {
                    panic!(
                        "Failed to connect to database after {} attempts: {}",
                        max_attempts, e
                    );
                }
                tracing::warn!(
                    "Database connection attempt {}/{} failed: {}. Retrying in {} ms",
                    attempt,
                    max_attempts,
                    e,
                    delay_ms
                );
                tokio::time::sleep(std::time::Duration::from_millis(delay_ms)).await;
                delay_ms = (delay_ms.saturating_mul(2)).min(max_delay_ms);
            }
        }
    }
}

fn require_supabase_database_url(database_url: &str) {
    if !database_url.contains("sslmode=require") {
        panic!("DATABASE_URL must include sslmode=require for Supabase-only mode");
    }

    if !database_url.contains("supabase.co") {
        panic!("DATABASE_URL must point to a Supabase host (supabase.co)");
    }
}

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
    require_supabase_database_url(&database_url);

    // DEBUG (safe): show which DB user/host we are actually using (no password printed)
    let db_user = database_url.split("://").nth(1).unwrap_or("")
        .split(':').next().unwrap_or("<none>");
    let db_host = database_url.split('@').nth(1).unwrap_or("<none>");
    tracing::info!("DB user = {}", db_user);
    tracing::info!("DB host = {}", db_host);

    let jwt_secret = std::env::var("JWT_SECRET")
        .expect("JWT_SECRET must be set in .env or environment");
    let reconnect_grace_secs = std::env::var("RECONNECT_GRACE_SECS")
        .ok()
        .and_then(|v| v.parse::<u64>().ok())
        .unwrap_or(90);
    let day_phase_secs = std::env::var("DAY_PHASE_SECS")
        .ok()
        .and_then(|v| v.parse::<u64>().ok())
        .unwrap_or(60);
    let night_phase_secs = std::env::var("NIGHT_PHASE_SECS")
        .ok()
        .and_then(|v| v.parse::<u64>().ok())
        .unwrap_or(20);
    let voting_phase_secs = std::env::var("VOTING_PHASE_SECS")
        .ok()
        .and_then(|v| v.parse::<u64>().ok())
        .unwrap_or(15);

    // ── Connect to Postgres (Supabase) ────────────────────────────
    let db = connect_db_with_retry(&database_url).await;

    // Quick sanity check
    sqlx::query("SELECT 1")
        .execute(&db)
        .await
        .expect("Database health-check failed");

    tracing::info!("Database connection established ✅");

    // ── Build shared state ────────────────────────────────────────
    tracing::info!("JWT_SECRET loaded: {} chars", jwt_secret.len());
    tracing::info!("Reconnect grace period: {}s", reconnect_grace_secs);
    let state: Arc<AppState> = AppState::new(
        db,
        jwt_secret,
        reconnect_grace_secs,
        day_phase_secs,
        night_phase_secs,
        voting_phase_secs,
    );

    let tick_state = state.clone();
    tokio::spawn(async move {
        let mut interval = tokio::time::interval(std::time::Duration::from_millis(500));
        loop {
            interval.tick().await;
            tick_state.tick_games();
        }
    });

    // ── Build router ──────────────────────────────────────────────
    let app = Router::new()
        .route("/", get(|| async { "Are You Ghost? Server Online" }))
        .route("/health", get(health_check))
        // Auth
        .route("/auth/register", post(register))
        .route("/auth/login", post(login))
        .route("/auth/update-username", post(update_username))
        .route("/players/search", get(search_players))
        .route("/friends/overview", get(friends_overview))
        .route("/friends/request", post(send_request))
        .route("/friends/respond", post(respond_request))
        .route("/roles", get(list_roles))
        // WebSocket
        .route("/ws", get(ws::ws_handler))
        .layer(CorsLayer::permissive())
        .with_state(state.clone());

    // ── Bind and serve ────────────────────────────────────────────
    let addr = SocketAddr::from(([0, 0, 0, 0], 3000));
    tracing::info!("Server listening on {addr}");
    tracing::info!("POST /auth/register  — create account");
    tracing::info!("POST /auth/login     — get JWT");
    tracing::info!("WS   /ws             — WebSocket (auth.hello required)");
    tracing::info!("Raw TCP Protocol     — 3001");
    tracing::info!("Framed TCP (WS wire) — STD_GAME_TCP_BIND (default 3010, or 'off')");

    let tcp_state = state.clone();
    tokio::spawn(async move {
        raw_tcp::start_raw_tcp_server(tcp_state).await;
    });

    let std_tcp_bind =
        std::env::var("STD_GAME_TCP_BIND").unwrap_or_else(|_| "0.0.0.0:3010".to_string());
    if std_tcp_bind != "off" && !std_tcp_bind.is_empty() {
        let bind = std_tcp_bind.clone();
        let st = state.clone();
        tokio::spawn(async move {
            if let Err(e) = game_tcp_std::run_tcp_listener(bind, st).await {
                tracing::error!("Framed TCP listener exited: {}", e);
            }
        });
    }

    let listener = TcpListener::bind(addr)
        .await
        .expect("Failed to bind to 0.0.0.0:3000");

    axum::serve(listener, app)
        .await
        .expect("Failed to start server");
}
