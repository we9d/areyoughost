//! # FFI API Module
//!
//! This module provides the FFI (Foreign Function Interface) exports
//! that allow the Flutter frontend to communicate with the Rust backend.
//!
//! All public functions in the `Api` struct are exposed to Flutter via
//! flutter_rust_bridge and handle user authentication, room management,
//! and game actions.

use crate::models::*;
use crate::network::tcp_server::TcpServer;
use crate::network::tcp_client::TcpClient;
use anyhow::{Result, anyhow};
use std::sync::{Arc, Mutex};

/// Main API struct for FFI exports to Flutter
///
/// This struct will hold the database connection, network state,
/// and game state management. All methods are exposed to Flutter
/// via flutter_rust_bridge.
pub struct Api {
    // Network state (Host/Client)
    // We use Arc<Mutex<Option<...>>> to allow interior mutability and sharing
    server: Arc<Mutex<Option<TcpServer>>>,
    client: Arc<Mutex<Option<TcpClient>>>,
}

impl Api {
    pub fn new() -> Self {
        Api {
            server: Arc::new(Mutex::new(None)),
            client: Arc::new(Mutex::new(None)),
        }
    }

    /// User authentication (Mock for now)
    pub fn login(&self, username: String, _password: String) -> Result<User> {
        Ok(User {
            user_id: 1,
            username,
            password_hash: String::new(),
            created_at: String::new(),
            last_login: None,
        })
    }

    pub fn register(&self, username: String, _password: String) -> Result<User> {
        Ok(User {
            user_id: 1,
            username,
            password_hash: String::new(),
            created_at: String::new(),
            last_login: None,
        })
    }

    // --- Network Management ---

    /// Host: Start a TCP server on port 27015
    pub async fn create_room(&self, room_name: String, max_players: i32) -> Result<String> {
        // Stop any existing server/client
        *self.server.lock().unwrap() = None;
        *self.client.lock().unwrap() = None;

        let addr = "0.0.0.0:27015";
        let server = TcpServer::bind(addr).await
            .map_err(|e| anyhow!("Failed to bind server to {}: {}", addr, e))?;
        
        *self.server.lock().unwrap() = Some(server);
        
        // Return success message
        Ok(format!("Room '{}' created on port 27015. Max players: {}", room_name, max_players))
    }

    /// Peer: Connect to a host IP on port 27015
    pub async fn join_room(&self, host_ip: String) -> Result<String> {
        // Stop any existing server/client
        *self.server.lock().unwrap() = None;
        *self.client.lock().unwrap() = None;

        let addr = format!("{}:27015", host_ip);
        let client = TcpClient::connect(&addr).await
            .map_err(|e| anyhow!("Failed to connect to host {}: {}", addr, e))?;

        *self.client.lock().unwrap() = Some(client);
        
        Ok(format!("Successfully connected to {}", addr))
    }

    /// Helper: Get local IP addresses for display
    /// Returns a list of strings (e.g., ["192.168.1.5", "10.147.19.1"])
    /// Requires `get_if_addrs` crate or manual parsing (Mocking for now to avoid dep hell)
    pub fn get_local_ips(&self) -> Result<Vec<String>> {
        // Note: For a robust solution, we should add `get_if_addrs` crate later.
        // For now, we rely on the user knowing their VPN IP as discussed.
        // Returning a placeholder to indicate where the IPs would be.
        Ok(vec![
            "Check your VPN/LAN adapter settings".to_string(),
            "(Use ipconfig on Windows)".to_string()
        ])
    }

    /// Test connection with a handshake
    /// Sends a "PING" message and expects a "PONG" response (or just successful send for now)
    pub async fn test_connection(&self) -> Result<String> {
        let mut client_lock = self.client.lock().unwrap();
        
        if let Some(_client) = client_lock.as_mut() {
             // For now, since we haven't implemented full message framing reading in TcpClient yet,
             // we'll just check if the socket is writable/connected.
             // In Phase 5/6 we will implement actual PING/PONG packet exchange.
             // TcpClient doesn't expose `write` directly yet, need to add it or use `stream`.
             // Assuming TcpClient will have a `send` method soon. 
             // For this step, we'll return OK if client exists.
             Ok("Connection active".to_string())
        } else {
            Err(anyhow!("No active client connection"))
        }
    }

    // --- Game Actions ---

    pub fn send_message(&self, room_id: String, user_id: i64, message: String) -> Result<ChatMessage> {
        Ok(ChatMessage {
            message_id: 1,
            room_id,
            sender_id: user_id,
            sender_name: String::from("Player"),
            message,
            phase_type: String::from("day"),
            created_at: String::new(),
        })
    }

    pub fn cast_vote(&self, room_id: String, voter_id: i64, target_id: i64) -> Result<Vote> {
        Ok(Vote {
            vote_id: 1,
            room_id,
            phase_id: 1,
            voter_id,
            target_id,
            created_at: String::new(),
        })
    }
}
