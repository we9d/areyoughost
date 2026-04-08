//! # TCP Server Module
//!
//! Raw TCP server with split-stream per-connection tasks and a DashMap connection registry.
//!
//! ## Architecture
//!
//! Each accepted connection is split into `OwnedReadHalf` / `OwnedWriteHalf`.
//! Two Tokio tasks are spawned per connection:
//!
//! - **Read Task** — accumulates bytes, parses complete Areyoughost frames, forwards to Dispatcher.
//! - **Write Task** — drains an `mpsc::UnboundedReceiver<Bytes>` and writes to the socket.
//!
//! The `UnboundedSender<Bytes>` end is stored in the `DashMap` registry keyed by a temporary
//! `PlayerId` (UUID string).  When either task terminates the sibling is cancelled and the
//! registry entry is removed.

use anyhow::Result;
use bytes::{Bytes, BytesMut, BufMut};
use dashmap::DashMap;
use std::sync::Arc;
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::{TcpListener, TcpStream};
use tokio::sync::{mpsc, RwLock};
use tracing::{error, info, warn};
use uuid::Uuid;

use crate::game_logic::state::AppState;
use crate::network::message::{Message, MAX_MESSAGE_SIZE, MAGIC_BYTES};
use super::dispatcher::Dispatcher;

/// TCP server with split-stream connection handling and a DashMap connection registry.
pub struct TcpServer {
    listener: TcpListener,
    app_state: Arc<RwLock<AppState>>,
    registry: Arc<DashMap<Uuid, mpsc::UnboundedSender<Bytes>>>,
}

impl TcpServer {
    /// Bind to `addr` and construct a `TcpServer`.
    pub async fn bind(addr: &str, app_state: Arc<RwLock<AppState>>) -> Result<Self> {
        let listener = TcpListener::bind(addr).await?;
        info!("TCP server listening on {}", addr);
        Ok(Self {
            listener,
            app_state,
            registry: Arc::new(DashMap::new()),
        })
    }

    /// Return a clone of the shared connection registry.
    pub fn registry(&self) -> Arc<DashMap<Uuid, mpsc::UnboundedSender<Bytes>>> {
        Arc::clone(&self.registry)
    }

    /// Accept loop — spawns `handle_connection` for every incoming TCP stream.
    pub async fn run(&self) {
        loop {
            match self.listener.accept().await {
                Ok((stream, addr)) => {
                    info!("New connection from {}", addr);
                    let app_state = Arc::clone(&self.app_state);
                    let registry = Arc::clone(&self.registry);
                    tokio::spawn(async move {
                        Self::handle_connection(stream, app_state, registry).await;
                    });
                }
                Err(e) => {
                    error!("Accept error: {}", e);
                }
            }
        }
    }

    /// Handle a single TCP connection:
    /// 1. Split into read/write halves.
    /// 2. Create an unbounded channel for outbound bytes.
    /// 3. Register the sender in the registry under a temporary UUID PlayerId.
    /// 4. Spawn Read Task + Write Task.
    /// 5. On either task exit: cancel sibling, remove from registry.
    async fn handle_connection(
        stream: TcpStream,
        app_state: Arc<RwLock<AppState>>,
        registry: Arc<DashMap<Uuid, mpsc::UnboundedSender<Bytes>>>,
    ) {
        let player_id = Uuid::new_v4();
        let (read_half, write_half) = stream.into_split();

        let (tx, rx) = mpsc::unbounded_channel::<Bytes>();
        registry.insert(player_id.clone(), tx);

        let dispatcher = Dispatcher::new(Arc::clone(&app_state), Arc::clone(&registry));

        let pid_read = player_id.clone();
        let pid_write = player_id.clone();
        let registry_read = Arc::clone(&registry);
        let registry_write = Arc::clone(&registry);

        // ── Read Task ──────────────────────────────────────────────────────────
        let mut read_handle: tokio::task::JoinHandle<()> = tokio::spawn(async move {
            Self::read_task(read_half, dispatcher, pid_read, registry_read).await
        });

        // ── Write Task ─────────────────────────────────────────────────────────
        let mut write_handle: tokio::task::JoinHandle<()> = tokio::spawn(async move {
            Self::write_task(write_half, rx, pid_write, registry_write).await
        });

        // Wait for either task to finish, then abort the other.
        tokio::select! {
            _ = &mut read_handle => {
                write_handle.abort();
            }
            _ = &mut write_handle => {
                read_handle.abort();
            }
        }

        // Final cleanup — remove from registry (may already be gone).
        registry.remove(&player_id);
        info!("Connection cleaned up for player {}", player_id);
    }

