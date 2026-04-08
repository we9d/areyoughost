use tokio::net::UdpSocket;
use tracing::{info, error};
use std::sync::Arc;
use crate::state::manager::AppState;
use areyoughost_core::network::message::MessageType;

pub async fn start_udp_server(_state: Arc<AppState>, port: u16) {
    let addr = format!("0.0.0.0:{}", port);
    match UdpSocket::bind(&addr).await {
        Ok(socket) => {
            info!("UDP Protocol Server listening on {}", addr);
            let mut buf = vec![0u8; 65535]; // Max UDP packet size

            loop {
                match socket.recv_from(&mut buf).await {
                    Ok((len, peer_addr)) => {
                        // Frame: [Type (1B) | PlayerID UUID (16B) | Payload (NB)]
                        if len < 17 {
                            error!("UDP packet too small from {}", peer_addr);
                            continue;
                        }

                        let msg_type = MessageType::from_byte(buf[0]).unwrap_or(MessageType::Error);
                        
                        // Extract exactly 16 bytes for UUID
                        let uuid_bytes: [u8; 16] = buf[1..17].try_into().unwrap_or_default();
                        let sender_id = uuid::Uuid::from_bytes(uuid_bytes).to_string();

                        let payload = &buf[17..len];

                        info!("UDP Recv [{}]: Type={:?} Sender={} Len={}", peer_addr, msg_type, sender_id, payload.len());

                        // Dispatch Heartbeats
                        if msg_type == MessageType::Heartbeat {
                            // TODO: Heartbeat update timestamp logic
                        }
                    }
                    Err(e) => {
                        error!("UDP recv_from error: {}", e);
                    }
                }
            }
        }
        Err(e) => error!("Failed to bind UDP server: {}", e),
    }
}
