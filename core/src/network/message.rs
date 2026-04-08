//! # Message Module - Areyoughost Binary Protocol
//!
//! Implements a robust binary framing protocol for "Are You Ghost?":
//! [2-byte Magic (0xAE 0x80)][1-byte Type][4-byte Length][Payload][2-byte CRC16]

use anyhow::{anyhow, Result};
use bytes::{Buf, BufMut, Bytes, BytesMut};
use serde::{Deserialize, Serialize};
use crc::{Crc, CRC_16_IBM_SDLC};
use uuid::Uuid;

/// Protocol Magic Bytes
pub const MAGIC_BYTES: [u8; 2] = [0xAE, 0x80];
/// Current Protocol Version (v1)
pub const PROTOCOL_VERSION: u8 = 1;

// ─── Binary Payloads (SRS 3.1.4.4 - Custom Auth) ───────────────────

#[derive(Debug, serde::Serialize, serde::Deserialize, Clone)]
pub struct LoginRequest {
    pub username: String,
    pub password: String,
}

#[derive(Debug, serde::Serialize, serde::Deserialize, Clone)]
pub struct LoginResponse {
    pub success: bool,
    pub session_id: Option<Uuid>,
    pub player_id: Option<Uuid>,
    pub error: Option<String>,
}

#[derive(Debug, serde::Serialize, serde::Deserialize, Clone)]
pub struct RegisterRequest {
    pub username: String,
    pub password: String,
}

#[derive(Debug, serde::Serialize, serde::Deserialize, Clone)]
pub struct RegisterResponse {
    pub success: bool,
    pub error: Option<String>,
}

// ─── Re-export PhaseType for use in message payloads ───────────────
pub use crate::game_logic::phase_machine::PhaseType;