    /// Read Task: accumulates bytes from `OwnedReadHalf`, parses complete Areyoughost frames,
    /// and forwards each `Message` to the `Dispatcher`.
    ///
    /// Exits on:
    /// - EOF / socket error
    /// - Invalid magic bytes
    /// - CRC mismatch
    /// - Payload > 10 MB
    async fn read_task(
        mut read_half: tokio::net::tcp::OwnedReadHalf,
        dispatcher: Dispatcher,
        player_id: Uuid,
        registry: Arc<DashMap<Uuid, mpsc::UnboundedSender<Bytes>>>,
    ) {
        let mut buf = BytesMut::with_capacity(4096);

        loop {
            // Read more bytes from the socket.
            let mut tmp = [0u8; 4096];
            let n = match read_half.read(&mut tmp).await {
                Ok(0) => {
                    info!("Player {} disconnected (EOF)", player_id);
                    break;
                }
                Ok(n) => n,
                Err(e) => {
                    warn!("Read error for player {}: {}", player_id, e);
                    break;
                }
            };
            buf.put_slice(&tmp[..n]);

            // Drain all complete frames from the buffer.
            loop {
                // Need at least the 9-byte header to know payload length.
                if buf.len() < 9 {
                    break;
                }

                // Validate magic bytes early (before we know the full frame).
                if buf[0] != MAGIC_BYTES[0] || buf[1] != MAGIC_BYTES[1] {
                    error!(
                        "Invalid magic bytes from player {}: 0x{:02X} 0x{:02X}",
                        player_id, buf[0], buf[1]
                    );
                    registry.remove(&player_id);
                    return;
                }

                // Parse payload length from bytes 3–6 (big-endian u32).
                let payload_len = u32::from_be_bytes([buf[3], buf[4], buf[5], buf[6]]) as usize;

                if payload_len > MAX_MESSAGE_SIZE {
                    error!(
                        "Payload too large ({} bytes) from player {}",
                        payload_len, player_id
                    );
                    registry.remove(&player_id);
                    return;
                }

                let frame_len = 9 + payload_len; // header(9) + payload + CRC(2) already in 9
                // Actually: 2(magic) + 1(type) + 4(len) + payload_len + 2(crc) = 9 + payload_len
                if buf.len() < frame_len {
                    // Not enough bytes yet — wait for more.
                    break;
                }

                // Slice exactly one frame.
                let frame = buf.split_to(frame_len).freeze();

                match Message::from_bytes(frame) {
                    Ok(msg) => {
                        if let Err(e) = dispatcher.handle(player_id, msg).await {
                            warn!("Dispatcher error for player {}: {}", player_id, e);
                        }
                    }
                    Err(e) => {
                        error!("Frame parse error for player {}: {}", player_id, e);
                        registry.remove(&player_id);
                        return;
                    }
                }
            }
        }

        registry.remove(&player_id);
    }

    /// Write Task: drains `UnboundedReceiver<Bytes>` and writes each chunk to `OwnedWriteHalf`.
    async fn write_task(
        mut write_half: tokio::net::tcp::OwnedWriteHalf,
        mut rx: mpsc::UnboundedReceiver<Bytes>,
        player_id: Uuid,
        registry: Arc<DashMap<Uuid, mpsc::UnboundedSender<Bytes>>>,
    ) {
        while let Some(bytes) = rx.recv().await {
            if let Err(e) = write_half.write_all(&bytes).await {
                warn!("Write error for player {}: {}", player_id, e);
                break;
            }
        }
        registry.remove(&player_id);
    }
}
