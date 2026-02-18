//! # HTTP/WebSocket Server
//!
//! Standalone server for Are You Ghost game.
//! Binds to 0.0.0.0:3000 with health check and WebSocket endpoints.

use std::{net::SocketAddr, sync::Arc};
use axum::{routing::get, Router};
use tower_http::cors::CorsLayer;
use tokio::net::TcpListener;

mod routes;
mod ws;
mod state;

use routes::health::health_check;
use state::manager::GameRoomManager;

#[tokio::main]
async fn main() {
    // Initialize tracing for logging
    tracing_subscriber::fmt::init();

    // Create shared game state
    let manager = Arc::new(GameRoomManager::new());

    // Build the application router
    let app = Router::new()
        .route("/", get(|| async { "Are You Ghost? Server Online" }))
        .route("/health", get(health_check))
        .route("/ws", get(ws::ws_handler))
        .layer(CorsLayer::permissive())
        .with_state(manager);

    // Bind to 0.0.0.0:3000 (not 127.0.0.1)
    // This allows external connections through Cloudflare tunnel
    let addr = SocketAddr::from(([0, 0, 0, 0], 3000));

    tracing::info!("Server listening on {}", addr);
    tracing::info!("Health check: http://localhost:3000/health");
    tracing::info!("WebSocket: ws://localhost:3000/ws");

    // Start the server
    let listener = TcpListener::bind(addr)
        .await
        .expect("Failed to bind to 0.0.0.0:3000");

    axum::serve(listener, app)
        .await
        .expect("Failed to start server");
}
