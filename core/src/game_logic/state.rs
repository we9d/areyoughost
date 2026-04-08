use crate::models::{ChatMessage, GameAction, GameParticipant, Room};
use std::collections::HashMap;
use std::sync::Arc;
use std::time::Instant;
use tokio::sync::{mpsc, RwLock};
use uuid::Uuid;
use chrono::{DateTime, Utc};

// ---------------------------------------------------------------------------
// Session tracking
// ---------------------------------------------------------------------------

/// Tracks an authenticated player session (session_id → player_id + last_seen).
#[derive(Debug)]
pub struct SessionInfo {
    pub player_id: Uuid,
    pub last_seen: Instant,
}

// ---------------------------------------------------------------------------
// Room mode
// ---------------------------------------------------------------------------

/// Distinguishes Quick Play (public matchmaking) from Custom (invite-only) rooms.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum RoomMode {
    QuickPlay,
    Custom,
}

// ---------------------------------------------------------------------------
// Room state
// ---------------------------------------------------------------------------

pub struct RoomState {
    pub room: Room,
    pub game_state: Option<GameState>,
    /// The player_id of the room host
    pub host_id: Uuid,
    /// Channel to send actions into the Room Runner task (set when game starts).
    pub action_tx: Option<mpsc::UnboundedSender<super::room_task::RoomAction>>,
    /// Whether this is a Quick Play or Custom room.
    pub room_mode: RoomMode,
    /// Timestamp when the Quick Play lobby was created (used for the 120 s auto-start timer).
    pub lobby_start_time: Option<Instant>,
}

// ---------------------------------------------------------------------------
// Application state
// ---------------------------------------------------------------------------

pub struct AppState {
    pub rooms: HashMap<Uuid, RoomState>,
    /// Maps session_id → SessionInfo (player_id + last_seen Instant).
    pub sessions: HashMap<Uuid, SessionInfo>,
    /// Shared PostgreSQL connection pool.
    pub db_pool: sqlx::PgPool,
    /// Cached roles from the DB for runtime reference
    pub cached_roles: HashMap<i32, crate::game_logic::roles::Role>,
}

impl AppState {
    /// Construct a new `AppState` and wrap it in `Arc<RwLock<AppState>>`.
    pub fn new(db_pool: sqlx::PgPool) -> Arc<RwLock<Self>> {
        Arc::new(RwLock::new(Self {
            rooms: HashMap::new(),
            sessions: HashMap::new(),
            db_pool,
            cached_roles: HashMap::new(),
        }))
    }
}

// ---------------------------------------------------------------------------
// Runtime Participant Info
// ---------------------------------------------------------------------------

#[derive(Debug, Clone)]
pub struct ParticipantInfo {
    pub model: GameParticipant,
    pub username: String,
    pub role: Option<crate::game_logic::roles::Role>,
    // Runtime states tracking round-to-round logic natively in memory
    pub is_silenced: bool,
    pub protected_by: Option<uuid::Uuid>,
    pub hidden_target: Option<uuid::Uuid>,
}

// ---------------------------------------------------------------------------
// Game state (per active game inside a room)
// ---------------------------------------------------------------------------

#[derive(Debug, Clone)]
pub struct GameState {
    pub room_id: Uuid,
    pub game_id: Uuid,
    pub participants: HashMap<Uuid, ParticipantInfo>,
    pub phase_machine: super::phase_machine::PhaseMachine,
    pub chat_history: Vec<ChatMessage>,
    pub action_history: Vec<GameAction>,
    pub vote_system: super::vote_system::VoteSystem,
}

impl GameState {
    pub fn new(room_id: Uuid) -> Self {
        Self {
            room_id,
            game_id: Uuid::nil(),
            participants: HashMap::new(),
            phase_machine: super::phase_machine::PhaseMachine::new(),
            chat_history: Vec::new(),
            action_history: Vec::new(),
            vote_system: super::vote_system::VoteSystem::new(),
        }
    }

