//! # FFI API Module
//!
//! This module provides the FFI (Foreign Function Interface) exports
//! that allow the Flutter frontend to communicate with the Rust backend.
//!
//! All public functions in the `Api` struct are exposed to Flutter via
//! flutter_rust_bridge.
//!
//! **NOTE**: This module has been refactored to use the Dedicated Server (HTTP/WS)
//! instead of a local SQLite database.

use crate::db::postgres::PostgresDb;
use crate::models::*;
use crate::network::tcp_client::TcpClient;
use crate::network::tcp_server::TcpServer;
use anyhow::{anyhow, Result};
use std::sync::{Arc, Mutex};

use crate::game_logic::night_resolver::NightResolver;
use crate::game_logic::phase_machine::PhaseType;
use crate::game_logic::role_distributor::RoleDistributor;
use crate::game_logic::state::GameState;
use crate::game_logic::win_checker::WinChecker;

/// Main API struct for FFI exports to Flutter
pub struct Api {
    // Network state (Host/Client)
    // We use Arc<Mutex<Option<...>>> to allow interior mutability and sharing
    server: Arc<Mutex<Option<TcpServer>>>,
    client: Arc<Mutex<Option<TcpClient>>>,
    // Database client
    db: Arc<PostgresDb>,
    // Game State
    game_state: Arc<Mutex<Option<GameState>>>,
}

impl Api {
    pub fn new(database_url: String) -> Self {
        // Initialize Postgres DB (blocking waiting for connection/migration)
        let runtime = tokio::runtime::Runtime::new().unwrap();

        let db = runtime
            .block_on(async { PostgresDb::new(&database_url).await })
            .expect("Failed to initialize Database");

        Api {
            server: Arc::new(Mutex::new(None)),
            client: Arc::new(Mutex::new(None)),
            db: Arc::new(db),
            game_state: Arc::new(Mutex::new(None)),
        }
    }

    /// Test database connection
    pub fn test_db(&self) -> Result<String> {
        let db = self.db.clone();
        let runtime = tokio::runtime::Runtime::new().unwrap();

        runtime.block_on(async {
            // Check connection by getting a player or running a query
            // Simple check: Try to get a non-existent player
            match db.get_player_by_username("test_check").await {
                Ok(_) => Ok("Database connection active".to_string()),
                Err(e) => Err(anyhow!("Database error: {}", e)),
            }
        })
    }

    /// User authentication
    pub fn login(&self, username: String, password: String) -> Result<User> {
        let db = self.db.clone();
        let runtime = tokio::runtime::Runtime::new().unwrap();

        runtime.block_on(async {
            match db.get_player_by_username(&username).await? {
                Some(user) => {
                    // Verify password (Simple check for prototype)
                    if user.password_hash == password {
                        // Update last login
                        let _ = db.update_last_login(&user.user_id).await;
                        Ok(user)
                    } else {
                        Err(anyhow!("Invalid password"))
                    }
                },
                None => Err(anyhow!("User not found")),
            }
        })
    }

    /// User registration
    pub fn register(&self, username: String, password: String) -> Result<User> {
        let db = self.db.clone();
        let runtime = tokio::runtime::Runtime::new().unwrap();

        // In production, hash password here
        let password_hash = password;

        runtime.block_on(async {
            db.create_player(&username, &password_hash)
                .await
                .map_err(|e| anyhow!("Registration failed: {}", e))
        })
    }

    /// Update username
    pub fn update_username(&self, user_id: String, new_username: String) -> Result<()> {
        let db = self.db.clone();
        let runtime = tokio::runtime::Runtime::new().unwrap();

        runtime.block_on(async {
            db.update_username(&user_id, &new_username)
                .await
                .map_err(|e| anyhow!("Failed to update username: {}", e))
        })
    }

    // --- Legacy P2P / Local methods (Stubbed or Redirected) ---

