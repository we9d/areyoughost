//! Custom Byte Protocol Definition
//! Defines the structure for TCP Streams and UDP Datagrams.

pub use areyoughost_core::network::message::MessageType;

/// A generic structure to hold a fully parsed TCP packet.
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
