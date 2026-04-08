//! # TCP Client Module
//!
//! Raw TCP client implementation with bandwidth control and protocol framing.

use std::sync::Arc;
use tokio::sync::Mutex;
use tokio::net::TcpStream;
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use bytes::Bytes;
use crate::network::Message;
use crate::network::BandwidthLimiter;

/// TCP client with bandwidth control and protocol framing (Clonable & Async-Safe)
#[derive(Clone)]
pub struct TcpClient {
    stream: Arc<Mutex<TcpStream>>,
    bandwidth_limiter: BandwidthLimiter,
}

impl TcpClient {
    /// Connect to a server
    pub async fn connect(addr: &str) -> anyhow::Result<Self> {
        let stream = TcpStream::connect(addr).await
            .map_err(|e| anyhow::anyhow!("Failed to connect to {}: {}", addr, e))?;
            
        Ok(Self {
            stream: Arc::new(Mutex::new(stream)),
            bandwidth_limiter: BandwidthLimiter::new(10_000_000), // 10 MB/s default
        })
    }

    /// Send a protocol message
    pub async fn send(&mut self, msg: &Message) -> anyhow::Result<()> {
        let bytes = msg.to_bytes();
        let mut stream = self.stream.lock().await;
        (&mut *stream).write_all(&bytes).await
            .map_err(|e| anyhow::anyhow!("Failed to write to stream: {}", e))?;
        (&mut *stream).flush().await
            .map_err(|e| anyhow::anyhow!("Failed to flush stream: {}", e))?;
        Ok(())
    }

    /// Receive a protocol message (blocking read for header + payload)
    pub async fn receive(&mut self) -> anyhow::Result<Message> {
        let mut stream = self.stream.lock().await;

        // 1. Read Header (Magic[2] + Type[1] + Len[4] = 7 bytes)
        let mut header = [0u8; 7];
        (&mut *stream).read_exact(&mut header).await
            .map_err(|e| anyhow::anyhow!("Failed to read header: {}", e))?;
        
        let payload_len = u32::from_be_bytes([header[3], header[4], header[5], header[6]]) as usize;
        
        // 2. Read Payload + CRC (payload_len + 2 bytes)
        let mut remaining = vec![0u8; payload_len + 2];
        (&mut *stream).read_exact(&mut remaining).await
            .map_err(|e| anyhow::anyhow!("Failed to read payload: {}", e))?;
        
        // 3. Reconstruct for Verification
        let mut full_bytes = Vec::with_capacity(7 + payload_len + 2);
        full_bytes.extend_from_slice(&header);
        full_bytes.extend_from_slice(&remaining);
        
        Message::from_bytes(Bytes::from(full_bytes))
    }
    /// Set bandwidth limit
    pub async fn set_bandwidth_limit(&self, bytes_per_sec: u64) {
        self.bandwidth_limiter.set_rate(bytes_per_sec).await;
    }
}
