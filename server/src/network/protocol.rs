//! Custom Byte Protocol Definition
//! Defines the structure for TCP Streams and UDP Datagrams.

/// Command codes representing the action of a packet. (1 Byte in Header)
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
#[repr(u8)]
pub enum MessageType {
    // Auth & Room (TCP)
    LoginRequest = 0x01,
    LoginResponse = 0x02,
    RoomListRequest = 0x10,
    RoomListResponse = 0x11,
    CreateRoomRequest = 0x12,
    CreateRoomResponse = 0x13,
    JoinRoomRequest = 0x14,
    JoinRoomResponse = 0x15,
    LeaveRoomRequest = 0x16,
    RoomStateSync = 0x20, // Broadcast
    
    // Game Actions (TCP)
    ChatMessage = 0x30, // Broadcast
    CastVote = 0x31,
    GameEvent = 0x32, // Broadcast (Eliminated, Win, Phase Change)
    
    // Fast Signals (UDP)
    Heartbeat = 0x50,
    LatencyPing = 0x51,
    PositionSync = 0x60, // Optional future use
    
    // Control (TCP)
    Error = 0xFF,
    Unknown = 0x00,
}

impl From<u8> for MessageType {
    fn from(value: u8) -> Self {
        match value {
            0x01 => MessageType::LoginRequest,
            0x02 => MessageType::LoginResponse,
            0x10 => MessageType::RoomListRequest,
            0x11 => MessageType::RoomListResponse,
            0x12 => MessageType::CreateRoomRequest,
            0x13 => MessageType::CreateRoomResponse,
            0x14 => MessageType::JoinRoomRequest,
            0x15 => MessageType::JoinRoomResponse,
            0x16 => MessageType::LeaveRoomRequest,
            0x20 => MessageType::RoomStateSync,
            0x30 => MessageType::ChatMessage,
            0x31 => MessageType::CastVote,
            0x32 => MessageType::GameEvent,
            0x50 => MessageType::Heartbeat,
            0x51 => MessageType::LatencyPing,
            0x60 => MessageType::PositionSync,
            0xFF => MessageType::Error,
            _ => MessageType::Unknown,
        }
    }
}

/// A generic structure to hold a fully parsed packet.
#[derive(Debug, Clone)]
pub struct DecodedPacket {
    pub msg_type: MessageType,
    pub payload: Vec<u8>,
}

/// UDP framing specifically requires extracting the 16-byte UUID of the sender
#[derive(Debug, Clone)]
pub struct DecodedUdpPacket {
    pub msg_type: MessageType,
    pub sender_id: String, // Parsed from 16 bytes
    pub payload: Vec<u8>,
}
