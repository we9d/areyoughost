//! # FFI API Module
//!
//! This module provides the FFI (Foreign Function Interface) exports
//! that allow the Flutter frontend to communicate with the Rust backend.
//!
//! All public functions in the `Api` struct are exposed to Flutter via
//! flutter_rust_bridge.
//!
//! **NOTE**: This module has been refactored to use the Dedicated Server (HTTP/WS)
//! instead of a local SQLite database.

use crate::models::*;
use crate::http_client::HttpClient;
use anyhow::{Result, anyhow};
use std::sync::{Arc, Mutex};
use tokio::sync::Mutex as AsyncMutex;

/// Main API struct for FFI exports to Flutter
pub struct Api {
    client: Arc<AsyncMutex<HttpClient>>,
    // We can keep these for P2P references if needed later, but mostly likely
    // we will move to pure WebSocket client logic for the game.
}

impl Api {
    /// Initialize API with server URL (e.g. "http://127.0.0.1:3000")
    /// The `db_path` argument is kept for compatibility but ignored (or reused as server URL).
    pub async fn new(server_url: &str) -> Result<Self> {
        println!("Rust: Connecting to server at {}", server_url);
        let client = HttpClient::new(server_url.to_string());
        
        Ok(Api {
            client: Arc::new(AsyncMutex::new(client)),
        })
    }

    /// Register a new user via Server API
    pub async fn register(&self, username: String, password: String) -> Result<User> {
        println!("Rust: Registering '{}' at server...", username);
        let mut client = self.client.lock().await; // Lock for mutable access
        
        let msg = client.register(username.clone(), password.clone()).await?;
        println!("Rust: Server response: {}", msg);

        // For now, return a dummy User object since the server doesn't return the full user on register
        // In a real flow, we might auto-login or ask user to login.
        Ok(User {
            user_id: "pending".to_string(),
            username,
            password_hash: "handled_by_server".to_string(),
            created_at: chrono::Utc::now().to_rfc3339(),
            last_login: None,
        })
    }

    /// Login user via Server API
    pub async fn login(&self, username: String, password: String) -> Result<User> {
        println!("Rust: Login attempt for '{}'...", username);
        let mut client = self.client.lock().await;

        let (player_id, token) = client.login(username.clone(), password.clone()).await?;
        
        println!("Rust: Login successful. Token: {}...", &token[0..10]);

        Ok(User {
            user_id: player_id,
            username,
            password_hash: "hidden".to_string(),
            created_at: chrono::Utc::now().to_rfc3339(),
            last_login: Some(token), // Return the JWT token as the session
        })
    }

    // --- Legacy P2P / Local methods (Stubbed or Redirected) ---

    pub async fn create_room(&self, room_name: String, max_players: i32) -> Result<String> {
        // TODO: Call Server API to create room
        Ok("Use WebSocket for room creation".to_string())
    }

    pub async fn join_room(&self, host_ip: String) -> Result<String> {
        // TODO: Call Server API to join room
        Ok("Use WebSocket for room joining".to_string())
    }

    pub fn get_local_ips(&self) -> Result<Vec<String>> {
        Ok(vec!["Server Mode Active".to_string()])
    }

    pub async fn test_connection(&self) -> Result<String> {
        Ok("Server Connection OK".to_string())
    }

    pub fn send_message(&self, room_id: String, user_id: String, message: String) -> Result<ChatMessage> {
       // TODO: Send via WebSocket
        Ok(ChatMessage {
            message_id: "temp".to_string(),
            room_id,
            sender_id: user_id,
            sender_name: "Me".to_string(),
            message,
            phase_type: "lobb".to_string(),
            created_at: chrono::Utc::now().to_rfc3339(),
        })
    }

    pub fn cast_vote(&self, room_id: String, voter_id: String, target_id: String) -> Result<Vote> {
        Ok(Vote {
             vote_id: "temp".to_string(),
             room_id,
             phase_id: "temp".to_string(),
             voter_id,
             target_id,
             created_at: chrono::Utc::now().to_rfc3339(),
        })
    }
}
