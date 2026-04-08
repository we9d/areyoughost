//! # FFI API Module
//!
//! This module provides the FFI (Foreign Function Interface) exports
//! that allow the Flutter frontend to communicate with the Rust backend.

use crate::models::*;
use crate::network::tcp_client::TcpClient;
use crate::network::tcp_server::TcpServer;
use crate::network::message::{
    Message, MessageType, LoginRequest, LoginResponse, 
    StartGameRequest, CastVoteRequest, NightActionRequest, ChatMessageRequest, 
    LeaveRoomRequest, ParticipantInfoDto, RoomStateSync, GamePhaseChange, GameEvent, ServerResponse, ChatEntry
};
use std::sync::{Arc, Mutex};
use crate::game_logic::state::GameState;
pub use serde_json::Value;
use uuid::Uuid;
use chrono::Utc;

/// Main API struct for FFI exports to Flutter
pub struct Api {
  _server: Arc<Mutex<Option<TcpServer>>>,
  _client: Arc<Mutex<Option<TcpClient>>>,
  _game_state: Arc<Mutex<Option<GameState>>>,
}

impl Api {
  /// Create a new Api instance.
  pub fn new(_database_url: String) -> Self {
    Api {
      _server: Arc::new(Mutex::new(None)),
      _client: Arc::new(Mutex::new(None)),
      _game_state: Arc::new(Mutex::new(None)),
    }
  }

  /// Compatibility constructor used by Flutter bridge
  pub fn new_with_db(_database_url: String) -> Self {
    Self::new(String::new())
  }

  pub fn login(&self, _username: String, _password: String) -> anyhow::Result<User> {
    Err(anyhow::anyhow!("Use HTTP POST /auth/login instead"))
  }

  /// Stub: auth is handled by HTTP POST /auth/register
  pub fn register(&self, _username: String, _password: String) -> anyhow::Result<User> {
    Err(anyhow::anyhow!("Use HTTP POST /auth/register instead"))
  }

  /// Stub: DB is server-side only
  pub fn test_db(&self) -> anyhow::Result<String> {
    Ok("DB is managed by HTTP server".to_string())
  }

  pub fn update_username(&self, _player_id: String, _new_username: String) -> anyhow::Result<()> {
    Err(anyhow::anyhow!("update_username not yet implemented"))
  }

  /// Connect to the Rust Backend via Binary TCP (SRS 3.1.4.1.1.2)
  pub async fn connect_to_server(&self, addr: String) -> anyhow::Result<String> {
    let client = TcpClient::connect(&addr).await?;
    let mut guard = self._client.lock().map_err(|e| anyhow::anyhow!("Lock error: {}", e))?;
    *guard = Some(client);
    Ok(format!("Connected to {}", addr))
  }

  /// Execute Custom Binary Authentication (SRS 3.1.4.4)
  pub async fn send_login(&self, username: String, password: String) -> anyhow::Result<String> {
    let req = LoginRequest { username, password };
    let msg = Message::from_json(MessageType::LoginRequest, &req)?;
    
    let client = {
        let guard = self._client.lock().map_err(|e| anyhow::anyhow!("Lock error: {}", e))?;
        guard.as_ref().cloned()
    };
    
    if let Some(mut client) = client {
        client.send(&msg).await?;
        let resp_msg = client.receive().await?;
        if resp_msg.msg_type == MessageType::LoginResponse {
            let resp = resp_msg.parse_json::<LoginResponse>()?;
            if resp.success {
                Ok(format!("Login successful! Session: {:?}", resp.session_id))
            } else {
                Err(anyhow::anyhow!("Login failed: {:?}", resp.error))
            }
        } else {
            Err(anyhow::anyhow!("Unexpected response type: {:?}", resp_msg.msg_type))
        }
    } else {
        Err(anyhow::anyhow!("Not connected to server"))
    }
  }

  pub async fn accept_invite(&self, invite_code: String) -> anyhow::Result<String> {
    use serde_json::json;
    let msg = Message::from_json(MessageType::JoinRoomRequest, &json!({ "invite_code": invite_code }))?;
    let client = {
        let guard = self._client.lock().map_err(|e| anyhow::anyhow!("Lock error: {}", e))?;
        guard.as_ref().cloned()
    };

    if let Some(mut client) = client {
        client.send(&msg).await?;
        Ok("Acceptance sent".to_string())
    } else {
        Err(anyhow::anyhow!("Not connected to server"))
    }
  }