    pub async fn create_room(&self, room_name: String, max_players: i32) -> Result<String> {
        // Stop any existing server/client
        *self.server.lock().unwrap() = None;
        *self.client.lock().unwrap() = None;

        let addr = "0.0.0.0:27015";
        let server = TcpServer::bind(addr)
            .await
            .map_err(|e| anyhow!("Failed to bind server to {}: {}", addr, e))?;

        *self.server.lock().unwrap() = Some(server);

        Ok(format!(
            "Room '{}' created on port 27015. Max players: {}",
            room_name, max_players
        ))
    }

    pub async fn join_room(&self, host_ip: String) -> Result<String> {
        // Stop any existing server/client
        *self.server.lock().unwrap() = None;
        *self.client.lock().unwrap() = None;

        let addr = format!("{}:27015", host_ip);
        let client = TcpClient::connect(&addr)
            .await
            .map_err(|e| anyhow!("Failed to connect to host {}: {}", addr, e))?;

        *self.client.lock().unwrap() = Some(client);

        Ok(format!("Successfully connected to {}", addr))
    }

    pub fn get_local_ips(&self) -> Result<Vec<String>> {
        Ok(vec![
            "Check your VPN/LAN adapter settings".to_string(),
            "(Use ipconfig on Windows)".to_string(),
        ])
    }

    pub async fn test_connection(&self) -> Result<String> {
        let mut client_lock = self.client.lock().unwrap();

        if let Some(_client) = client_lock.as_mut() {
            Ok("Connection active".to_string())
        } else {
            Err(anyhow!("No active client connection"))
        }
    }

    // --- Game Actions ---

    pub fn send_message(
        &self,
        room_id: String,
        user_id: String,
        message: String,
    ) -> Result<ChatMessage> {
        // DB Persistence: Save Chat
        let db = self.db.clone();
        let runtime = tokio::runtime::Runtime::new().unwrap();

        // We need game_id from state
        let game_lock = self.game_state.lock().unwrap();
        let game_id = if let Some(state) = game_lock.as_ref() {
            state.game_id.clone()
        } else {
            String::new()
        };

        // Scope logic (simplified)
        let scope = "LOBBY";

        if !game_id.is_empty() {
            let g_id = game_id.clone();
            let u_id = user_id.clone();
            let msg = message.clone();

            runtime.block_on(async {
                let _ = db.save_chat_message(&g_id, None, &u_id, scope, &msg).await;
            });
        }

        Ok(ChatMessage {
            message_id: "preview".to_string(),
            room_id,
            sender_id: user_id,
            sender_name: "Me".to_string(),
            message,
            phase_type: "lobb".to_string(),
            created_at: chrono::Utc::now().to_rfc3339(),
        })
    }

    pub fn cast_vote(&self, room_id: String, voter_id: String, target_id: String) -> Result<Vote> {
        Ok(Vote {
            vote_id: "preview".to_string(),
            room_id,
            phase_id: "1".to_string(),
            voter_id,
            target_id,
            created_at: String::new(),
        })
    }

    // --- Game Engine FFI ---

