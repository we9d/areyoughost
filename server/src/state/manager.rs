use dashmap::DashMap;
use std::collections::VecDeque;
use tokio::sync::{Mutex, mpsc};
use axum::extract::ws::Message;

pub type PlayerId = String;
pub type RoomId = String;

#[derive(Clone, Debug)]
pub struct PlayerInfo {
    pub player_id: PlayerId,
    pub username: String,
    pub is_ready: bool,
    pub is_host: bool,
}

#[derive(Clone, Debug)]
pub struct Room {
    pub room_id: RoomId,
    pub players: Vec<PlayerInfo>,
    pub max_players: usize,
    pub is_public: bool,
    pub status: String, // "waiting" | "playing"
}

pub struct GameRoomManager {
    pub rooms: DashMap<RoomId, Room>,
    pub connections: DashMap<PlayerId, mpsc::UnboundedSender<Message>>,
    pub player_rooms: DashMap<PlayerId, RoomId>,

    // FIFO queue (important: use Mutex<VecDeque> not just DashMap)
    pub queue: Mutex<VecDeque<PlayerId>>,
}

impl GameRoomManager {
    pub fn new() -> Self {
        Self {
            rooms: DashMap::new(),
            connections: DashMap::new(),
            player_rooms: DashMap::new(),
            queue: Mutex::new(VecDeque::new()),
        }
    }

    /// Join the matchmaking queue and try to match players
    pub async fn join_queue(&self, player_id: String, username: String) -> Option<RoomId> {
        // Add to queue
        {
            let mut queue = self.queue.lock().await;
            if !queue.contains(&player_id) {
                queue.push_back(player_id.clone());
                tracing::info!("Player {} added to queue. Queue size: {}", player_id, queue.len());
            }
        }

        // Try to match players
        self.try_match_players(2).await
    }

    /// Try to match players from queue (min_players = 2 by default)
    async fn try_match_players(&self, min_players: usize) -> Option<RoomId> {
        let mut queue = self.queue.lock().await;
        
        if queue.len() >= min_players {
            // Create a new room
            let room_id = format!("room-{}", uuid::Uuid::new_v4());
            let mut players = Vec::new();

            // Take first N players from queue
            for i in 0..min_players.min(queue.len()) {
                if let Some(player_id) = queue.pop_front() {
                    let is_host = i == 0; // First player is host
                    players.push(PlayerInfo {
                        player_id: player_id.clone(),
                        username: format!("Player{}", i + 1), // Will get from connection data
                        is_ready: false,
                        is_host,
                    });
                    self.player_rooms.insert(player_id, room_id.clone());
                }
            }

            let room = Room {
                room_id: room_id.clone(),
                players,
                max_players: 16,
                is_public: true,
                status: "waiting".to_string(),
            };

            self.rooms.insert(room_id.clone(), room);
            tracing::info!("Created room {} with {} players", room_id, min_players);

            Some(room_id)
        } else {
            None
        }
    }

    /// Create a custom room
    pub fn create_room(&self, host_id: String, username: String, max_players: usize) -> RoomId {
        let room_id = format!("room-{}", uuid::Uuid::new_v4());
        
        let players = vec![PlayerInfo {
            player_id: host_id.clone(),
            username,
            is_ready: false,
            is_host: true,
        }];

        let room = Room {
            room_id: room_id.clone(),
            players,
            max_players,
            is_public: true,
            status: "waiting".to_string(),
        };

        self.rooms.insert(room_id.clone(), room.clone());
        self.player_rooms.insert(host_id, room_id.clone());

        tracing::info!("Created custom room {}", room_id);
        room_id
    }

    /// Broadcast a message to all players in a room
    pub fn broadcast_to_room(&self, room_id: &str, message: &str) {
        if let Some(room) = self.rooms.get(room_id) {
            for player in &room.players {
                if let Some(tx) = self.connections.get(&player.player_id) {
                    let _ = tx.send(Message::Text(message.to_string()));
                }
            }
        }
    }

    /// Get room state as JSON
    pub fn get_room_state(&self, room_id: &str) -> Option<serde_json::Value> {
        self.rooms.get(room_id).map(|room| {
            serde_json::json!({
                "roomId": room.room_id,
                "players": room.players.iter().map(|p| serde_json::json!({
                    "playerId": p.player_id,
                    "username": p.username,
                    "isReady": p.is_ready,
                    "isHost": p.is_host,
                })).collect::<Vec<_>>(),
                "maxPlayers": room.max_players,
                "isPublic": room.is_public,
                "status": room.status,
            })
        })
    }
}
