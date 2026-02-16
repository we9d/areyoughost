//! # Message Module - Simple Length-Prefixed Messages
//!
//! Implements a simple message framing protocol:
//! [4-byte length][1-byte type][payload]

use anyhow::{anyhow, Result};
use bytes::{Buf, BufMut, Bytes, BytesMut};
use serde::{Deserialize, Serialize};

/// Maximum message size (1MB)
pub const MAX_MESSAGE_SIZE: usize = 1_048_576;

/// Message structure with type and payload
#[derive(Debug, Clone)]
pub struct Message {
    pub msg_type: MessageType,
    pub payload: Bytes,
}

/// Message types for the game protocol
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
#[repr(u8)]
pub enum MessageType {
    // Authentication (0x01-0x0F)
    LoginRequest = 0x01,
    LoginResponse = 0x02,
    RegisterRequest = 0x03,
    RegisterResponse = 0x04,

    // Room Management (0x10-0x2F)
    RoomListRequest = 0x10,
    RoomListResponse = 0x11,
    CreateRoomRequest = 0x12,
    CreateRoomResponse = 0x13,
    JoinRoomRequest = 0x14,
    JoinRoomResponse = 0x15,
    LeaveRoom = 0x16,

    // Game Actions (0x30-0x4F)
    ChatMessage = 0x30,
    CastVote = 0x31,
    GameStateUpdate = 0x32,
    PlayerEliminated = 0x33,
    GameEnd = 0x34,

    // Control (0x50-0xFF)
    Heartbeat = 0x50,
    Disconnect = 0x51,
    Error = 0x52,
}

impl MessageType {
    pub fn from_byte(byte: u8) -> Result<Self> {
        match byte {
            0x01 => Ok(MessageType::LoginRequest),
            0x02 => Ok(MessageType::LoginResponse),
            0x03 => Ok(MessageType::RegisterRequest),
            0x04 => Ok(MessageType::RegisterResponse),
            0x10 => Ok(MessageType::RoomListRequest),
            0x11 => Ok(MessageType::RoomListResponse),
            0x12 => Ok(MessageType::CreateRoomRequest),
            0x13 => Ok(MessageType::CreateRoomResponse),
            0x14 => Ok(MessageType::JoinRoomRequest),
            0x15 => Ok(MessageType::JoinRoomResponse),
            0x16 => Ok(MessageType::LeaveRoom),
            0x30 => Ok(MessageType::ChatMessage),
            0x31 => Ok(MessageType::CastVote),
            0x32 => Ok(MessageType::GameStateUpdate),
            0x33 => Ok(MessageType::PlayerEliminated),
            0x34 => Ok(MessageType::GameEnd),
            0x50 => Ok(MessageType::Heartbeat),
            0x51 => Ok(MessageType::Disconnect),
            0x52 => Ok(MessageType::Error),
            _ => Err(anyhow!("Unknown message type: {}", byte)),
        }
    }
}

impl Message {
    /// Create a new message
    pub fn new(msg_type: MessageType, payload: Bytes) -> Self {
        Self { msg_type, payload }
    }

    /// Create a message from JSON payload
    pub fn from_json<T: Serialize>(msg_type: MessageType, data: &T) -> Result<Self> {
        let json = serde_json::to_vec(data)?;
        Ok(Self {
            msg_type,
            payload: Bytes::from(json),
        })
    }

    /// Parse JSON payload
    pub fn parse_json<T: for<'de> Deserialize<'de>>(&self) -> Result<T> {
        Ok(serde_json::from_slice(&self.payload)?)
    }

    /// Serialize message to bytes
    /// Format: [4-byte length][1-byte type][payload]
    pub fn to_bytes(&self) -> Bytes {
        let total_len = 5 + self.payload.len(); // 4 (length) + 1 (type) + payload
        let mut buf = BytesMut::with_capacity(total_len);

        // Write length (excluding the length field itself)
        buf.put_u32((1 + self.payload.len()) as u32);

        // Write message type
        buf.put_u8(self.msg_type as u8);

        // Write payload
        buf.put_slice(&self.payload);

        buf.freeze()
    }

    /// Deserialize message from bytes
    pub fn from_bytes(mut data: Bytes) -> Result<Self> {
        if data.len() < 5 {
            return Err(anyhow!("Message too small: {} bytes", data.len()));
        }

        // Read length
        let length = data.get_u32() as usize;

        if length > MAX_MESSAGE_SIZE {
            return Err(anyhow!("Message too large: {} bytes", length));
        }

        if data.len() < length {
            return Err(anyhow!("Incomplete message: expected {}, got {}", length, data.len()));
        }

        // Read message type
        let msg_type = MessageType::from_byte(data.get_u8())?;

        // Read payload
        let payload = data;

        Ok(Self { msg_type, payload })
    }

    /// Get message size in bytes
    pub fn size(&self) -> usize {
        5 + self.payload.len()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_message_serialization() {
        let payload = Bytes::from("Hello, World!");
        let msg = Message::new(MessageType::ChatMessage, payload.clone());

        let bytes = msg.to_bytes();
        let decoded = Message::from_bytes(bytes).unwrap();

        assert_eq!(decoded.msg_type, MessageType::ChatMessage);
        assert_eq!(decoded.payload, payload);
    }

    #[test]
    fn test_json_message() {
        #[derive(Serialize, Deserialize, PartialEq, Debug)]
        struct TestData {
            username: String,
            password: String,
        }

        let data = TestData {
            username: "player1".to_string(),
            password: "secret".to_string(),
        };

        let msg = Message::from_json(MessageType::LoginRequest, &data).unwrap();
        let decoded: TestData = msg.parse_json().unwrap();

        assert_eq!(decoded, data);
    }
}
