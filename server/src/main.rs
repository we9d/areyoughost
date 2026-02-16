//! # HTTP/WebSocket Server
//!
//! Standalone server for Are You Ghost game.
//! Binds to 0.0.0.0:3000 with health check and WebSocket endpoints.

use axum::{
    extract::ws::{Message, WebSocket, WebSocketUpgrade},
    response::{IntoResponse, Json},
    routing::get,
    Router,
};
use serde_json::json;
use std::net::SocketAddr;
use tower_http::cors::{Any, CorsLayer};

#[tokio::main]
async fn main() {
    // Initialize tracing for logging
    tracing_subscriber::fmt::init();

    // Build the application router
    let app = Router::new()
        .route("/", get(health_check))
        .route("/health", get(health_check))
        .route("/ws", get(websocket_handler))
        // Enable CORS for browser clients
        .layer(
            CorsLayer::new()
                .allow_origin(Any)
                .allow_methods(Any)
                .allow_headers(Any),
        );

    // Bind to 0.0.0.0:3000 (not 127.0.0.1)
    // This allows external connections through Cloudflare tunnel
    let addr = SocketAddr::from(([0, 0, 0, 0], 3000));

    tracing::info!("Server listening on {}", addr);
    tracing::info!("Health check: http://localhost:3000/health");
    tracing::info!("WebSocket: ws://localhost:3000/ws");

    // Start the server
    let listener = tokio::net::TcpListener::bind(addr)
        .await
        .expect("Failed to bind to 0.0.0.0:3000");

    axum::serve(listener, app)
        .await
        .expect("Failed to start server");
}

/// Health check endpoint
/// GET / or GET /health
async fn health_check() -> Json<serde_json::Value> {
    Json(json!({
        "status": "ok",
        "server": "areyoughost",
        "timestamp": chrono::Utc::now().to_rfc3339(),
    }))
}

/// WebSocket connection handler
/// GET /ws
async fn websocket_handler(ws: WebSocketUpgrade) -> impl IntoResponse {
    ws.on_upgrade(handle_socket)
}

/// Handle WebSocket connection
async fn handle_socket(mut socket: WebSocket) {
    tracing::info!("New WebSocket connection established");

    // Send welcome message
    if socket
        .send(Message::Text("Welcome to Are You Ghost!".into()))
        .await
        .is_err()
    {
        tracing::error!("Failed to send welcome message");
        return;
    }

    // Message echo loop (placeholder for game logic)
    while let Some(msg) = socket.recv().await {
        match msg {
            Ok(Message::Text(text)) => {
                tracing::info!("Received: {}", text);

                // Echo back for now (will integrate with game logic later)
                let response = json!({
                    "type": "echo",
                    "message": text,
                    "timestamp": chrono::Utc::now().to_rfc3339(),
                });

                if socket
                    .send(Message::Text(response.to_string()))
                    .await
                    .is_err()
                {
                    tracing::error!("Failed to send message");
                    break;
                }
            },
            Ok(Message::Close(_)) => {
                tracing::info!("WebSocket connection closed");
                break;
            },
            Err(e) => {
                tracing::error!("WebSocket error: {:?}", e);
                break;
            },
            _ => {},
        }
    }
}