// ─── Phase 9: Standardized Payloads ────────────────────────────────

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct StartGameRequest {
    pub room_id: Uuid,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CastVoteRequest {
    pub room_id: Uuid,
    pub target_id: Uuid,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct NightActionRequest {
    pub room_id: Uuid,
    pub action_type: crate::game_logic::roles::SkillType,
    pub target_id: Option<Uuid>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ChatMessageRequest {
    pub room_id: Uuid,
    pub message_text: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ServerResponse {
    pub success: bool,
    pub error: Option<String>,
}

// ─── New Payload Structs (Task 3) ───────────────────────────────────

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ReconnectRequest {
    pub session_id: Uuid,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RoleInfo {
    pub role_code: String,
    pub role_name: String,
    pub faction: String,
    pub description: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ReconnectResponse {
    pub success: bool,
    pub room_id: Option<Uuid>,
    pub phase: Option<PhaseType>,
    pub day_number: Option<u32>,
    pub phase_remaining_secs: Option<u32>,
    pub is_alive: Option<bool>,
    pub role: Option<RoleInfo>,
    pub error: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct QuickJoinRequest {
    pub player_id: Uuid,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct QuickJoinResponse {
    pub room_id: Uuid,
    pub current_players: u32,
    pub lobby_remaining_secs: u32,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CreateRoomRequest {
    pub room_name: String,
    pub is_public: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CreateRoomResponse {
    pub success: bool,
    pub room_id: Option<Uuid>,
    pub error: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct JoinRoomRequest {
    pub room_id: Uuid,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct JoinRoomResponse {
    pub success: bool,
    pub room_id: Uuid,
    pub role_code: String,
    pub role_name: String,
    pub faction: String,
    pub description: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct HeartbeatPayload {
    pub timestamp: u64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ErrorPayload {
    pub message: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct InvitePlayerRequest {
    pub target_username: String,
    pub room_id: Uuid,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GameInviteReceived {
    pub from_username: String,
    pub room_id: Uuid,
    pub room_name: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LeaveRoomRequest {
    pub room_id: Uuid,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ParticipantInfoDto {
    pub player_id: Uuid,
    pub username: String,
    pub is_alive: bool,
    pub seat_number: i32,
    pub is_online: bool,
}

impl From<&crate::game_logic::state::ParticipantInfo> for ParticipantInfoDto {
    fn from(p: &crate::game_logic::state::ParticipantInfo) -> Self {
        Self {
            player_id: p.model.player_id,
            username: p.username.clone(),
            is_alive: p.model.is_alive,
            seat_number: p.model.seat_number,
            is_online: true, // simplified for sync
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RoomStateSync {
    pub room_id: Uuid,
    pub participants: Vec<ParticipantInfoDto>,
    pub alive_count: u32,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ChatEntry {
    pub sender_username: String,
    pub message_text: String,
    pub timestamp: u64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ChatBroadcast {
    pub sender_id: Uuid,
    pub message_text: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GamePhaseChange {
    pub phase: PhaseType,
    pub day_number: u32,
    pub duration_secs: u32,
    pub server_timestamp: u64,
    pub night_chat_history: Option<Vec<ChatEntry>>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DeathInfo {
    pub player_id: Uuid,
    pub username: String,
    pub role_name: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum GameEventType {
    NightResolution,
    VoteResult,
    GameOver,
    AvengerVengeance,
    NemesisWin,
    FoolWin,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GameEvent {
    pub event_type: GameEventType,
    pub deaths: Vec<DeathInfo>,
    pub winner_faction: Option<String>,
    pub extra: Option<serde_json::Value>,
}

/// Maximum message size (10MB) - Adjusted for potential game data lists
pub const MAX_MESSAGE_SIZE: usize = 10_485_760;

/// CRC16 algorithm (CCITT/IBM-SDLC)
const CRC_ALGO: Crc<u16> = Crc::<u16>::new(&CRC_16_IBM_SDLC);

/// Message structure with type and payload
#[derive(Debug, Clone)]
pub struct Message {
    pub msg_type: MessageType,
    pub payload: Bytes,
}

/// Message types for the game protocol
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[repr(u8)]
pub enum MessageType {
    // Authentication (0x01-0x0F)
    LoginRequest = 0x01,
    LoginResponse = 0x02,
    RegisterRequest = 0x03,
    RegisterResponse = 0x04,
    ReconnectRequest = 0x05,
    ReconnectResponse = 0x06,
    GetGameData = 0x0F, // New: Direct fetch for roles/skills

    // Room Management (0x10-0x2F)
    RoomListRequest = 0x10,
    RoomListResponse = 0x11,
    CreateRoomRequest = 0x12,
    CreateRoomResponse = 0x13,
    JoinRoomRequest = 0x14,
    JoinRoomResponse = 0x15,
    LeaveRoomRequest = 0x16,
    QuickJoinRequest = 0x17,
    QuickJoinResponse = 0x18,
    InvitePlayer = 0x1A,
    GameInviteReceived = 0x1B,
    StartGame = 0x19,     // Official StartGame
    RoomStateSync = 0x20, // Broadcast

    // Game Actions (0x30-0x4F)
    ChatMessage = 0x30,
    CastVote = 0x31,
    NightAction = 0x32,     // Phase 9: Use night skills
    GamePhaseChange = 0x33, // Phase 9: Day/Night transition
    GameEvent = 0x34,       // Broadcast (Eliminated, Win)

    // Fast Signals (UDP) (0x50-0x6F)
    Heartbeat = 0x50,
    LatencyPing = 0x51,
    PositionSync = 0x60, // Optional future use

    // Control (0x70-0xFF)
    Disconnect = 0x70,
    Error = 0xFF,
    Unknown = 0x00,
}

impl MessageType {
    pub fn from_byte(byte: u8) -> Result<Self> {
        match byte {
            0x01 => Ok(MessageType::LoginRequest),
            0x02 => Ok(MessageType::LoginResponse),
            0x03 => Ok(MessageType::RegisterRequest),
            0x04 => Ok(MessageType::RegisterResponse),
            0x05 => Ok(MessageType::ReconnectRequest),
            0x06 => Ok(MessageType::ReconnectResponse),
            0x0F => Ok(MessageType::GetGameData),
            0x10 => Ok(MessageType::RoomListRequest),
            0x11 => Ok(MessageType::RoomListResponse),
            0x12 => Ok(MessageType::CreateRoomRequest),
            0x13 => Ok(MessageType::CreateRoomResponse),
            0x14 => Ok(MessageType::JoinRoomRequest),
            0x15 => Ok(MessageType::JoinRoomResponse),
            0x16 => Ok(MessageType::LeaveRoomRequest),
            0x17 => Ok(MessageType::QuickJoinRequest),
            0x18 => Ok(MessageType::QuickJoinResponse),
            0x1A => Ok(MessageType::InvitePlayer),
            0x1B => Ok(MessageType::GameInviteReceived),
            0x19 => Ok(MessageType::StartGame),
            0x20 => Ok(MessageType::RoomStateSync), 
            0x30 => Ok(MessageType::ChatMessage),
            0x31 => Ok(MessageType::CastVote),
            0x32 => Ok(MessageType::NightAction),
            0x33 => Ok(MessageType::GamePhaseChange),
            0x34 => Ok(MessageType::GameEvent),
            0x50 => Ok(MessageType::Heartbeat),
            0x51 => Ok(MessageType::LatencyPing),
            0x60 => Ok(MessageType::PositionSync),
            0x70 => Ok(MessageType::Disconnect),
            0xFF => Ok(MessageType::Error),
            0x00 => Ok(MessageType::Unknown),
            _ => Err(anyhow!("Unknown message type: 0x{:02X}", byte)),
        }
    }
}

impl Message {
    /// Create a new message
    pub fn new(msg_type: MessageType, payload: Bytes) -> Self {
        Self { msg_type, payload }
    }

    /// Create a message from JSON payload (Legacy support)
    pub fn from_json<T: serde::Serialize>(msg_type: MessageType, data: &T) -> Result<Self> {
        let json = serde_json::to_vec(data)?;
        Ok(Self {
            msg_type,
            payload: Bytes::from(json),
        })
    }

    /// Create a message using Bincode (Preferred for Academic Network requirements)
    pub fn from_binary<T: serde::Serialize>(msg_type: MessageType, data: &T) -> Result<Self> {
        let binary = bincode::serialize(data)?;
        Ok(Self {
            msg_type,
            payload: Bytes::from(binary),
        })
    }

    /// Parse JSON payload
    pub fn parse_json<T: serde::de::DeserializeOwned>(&self) -> Result<T> {
        Ok(serde_json::from_slice(&self.payload)?)
    }

    /// Parse Binary payload (Bincode)
    pub fn parse_binary<T: serde::de::DeserializeOwned>(&self) -> Result<T> {
        Ok(bincode::deserialize(&self.payload)?)
    }

    /// Serialize message to bytes using the Areyoughost Protocol
    /// Format: [Magic(2)][Type(1)][Len(4)][Payload(N)][CRC16(2)]
    pub fn to_bytes(&self) -> Bytes {
        let total_size = 2 + 1 + 4 + self.payload.len() + 2;
        let mut buf = BytesMut::with_capacity(total_size);

        // Header: [Magic(2)][Version(1)][Type(1)][Len(4)]
        buf.put_slice(&MAGIC_BYTES);
        buf.put_u8(PROTOCOL_VERSION);
        buf.put_u8(self.msg_type as u8);
        buf.put_u32(self.payload.len() as u32);

        // Payload
        buf.put_slice(&self.payload);

        // Calculate CRC over Header (excluding magic) + Payload
        let mut check_buf = Vec::with_capacity(6 + self.payload.len());
        check_buf.push(PROTOCOL_VERSION);
        check_buf.push(self.msg_type as u8);
        check_buf.extend_from_slice(&(self.payload.len() as u32).to_be_bytes());
        check_buf.extend_from_slice(&self.payload);
        
        let checksum = CRC_ALGO.checksum(&check_buf);
        buf.put_u16(checksum);

        buf.freeze()
    }

    /// Deserialize message from bytes
    pub fn from_bytes(mut data: Bytes) -> Result<Self> {
        // Verify Header: [Magic(2)][Version(1)][Type(1)][Len(4)]
        if data.len() < 10 {
            return Err(anyhow!("Message too small: minimum 10 bytes expected (v1)"));
        }
        
        if data[0..2] != MAGIC_BYTES {
            return Err(anyhow!("Invalid Magic Bytes: 0x{:02X} 0x{:02X}", data[0], data[1]));
        }
        data.advance(2);

        let version = data.get_u8();
        if version != PROTOCOL_VERSION {
            return Err(anyhow!("Invalid Protocol Version: expected 1, got {}", version));
        }

        let type_byte = data.get_u8();
        let payload_len = data.get_u32() as usize;

        if payload_len > MAX_MESSAGE_SIZE {
            return Err(anyhow!("Payload too large: {} bytes", payload_len));
        }

        if data.len() < payload_len + 2 {
            return Err(anyhow!("Incomplete message: expected {} + 2 bytes, got {}", payload_len, data.len()));
        }

        // Read Payload
        let payload = data.copy_to_bytes(payload_len);

        // Verify CRC
        let expected_crc = data.get_u16();
        
        let mut check_buf = Vec::with_capacity(6 + payload_len);
        check_buf.push(version);
        check_buf.push(type_byte);
        check_buf.extend_from_slice(&(payload_len as u32).to_be_bytes());
        check_buf.extend_from_slice(&payload);
        
        let actual_crc = CRC_ALGO.checksum(&check_buf);
        
        if expected_crc != actual_crc {
            return Err(anyhow!("CRC Checksum Failed: expected 0x{:04X}, got 0x{:04X}", expected_crc, actual_crc));
        }

        let msg_type = MessageType::from_byte(type_byte)?;

        Ok(Self { msg_type, payload })
    }

    /// Get total message size in bytes
    pub fn size(&self) -> usize {
        10 + self.payload.len()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_protocol_framing() {
        let payload = Bytes::from("AreYouGhost_Protocol_Test");
        let msg = Message::new(MessageType::ChatMessage, payload.clone());

        let bytes = msg.to_bytes();
        assert_eq!(bytes[0..2], MAGIC_BYTES);
        
        let decoded = Message::from_bytes(bytes).unwrap();
        assert_eq!(decoded.msg_type, MessageType::ChatMessage);
        assert_eq!(decoded.payload, payload);
    }
}
