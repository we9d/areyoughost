//! # TCP Client Module
//!
//! Raw TCP client implementation with bandwidth control

use tokio::net::TcpStream;
use anyhow::Result;

use super::bandwidth::BandwidthLimiter;
use super::message::Message;

/// TCP client with bandwidth control
#[allow(dead_code)]
pub struct TcpClient {
    stream: TcpStream,
    bandwidth_limiter: BandwidthLimiter,
}

impl TcpClient {
    /// Connect to a server
    pub async fn connect(addr: &str) -> Result<Self> {
        let stream = TcpStream::connect(addr).await?;
        Ok(Self {
            stream,
            bandwidth_limiter: BandwidthLimiter::new(1_000_000), // 1 MB/s default
        })
    }

    /// Set bandwidth limit
    pub async fn set_bandwidth_limit(&self, bytes_per_sec: u64) {
        self.bandwidth_limiter.set_rate(bytes_per_sec).await;
    }
}