  pub async fn decline_invite(&self, invite_code: String) -> anyhow::Result<String> {
    use serde_json::json;
    let msg = Message::from_json(MessageType::LeaveRoomRequest, &json!({ "invite_code": invite_code }))?;
    let client = {
        let guard = self._client.lock().map_err(|e| anyhow::anyhow!("Lock error: {}", e))?;
        guard.as_ref().cloned()
    };

    if let Some(mut client) = client {
        client.send(&msg).await?;
        Ok("Decline sent".to_string())
    } else {
        Err(anyhow::anyhow!("Not connected to server"))
    }
  }

  pub async fn create_room(&self, room_name: String, _max_players: i32) -> anyhow::Result<String> {
      {
          let mut s_guard = self._server.lock().map_err(|e| anyhow::anyhow!("Lock error: {}", e))?;
          let mut c_guard = self._client.lock().map_err(|e| anyhow::anyhow!("Lock error: {}", e))?;
          *s_guard = None;
          *c_guard = None;
      }

      let addr = "127.0.0.1:8888";
      // AppState requires a real PgPool; this FFI path is a legacy stub.
      // A proper server is started via TcpServer::bind in main.rs with a real pool.
      let db_url = std::env::var("DATABASE_URL")
          .unwrap_or_else(|_| "postgres://localhost/areyoughost".to_string());
      let pool = sqlx::PgPool::connect(&db_url).await
          .map_err(|e| anyhow::anyhow!("DB connect failed: {}", e))?;
      let app_state = crate::game_logic::state::AppState::new(pool);
      let server = TcpServer::bind(addr, app_state).await
          .map_err(|e| anyhow::anyhow!("Failed to bind server: {}", e))?;

      let mut s_guard = self._server.lock().map_err(|e| anyhow::anyhow!("Lock error: {}", e))?;
      *s_guard = Some(server);

      Ok(format!("Room '{}' created", room_name))
  }

  pub async fn join_room(&self, host_ip: String) -> anyhow::Result<String> {
      {
          let mut s_guard = self._server.lock().map_err(|e| anyhow::anyhow!("Lock error: {}", e))?;
          let mut c_guard = self._client.lock().map_err(|e| anyhow::anyhow!("Lock error: {}", e))?;
          *s_guard = None;
          *c_guard = None;
      }

      let addr = format!("{}:8888", host_ip);
      let client = TcpClient::connect(&addr).await
          .map_err(|e| anyhow::anyhow!("Failed to connect: {}", e))?;

      let mut c_guard = self._client.lock().map_err(|e| anyhow::anyhow!("Lock error: {}", e))?;
      *c_guard = Some(client);

      Ok(format!("Joined {}", addr))
  }

  pub fn get_local_ips(&self) -> anyhow::Result<Vec<String>> {
      Ok(vec!["Use ipconfig".to_string()])
  }

  pub async fn add_game_action(&self, actor_id: String, target_id: Option<String>, action_type: String) -> anyhow::Result<String> {
      let mut lock = self._game_state.lock().map_err(|e| anyhow::anyhow!("Lock error: {}", e))?;
      if let Some(state) = lock.as_mut() {
          let a_id = Uuid::parse_str(&actor_id).unwrap_or_else(|_| Uuid::nil());
          let t_id = target_id.and_then(|s| Uuid::parse_str(&s).ok());
          state.action_history.push(GameAction {
              action_id: Uuid::new_v4(),
              game_id: state.game_id,
              phase_id: state.phase_machine.phase_id,
              actor_id: a_id,
              target_id: t_id,
              action_type,
              action_result: None,
              created_at: Utc::now(),
          });
          Ok("Ok".into())
      } else {
          Err(anyhow::anyhow!("No active game state"))
      }
  }

  pub async fn force_next_phase(&self) -> anyhow::Result<String> {
      let mut lock = self._game_state.lock().map_err(|e| anyhow::anyhow!("Lock error: {}", e))?;
      if let Some(state) = lock.as_mut() {
          state.phase_machine.next_phase();
          Ok("Ok".into())
      } else { Err(anyhow::anyhow!("None")) }
  }

  pub async fn start_game(&self, room_id: String) -> anyhow::Result<String> {
      let r_id = Uuid::parse_str(&room_id).map_err(|_| anyhow::anyhow!("Invalid room ID"))?;
      let req = StartGameRequest { room_id: r_id };
      let msg = Message::from_json(MessageType::StartGame, &req)?;
      
      let client = {
          let guard = self._client.lock().map_err(|e| anyhow::anyhow!("Lock error: {}", e))?;
          guard.as_ref().cloned()
      };
      
      if let Some(mut client) = client {
          client.send(&msg).await?;
          Ok(format!("Game start requested for {}", r_id))
      } else {
          Err(anyhow::anyhow!("Not connected to server"))
      }
  }

