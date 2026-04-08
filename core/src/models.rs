//! # Data Models
//!
//! This module defines all data structures used throughout the application.
//! All models are serializable for database storage and network transmission.

use serde::{Deserialize, Serialize};
use uuid::Uuid;
use chrono::{DateTime, Utc};

// ==========================================
// 1. CORE MODELS (Strict Schema Alignment)
// ==========================================

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct User {
    pub player_id: Uuid,
    pub username: String,
    pub email: Option<String>,
    pub password_hash: String,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
    pub last_login: Option<DateTime<Utc>>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "SCREAMING_SNAKE_CASE")]
pub enum GameStatus {
    Waiting,
    Starting,
    Playing,
    Finished,
    Closed,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Room {
    pub room_id: Uuid,
    pub owner_id: Uuid,
    pub room_name: String,
    pub room_type: String, // 'PUBLIC', 'PRIVATE'
    pub max_players: i32,
    pub room_status: GameStatus,
    pub auto_start_at: Option<DateTime<Utc>>,
    pub started_by_owner: bool,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Role {
    pub role_id: i32,
    pub role_code: String,
    pub role_name: String,
    pub faction: String,
    pub description: Option<String>,
    pub seer_result: String,
    pub aura_result: String,
    pub min_players: i32,
    pub max_players: i32,
    pub is_unique: bool,
    pub is_enabled: bool,
    pub role_priority: i32,
    pub role_img: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Skill {
    pub skill_id: Uuid,
    pub skill_code: String,
    pub skill_name: String,
    pub description: Option<String>,
    pub phase_type: String,
    pub target_type: String,
    pub usage_limit: Option<i32>,
    pub can_skip: bool,
    pub is_enabled: bool,
    pub skill_img: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GameParticipant {
    pub game_participant_id: Uuid,
    pub game_id: Uuid,
    pub player_id: Uuid,
    pub role_id: i32,
    pub revealed_role_id: Option<i32>,
    pub is_alive: bool,
    pub seat_number: i32,
    pub joined_at: DateTime<Utc>,
    pub died_at: Option<DateTime<Utc>>,
    pub death_reason: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ParticipantState {
    pub participant_state_id: Uuid,
    pub game_participant_id: Uuid,
    pub original_role_id: i32,
    pub current_role_id: i32,
    pub original_faction: String,
    pub current_faction: String,
    pub is_silenced: bool,
    pub silenced_until_phase_id: Option<Uuid>,
    pub hidden_target_participant_id: Option<Uuid>,
    pub last_protected_target_id: Option<Uuid>,
    pub doctor_power_consumed: bool,
    pub lucky_one_turned: bool,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ParticipantSkillUsage {
    pub participant_skill_usage_id: Uuid,
    pub game_participant_id: Uuid,
    pub skill_id: Uuid,
    pub used_count: i32,
    pub remaining_uses: Option<i32>,
    pub updated_at: DateTime<Utc>,
}

// ==========================================
// 2. DTOs (Data Transfer Objects)
// ==========================================

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RoomListItem {
    pub room_id: Uuid,
    pub room_name: String,
    pub current_players: i32,
    pub max_players: i32,
    pub room_status: GameStatus,
    pub room_type: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GamePhase {
    pub phase_id: Uuid,
    pub game_id: Uuid,
    pub phase_type: String,
    pub vote_scope: Option<String>,
    pub phase_order: i32,
    pub started_at: DateTime<Utc>,
    pub ended_at: Option<DateTime<Utc>>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ChatMessage {
    pub message_id: Uuid,
    pub game_id: Uuid,
    pub phase_id: Option<Uuid>,
    pub sender_id: Option<Uuid>,
    pub chat_scope: String,
    pub message_text: String,
    pub created_at: DateTime<Utc>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GameAction {
    pub action_id: Uuid,
    pub game_id: Uuid,
    pub phase_id: Uuid,
    pub actor_id: Uuid,
    pub target_id: Option<Uuid>,
    pub action_type: String,
    pub action_result: Option<String>,
    pub created_at: DateTime<Utc>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GameStateSnapshot {
    pub game_id: Uuid,
    pub room_id: Uuid,
    pub status: GameStatus,
    pub current_phase: Option<GamePhase>,
    pub participants: Vec<GameParticipant>,
}