    pub fn init_from_room(
        room_id: Uuid,
        players: Vec<(Uuid, String)>,
        preassigned_roles: Option<Vec<super::roles::Role>>,
        random_seed: Option<u64>,
    ) -> Self {
        let mut state = Self::new(room_id.clone());
        let player_count = players.len();

        let roles = if let Some(r) = preassigned_roles {
            r
        } else {
            super::role_distributor::RoleDistributor::assign_roles(player_count, random_seed)
        };

        for (i, (player_id, _username)) in players.into_iter().enumerate() {
            let role = roles.get(i).cloned();

            let participant = GameParticipant {
                game_participant_id: Uuid::new_v4(),
                game_id: state.game_id,
                player_id,
                role_id: role.as_ref().map(|r| r.role_id).unwrap_or(1),
                revealed_role_id: None,
                is_alive: true,
                seat_number: (i + 1) as i32,
                joined_at: Utc::now(),
                died_at: None,
                death_reason: None,
            };

            state.participants.insert(
                player_id,
                ParticipantInfo {
                    model: participant,
                    username: _username,
                    role,
                    is_silenced: false,
                    protected_by: None,
                    hidden_target: None,
                },
            );
        }

        state
    }

    pub fn record_action(
        &mut self,
        actor_id: Uuid,
        target_id: Option<Uuid>,
        skill_code: String,
    ) -> Result<(), String> {
        let actor = self.participants.get(&actor_id).ok_or("Actor not found")?;
        if !actor.model.is_alive {
            return Err("Dead players cannot perform actions".to_string());
        }

        let action = GameAction {
            action_id: Uuid::new_v4(),
            game_id: self.game_id,
            phase_id: self.phase_machine.phase_id,
            actor_id,
            target_id,
            action_type: skill_code,
            action_result: None,
            created_at: Utc::now(),
        };

        self.action_history.push(action);
        Ok(())
    }

    pub fn resolve_night(&mut self) -> serde_json::Value {
        let mut deaths: Vec<Uuid> = Vec::new();
        let effects: Vec<serde_json::Value> = Vec::new();

        let mut kill_targets = Vec::new();
        let mut protected_targets = Vec::new();

        // Note: New schema alignment. If GameParticipant needs more fields like protected_by, 
        // they should be added to models.rs first. For now, simplifying to compile.

        // let current_day = self.phase_machine.day_number.to_string(); // OLD
        for action in &self.action_history {
            // Simplified resolution for now to match Uuid types
            match action.action_type.as_str() {
                "GHOST_KILL" | "SK_KILL" => {
                    if let Some(tid) = action.target_id {
                        kill_targets.push(tid);
                    }
                }
                "DOCTOR_HEAL" => {
                    if let Some(tid) = action.target_id {
                        protected_targets.push(tid);
                    }
                }
                _ => {}
            }
        }

        for target_id in kill_targets {
            if !protected_targets.contains(&target_id) {
                if let Some(participant) = self.participants.get_mut(&target_id) {
                    if participant.model.is_alive {
                        participant.model.is_alive = false;
                        deaths.push(target_id);
                    }
                }
            }
        }

        serde_json::json!({
            "deaths": deaths,
            "effects": effects
        })
    }

    pub fn resolve_vote(&mut self) -> serde_json::Value {
        // This assumes cross-dependency with vote_system.rs which might also need Uuid updates.
        // For now, aligning the output types.
        let result = self.vote_system.resolve_vote(&mut self.participants);

        let mut deaths: Vec<Uuid> = Vec::new();
        let mut events: Vec<serde_json::Value> = Vec::new();

        if let Some(eliminated) = result.eliminated {
            deaths.push(eliminated);
        }

        for extra in result.extra_deaths {
            deaths.push(extra);
            events.push(serde_json::json!({
                "type": "avenger_vengeance",
                "victim": extra
            }));
        }

        if let Some(ref faction) = result.special_win {
            let faction_str = match faction {
                crate::game_logic::roles::Faction::Special => "SPECIAL",
                crate::game_logic::roles::Faction::Ghost   => "GHOST",
                crate::game_logic::roles::Faction::Villager => "VILLAGER",
                crate::game_logic::roles::Faction::Draw    => "DRAW",
            };
            events.push(serde_json::json!({
                "type": "special_win",
                "faction": faction_str
            }));
        }

        serde_json::json!({
            "deaths": deaths,
            "events": events
        })
    }
}
