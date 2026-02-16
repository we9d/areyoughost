//! # TCP Server Module
//!
//! Raw TCP server implementation with bandwidth control

use anyhow::Result;
use std::collections::HashMap;
use std::net::SocketAddr;
use std::sync::Arc;
use tokio::net::{TcpListener, TcpStream};
use tokio::sync::Mutex;

use super::bandwidth::BandwidthLimiter;

/// TCP server with bandwidth control
#[allow(dead_code)]
pub struct TcpServer {
    listener: TcpListener,
    connections: Arc<Mutex<HashMap<SocketAddr, TcpStream>>>,
    bandwidth_limiter: BandwidthLimiter,
}

impl TcpServer {
    /// Bind to an address
    pub async fn bind(addr: &str) -> Result<Self> {
        let listener = TcpListener::bind(addr).await?;
        Ok(Self {
            listener,
            connections: Arc::new(Mutex::new(HashMap::new())),
            bandwidth_limiter: BandwidthLimiter::new(1_000_000), // 1 MB/s default
        })
    }

    /// Set bandwidth limit
    pub async fn set_bandwidth_limit(&self, bytes_per_sec: u64) {
        self.bandwidth_limiter.set_rate(bytes_per_sec).await;
    }

    /// Accept incoming connections
    pub async fn accept(&self) -> Result<(TcpStream, SocketAddr)> {
        let (stream, addr) = self.listener.accept().await?;
        Ok((stream, addr))
    }
}
