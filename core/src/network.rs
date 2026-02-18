//! # Network Module - Socket-Level Implementation
//!
//! This module implements raw TCP/UDP socket programming with bandwidth control
//! for the multiplayer game. Uses simple message framing without custom packet headers.
//!
//! ## Architecture
//!
//! - **message**: Simple length-prefixed message format
//! - **tcp_server**: Raw TCP server with async I/O
//! - **tcp_client**: Raw TCP client
//! - **bandwidth**: Bandwidth throttling (token bucket)
//!
//! ## Usage
//!
//! ```rust,ignore
//! use crate::network::{TcpServer, TcpClient};
//!
//! # async fn example() -> anyhow::Result<()> {
//! // Server
//! let server = TcpServer::bind("0.0.0.0:8080").await?;
//! server.set_bandwidth_limit(1_000_000).await; // 1 MB/s
//!
//! // Client
//! let client = TcpClient::connect("127.0.0.1:8080").await?;
//! // client.send_message(message).await?; // message not defined in example
//! # Ok(())
//! # }
//! ```

pub mod bandwidth;
#[cfg(test)]
pub mod benchmarks;
pub mod message;
pub mod tcp_client;
pub mod tcp_server;

pub use bandwidth::BandwidthLimiter;
pub use message::{Message, MessageType};
pub use tcp_client::TcpClient;
pub use tcp_server::TcpServer;

/// Network statistics for monitoring
#[derive(Debug, Clone)]
pub struct NetworkStats {
    pub bytes_sent: u64,
    pub bytes_received: u64,
    pub messages_sent: u64,
    pub messages_received: u64,
    pub active_connections: usize,
    pub bandwidth_usage: f64, // bytes per second
}