  /// Submit a night/day action.
  pub async fn submit_action(&self, room_id: String, action_type: crate::game_logic::roles::SkillType, target_id: Option<String>) -> anyhow::Result<String> {
      let rid = Uuid::parse_str(&room_id).map_err(|_| anyhow::anyhow!("Invalid room_id"))?;
      let tid = target_id.and_then(|s| Uuid::parse_str(&s).ok());

      let req = NightActionRequest { 
          room_id: rid, 
          action_type: action_type, 
          target_id: tid 
      };
      let msg = Message::from_json(MessageType::NightAction, &req)?;

      let client = {
          let guard = self._client.lock().map_err(|e| anyhow::anyhow!("Lock error: {}", e))?;
          guard.as_ref().cloned()
      };

      if let Some(mut client) = client {
          client.send(&msg).await?;
          Ok("Action submitted".to_string())
      } else {
          Err(anyhow::anyhow!("Not connected to server"))
      }
  }

  pub async fn test_connection(&self) -> anyhow::Result<String> {
      let guard = self._client.lock().map_err(|e| anyhow::anyhow!("Lock error: {}", e))?;
      if guard.is_some() {
          Ok("Connected".into())
      } else {
          Err(anyhow::anyhow!("Not connected"))
      }
  }

  /// Cast a vote during the Day phase.
  pub async fn cast_vote(&self, room_id: String, target_id: String) -> anyhow::Result<String> {
      let r = Uuid::parse_str(&room_id).map_err(|_| anyhow::anyhow!("Invalid room_id"))?;
      let t = Uuid::parse_str(&target_id).map_err(|_| anyhow::anyhow!("Invalid target_id"))?;
      
      let req = CastVoteRequest { room_id: r, target_id: t };
      let msg = Message::from_json(MessageType::CastVote, &req)?;

      let client = {
          let guard = self._client.lock().map_err(|e| anyhow::anyhow!("Lock error: {}", e))?;
          guard.as_ref().cloned()
      };

      if let Some(mut client) = client {
          client.send(&msg).await?;
          Ok("Vote recorded".to_string())
      } else {
          Err(anyhow::anyhow!("Not connected to server"))
      }
  }

  /// Get current game state summary. Stub — actual state is managed server-side.
  pub async fn get_game_state(&self) -> anyhow::Result<String> {
      let lock = self._game_state.lock().map_err(|e| anyhow::anyhow!("Lock error: {}", e))?;
      if lock.is_some() {
          Ok("Game in progress".to_string())
      } else {
          Ok("No active game".to_string())
      }
  }

  /// Send a chat message.
  pub async fn send_message(&self, room_id: String, message_text: String) -> anyhow::Result<String> {
      let rid = Uuid::parse_str(&room_id).map_err(|_| anyhow::anyhow!("Invalid room_id"))?;
      let req = ChatMessageRequest { room_id: rid, message_text };
      let msg = Message::from_json(MessageType::ChatMessage, &req)?;

      let client = {
          let guard = self._client.lock().map_err(|e| anyhow::anyhow!("Lock error: {}", e))?;
          guard.as_ref().cloned()
      };

      if let Some(mut client) = client {
          client.send(&msg).await?;
          Ok("Message sent".to_string())
      } else {
          Err(anyhow::anyhow!("Not connected to server"))
      }
  }

  pub async fn leave_room(&self, room_id: String) -> anyhow::Result<String> {
      let rid = Uuid::parse_str(&room_id).map_err(|_| anyhow::anyhow!("Invalid room_id"))?;
      use crate::network::message::LeaveRoomRequest;
      let req = LeaveRoomRequest { room_id: rid };
      let msg = Message::from_json(MessageType::LeaveRoomRequest, &req)?;

      let client = {
          let guard = self._client.lock().map_err(|e| anyhow::anyhow!("Lock error: {}", e))?;
          guard.as_ref().cloned()
      };

      if let Some(mut client) = client {
          client.send(&msg).await?;
          Ok("Leave request sent".to_string())
      } else {
          Err(anyhow::anyhow!("Not connected to server"))
      }
  }

  /// Internal use only: Ensures FRB generates Dart classes for these types.
  pub fn dummy_types(
      &self,
      _u: crate::models::User,
      _r: crate::models::Room,
      _p: crate::models::GameParticipant,
      _cm: crate::models::ChatMessage,
      _ga: crate::models::GameAction,
      _ce: crate::network::message::ChatEntry,
      _rss: RoomStateSync,
      _gpc: GamePhaseChange,
      _ge: GameEvent,
      _sr: ServerResponse,
      _sq: StartGameRequest,
      _vq: CastVoteRequest,
      _nq: NightActionRequest,
      _cq: ChatMessageRequest,
      _lq: LeaveRoomRequest,
      _pd: ParticipantInfoDto,
      _v: Option<Value>,
  ) {
  }
}
