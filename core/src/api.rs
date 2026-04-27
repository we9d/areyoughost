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
  server: Arc<Mutex<Option<TcpServer>>>,
  client: Arc<Mutex<Option<TcpClient>>>,
  // db: Option<Arc<PostgresDb>>,
  game_state: Arc<Mutex<Option<GameState>>>,
}

impl Api {
  /// Create a new Api instance. The database_url is ignored — DB is managed by the HTTP server.
  pub fn new(_database_url: String) -> Self {
    Api {
      server: Arc::new(Mutex::new(None)),
      client: Arc::new(Mutex::new(None)),
      game_state: Arc::new(Mutex::new(None)),
    }
  }

  /// Compatibility constructor used by Flutter bridge (database_url ignored — auth is HTTP-only now)
  pub fn new_with_db(_database_url: String) -> Self {
    Self::new(String::new())
  }

  /// Initialize the Raw TCP Connection to the server
  pub async fn connect_server(&self, ip: String) -> Result<()> {
      let client = TcpClient::connect(&ip).await
          .map_err(|e| anyhow!("Failed to connect to raw TCP server {}: {}", ip, e))?;
      *self.client.lock().unwrap() = Some(client);
      Ok(())
  }

  /// Raw TCP Protocol Login
  pub async fn login(&self, username: String, password: String) -> Result<User> {
      let mut client = {
          let mut client_opt = self.client.lock().unwrap();
          client_opt.take().ok_or_else(|| anyhow!("Not connected to server. Call connect_server() first."))?
      };

      let cmd = serde_json::json!({
          "command": "Login",
          "username": username,
          "password": password
      });

      let res = async {
          client.send_command(&cmd.to_string()).await?;
          client.read_line().await
      }.await;

      *self.client.lock().unwrap() = Some(client);

      let response = res?;
      let parsed: serde_json::Value = serde_json::from_str(&response)?;

      if parsed["response_type"] == "AuthSuccess" {
          let token = parsed["token"].as_str().unwrap_or_default().to_string();
          let user_id = parsed["player_id"].as_str().unwrap_or_default().to_string();
          let uname = parsed["username"].as_str().unwrap_or_default().to_string();

          Ok(User {
              user_id,
              username: uname,
              password_hash: token, // Used as token storage
              created_at: String::new(),
              last_login: None,
          })
      } else {
          let msg = parsed["message"].as_str().unwrap_or("Unknown error");
          Err(anyhow!("{}", msg))
      }
  }

  /// Raw TCP Protocol Register
  pub async fn register(&self, username: String, password: String) -> Result<User> {
      let mut client = {
          let mut client_opt = self.client.lock().unwrap();
          client_opt.take().ok_or_else(|| anyhow!("Not connected to server. Call connect_server() first."))?
      };

      let cmd = serde_json::json!({
          "command": "Register",
          "username": username,
          "password": password
      });

      let res = async {
          client.send_command(&cmd.to_string()).await?;
          client.read_line().await
      }.await;

      *self.client.lock().unwrap() = Some(client);

      let response = res?;
      let parsed: serde_json::Value = serde_json::from_str(&response)?;

      if parsed["response_type"] == "AuthSuccess" {
          let token = parsed["token"].as_str().unwrap_or_default().to_string();
          let user_id = parsed["player_id"].as_str().unwrap_or_default().to_string();
          let uname = parsed["username"].as_str().unwrap_or_default().to_string();

          Ok(User {
              user_id,
              username: uname,
              password_hash: token,
              created_at: String::new(),
              last_login: None,
          })
      } else {
          let msg = parsed["message"].as_str().unwrap_or("Unknown error");
          Err(anyhow!("{}", msg))
      }
  }

  /// Stub: DB is server-side only
  pub fn test_db(&self) -> Result<String> {
    Ok("DB is managed by HTTP server — no local connection needed".to_string())
  }

  /// Stub: profile updates not yet implemented
  pub fn update_username(&self, _user_id: String, _new_username: String) -> Result<()> {
    Err(anyhow!("update_username not yet implemented in HTTP server"))
  }
}


impl Api {
    // Note: Auth (login/register) is now handled by the HTTP server (POST /auth/login, POST /auth/register)
    // WS events handle room and game state. This core/api.rs is legacy P2P + Game Engine only.

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
        Ok(ChatMessage {
            message_id: "preview".to_string(),
            room_id,
            sender_id: user_id,
            sender_name: "Me".to_string(),
            message,
            phase_type: "lobby".to_string(),
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
                    current_faction: Some("Villager".to_string()),
                    transformed_to_ghoul: false,
                    is_alive: true,
                    seat_number: (i + 1) as i32,
                    joined_at: String::new(),
                },
            );
        }

        // Assign Roles (distribution wired when roles are bound per seat)
        let _roles = RoleDistributor::assign_roles(participants.len());
        let game_id_db = "local_game".to_string();

        new_state.participants = participants;
        new_state.game_id = game_id_db.clone();
        *game_lock = Some(new_state);

        // Start Game Loop (Spawn thread)
        let game_state_arc = self.game_state.clone();

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

                if let Some((_g_id, faction)) = game_ended {
                    println!("Game ended. Winner faction: {}", faction);
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
                } else {
                    state.vote_system.unvote(&actor_id);
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

// Legacy tests removed since the API is now Async and relies on the TCP server on port 3001.