    /// Start the game engine for a specific room
    pub fn start_game(&self, room_id: String) -> Result<String> {
        let mut game_lock = self.game_state.lock().unwrap();

        let mut new_state = GameState::new(room_id.clone());

        // 1. Mock Players (6 players for testing role distribution)
        let mock_names = vec!["Alice", "Bob", "Charlie", "David", "Eve", "Frank"];
        let mut participants = std::collections::HashMap::new();

        for (i, name) in mock_names.iter().enumerate() {
            let pid = (i + 1).to_string(); // String ID
            participants.insert(
                pid.clone(),
                GameParticipant {
                    session_id: format!("sess_{}", pid),
                    room_id: room_id.clone(),
                    user_id: pid.clone(),
                    username: name.to_string(),
                    role: None, // Assigned below
                    is_alive: true,
                    seat_number: (i + 1) as i32,
                    joined_at: String::new(),
                },
            );
        }

        // 2. Assign Roles
        let roles = RoleDistributor::assign_roles(participants.len());

        let mut role_iter = roles.into_iter();

        // DB Persistence: Create Game
        let db = self.db.clone();
        let runtime = tokio::runtime::Runtime::new().unwrap();
        let game_id_db = runtime.block_on(async {
            db.create_game(&room_id)
                .await
                .unwrap_or_else(|_| "offline_game".to_string())
        });

        for p in participants.values_mut() {
            if let Some(r) = role_iter.next() {
                p.role = Some(r.name.clone());

                // DB Persistence: Add Participant
                let pid_str = p.user_id.clone();
                let r_name = r.name.clone();
                let g_id = game_id_db.clone();
                let seat = p.seat_number;

                runtime.block_on(async {
                    let _ = db
                        .add_game_participant(&g_id, &pid_str, &r_name, true, seat)
                        .await;
                });
            }
        }

        new_state.participants = participants;
        new_state.game_id = game_id_db.clone();
        *game_lock = Some(new_state);

        // 3. Start Game Loop (Spawn thread)
        let game_state_arc = self.game_state.clone();
        let db_clone = self.db.clone();

        tokio::spawn(async move {
            loop {
                tokio::time::sleep(tokio::time::Duration::from_secs(1)).await;

                let game_ended = {
                    let mut lock = game_state_arc.lock().unwrap();
                    if let Some(state) = lock.as_mut() {
                        if state.phase_machine.get_remaining_time() <= 0 {
                            let old_phase = state.phase_machine.current_phase.clone();
                            state.phase_machine.next_phase();
                            let new_phase = state.phase_machine.current_phase.clone();

                            println!("Phase Change: {:?} -> {:?}", old_phase, new_phase);

                            match (old_phase, new_phase) {
                                (PhaseType::Night, PhaseType::Day) => {
                                    let logs = NightResolver::resolve(
                                        &state.action_history,
                                        &mut state.participants,
                                    );
                                    for log in logs {
                                        println!("[Night Log] {}", log);
                                    }
                                },
                                (PhaseType::Vote, PhaseType::Night) => {
                                    let votes = state.vote_system.get_results();
                                    if let Some((target, count)) =
                                        votes.iter().max_by_key(|entry| entry.1)
                                    {
                                        println!(
                                            "Vote Result: Player {} received {} votes.",
                                            target, count
                                        );
                                        if let Some(p) = state.participants.get_mut(target) {
                                            p.is_alive = false;
                                            println!("Player {} was executed by vote.", p.username);
                                        }
                                    } else {
                                        println!("No votes cast. No one executed.");
                                    }
                                    state.vote_system.reset();
                                },
                                _ => {},
                            }

                            // Check Win Condition
                            if let Some(faction) = WinChecker::check_win(&state.participants) {
                                println!("Game Over! Winner: {:?}", faction);
                                Some((state.game_id.clone(), format!("{:?}", faction)))
                            } else {
                                None
                            }
                        } else {
                            None
                        }
                    } else {
                        return;
                    }
                };

                if let Some((g_id, faction)) = game_ended {
                    let _ = db_clone.end_game(&g_id, &faction).await;
                    break;
                }
            }
        });

        Ok("Game started with 6 mock players".to_string())
    }

    pub fn get_game_state(&self) -> Result<String> {
        let game_lock = self.game_state.lock().unwrap();

        if let Some(state) = game_lock.as_ref() {
            let phase = &state.phase_machine.current_phase;
            let remaining = state.phase_machine.get_remaining_time();

            let json = serde_json::json!({
                "room_id": state.room_id,
                "phase": format!("{:?}", phase),
                "remaining_time": remaining,
                "player_count": state.participants.len()
            });

            Ok(json.to_string())
        } else {
            Err(anyhow!("No active game"))
        }
    }

