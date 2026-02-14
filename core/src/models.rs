//! # Data Models
//!
//! This module defines all data structures used throughout the application.
//! All models are serializable for database storage and network transmission.
//!
//! ## Core Models
//! - **User**: Player account information
//! - **Room**: Game room/lobby information
//! - **GameParticipant**: Player state within a game session
//! - **GamePhase**: Game phase tracking (day/night/vote)
//! - **ChatMessage**: In-game chat messages
//! - **Vote**: Player voting records
//! - **GameAction**: Player actions during game phases
//!
//! ## DTOs (Data Transfer Objects)
//! - **RoomListItem**: Simplified room info for lobby list
//! - **GameState**: Complete game state snapshot

use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct User {
    pub user_id: i64,
    pub username: String,
    pub password_hash: String,
    pub created_at: String,
    pub last_login: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Room {
    pub room_id: String,
    pub room_name: String,
    pub max_players: i32,
    pub current_players: i32,
    pub is_public: bool,
    pub status: String, // 'waiting', 'playing', 'finished'
    pub created_at: String,
    pub started_at: Option<String>,
    pub ended_at: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Role {
    pub role_id: i32,
    pub role_name: String,
    pub faction: String, // 'villager', 'wolf', 'neutral'
    pub description: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GameParticipant {
    pub session_id: i64,
    pub room_id: String,
    pub user_id: i64,
    pub username: String, // Denormalized for convenience
    pub role: Option<String>,
    pub is_alive: bool,
    pub seat_number: i32,
    pub joined_at: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GamePhase {
    pub phase_id: i64,
    pub room_id: String,
    pub phase_type: String, // 'day', 'night', 'vote'
    pub phase_order: i32,
    pub started_at: String,
    pub ended_at: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ChatMessage {
    pub message_id: i64,
    pub room_id: String,
    pub sender_id: i64,
    pub sender_name: String,
    pub message: String,
    pub phase_type: String,
    pub created_at: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Vote {
    pub vote_id: i64,
    pub room_id: String,
    pub phase_id: i64,
    pub voter_id: i64,
    pub target_id: i64,
    pub created_at: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GameAction {
    pub action_id: i64,
    pub room_id: String,
    pub phase_id: i64,
    pub actor_id: i64,
    pub target_id: Option<i64>,
    pub action_type: String,
    pub action_result: Option<String>,
    pub created_at: String,
}

// DTOs for API responses
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RoomListItem {
    pub room_id: String,
    pub room_name: String,
    pub current_players: i32,
    pub max_players: i32,
    pub status: String,
    pub is_public: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GameState {
    pub room: Room,
    pub participants: Vec<GameParticipant>,
    pub current_phase: Option<GamePhase>,
    pub recent_messages: Vec<ChatMessage>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GameResult {
    pub game_id: String,
    pub winner_faction: String,
    pub total_phases: i32,
    pub ended_reason: Option<String>,
    pub created_at: String,
}
