//! # FFI API Module
//!
//! This module provides the FFI (Foreign Function Interface) exports
//! that allow the Flutter frontend to communicate with the Rust backend.
//!
//! All public functions in the `Api` struct are exposed to Flutter via
//! flutter_rust_bridge and handle user authentication, room management,
//! and game actions.

use crate::models::*;
use anyhow::Result;

/// Main API struct for FFI exports to Flutter
///
/// This struct will hold the database connection, network state,
/// and game state management. All methods are exposed to Flutter
/// via flutter_rust_bridge.
pub struct Api {
    // Will hold database connection and state
}

impl Api {
    pub fn new() -> Self {
        Api {}
    }

    // User authentication
    pub fn login(&self, username: String, password: String) -> Result<User> {
        // TODO: Implement actual authentication
        Ok(User {
            user_id: 1,
            username,
            password_hash: String::new(),
            created_at: String::new(),
            last_login: None,
        })
    }

    pub fn register(&self, username: String, password: String) -> Result<User> {
        // TODO: Implement user registration
        Ok(User {
            user_id: 1,
            username,
            password_hash: String::new(),
            created_at: String::new(),
            last_login: None,
        })
    }

    // Room management
    pub fn get_rooms(&self) -> Result<Vec<RoomListItem>> {
        // TODO: Fetch from database
        Ok(vec![])
    }

    pub fn create_room(&self, room_name: String, max_players: i32) -> Result<Room> {
        // TODO: Create room in database
        Ok(Room {
            room_id: String::from("room_1"),
            room_name,
            max_players,
            current_players: 0,
            is_public: true,
            status: String::from("waiting"),
            created_at: String::new(),
            started_at: None,
            ended_at: None,
        })
    }

    pub fn join_room(&self, room_id: String, user_id: i64) -> Result<GameState> {
        // TODO: Join room logic
        Ok(GameState {
            room: Room {
                room_id: room_id.clone(),
                room_name: String::from("Test Room"),
                max_players: 16,
                current_players: 1,
                is_public: true,
                status: String::from("waiting"),
                created_at: String::new(),
                started_at: None,
                ended_at: None,
            },
            participants: vec![],
            current_phase: None,
            recent_messages: vec![],
        })
    }

    // Game actions
    pub fn send_message(&self, room_id: String, user_id: i64, message: String) -> Result<ChatMessage> {
        // TODO: Save and broadcast message
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
        // TODO: Record vote
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