    pub fn submit_action(
        &self,
        actor_id: String,
        action_type: String,
        target_id: Option<String>,
    ) -> Result<String> {
        let mut game_lock = self.game_state.lock().unwrap();

        if let Some(state) = game_lock.as_mut() {
            // Process action
            let action = GameAction {
                action_id: (state.action_history.len() + 1).to_string(),
                room_id: state.room_id.clone(),
                phase_id: "1".to_string(), // Mock phase ID
                actor_id: actor_id.clone(),
                target_id: target_id.clone(),
                action_type: action_type.clone(),
                action_result: None,
                created_at: String::new(),
            };

            state.action_history.push(action);

            // Handle specific logic
            if action_type == "VOTE" {
                if let Some(target) = target_id.clone() {
                    state.vote_system.cast_vote(actor_id.clone(), target);
                }
            }

            println!("Action: Player {} did {} on {:?}", actor_id, action_type, target_id);

            Ok("Action submitted".to_string())
        } else {
            Err(anyhow!("No active game"))
        }
    }

    pub fn force_next_phase(&self) -> Result<String> {
        let mut game_lock = self.game_state.lock().unwrap();
        if let Some(state) = game_lock.as_mut() {
            state.phase_machine.next_phase();
            Ok(format!("Advanced to {:?}", state.phase_machine.current_phase))
        } else {
            Err(anyhow!("No active game"))
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    // Helper to get test database URL
    fn get_test_db_url() -> String {
        std::env::var("DATABASE_URL")
            .unwrap_or_else(|_| "postgres://postgres:password@localhost/areyoughost".to_string())
    }

    #[test]
    fn test_register_success() {
        let api = Api::new(get_test_db_url());

        let username = format!("test{}", chrono::Utc::now().timestamp() % 100000);
        let password = "test_password_123";

        let user = api
            .register(username.clone(), password.to_string())
            .expect("Registration should succeed");

        assert_eq!(user.username, username);
        assert!(!user.user_id.is_empty());
        println!("✅ Registration successful: {}", user.username);
    }

    #[test]
    fn test_register_duplicate_username() {
        let api = Api::new(get_test_db_url());

        let username = format!("dup{}", chrono::Utc::now().timestamp() % 100000);
        let password = "password123";

        api.register(username.clone(), password.to_string())
            .expect("First registration should succeed");

        let result = api.register(username.clone(), password.to_string());
        assert!(result.is_err());
        println!("✅ Duplicate username correctly rejected");
    }

    #[test]
    fn test_login_success() {
        let api = Api::new(get_test_db_url());

        let username = format!("login{}", chrono::Utc::now().timestamp() % 100000);
        let password = "secure_password_456";

        api.register(username.clone(), password.to_string())
            .expect("Registration should succeed");

        let logged_in_user = api
            .login(username.clone(), password.to_string())
            .expect("Login should succeed");

        assert_eq!(logged_in_user.username, username);
        println!("✅ Login successful: {}", username);
    }

    #[test]
    fn test_login_wrong_password() {
        let api = Api::new(get_test_db_url());

        let username = format!("wrong{}", chrono::Utc::now().timestamp() % 100000);
        let password = "correct_password";

        api.register(username.clone(), password.to_string())
            .expect("Registration should succeed");

        let result = api.login(username.clone(), "wrong_password".to_string());
        assert!(result.is_err());
        println!("✅ Wrong password correctly rejected");
    }

    #[test]
    fn test_login_nonexistent_user() {
        let api = Api::new(get_test_db_url());

        let username = format!("none{}", chrono::Utc::now().timestamp() % 100000);
        let password = "any_password";

        let result = api.login(username.clone(), password.to_string());
        assert!(result.is_err());
        println!("✅ Non-existent user correctly rejected");
    }

    #[test]
    fn test_thai_username_support() {
        let api = Api::new(get_test_db_url());

        let username = format!("ไทย{}", chrono::Utc::now().timestamp() % 10000);
        let password = "รหัสผ่าน123";

        let user = api
            .register(username.clone(), password.to_string())
            .expect("Thai characters should be supported");

        assert_eq!(user.username, username);

        let logged_in = api
            .login(username.clone(), password.to_string())
            .expect("Thai login should work");

        assert_eq!(logged_in.username, username);
        println!("✅ Thai characters supported: {}", user.username);
    }
}
