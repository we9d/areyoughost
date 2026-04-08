use std::sync::Arc;
use std::time::{SystemTime, UNIX_EPOCH, Instant};
use std::collections::HashMap;

use bytes::Bytes;
use dashmap::DashMap;
use tokio::sync::mpsc;
use tokio::sync::RwLock;
use tokio::sync::mpsc::UnboundedSender;
use tokio::time::Duration;
use uuid::Uuid;
use chrono::{DateTime, Utc};

use crate::game_logic::night_resolver::NightResolver;
use crate::game_logic::state::AppState;
use crate::game_logic::win_checker::WinChecker;
use crate::models::GameAction;
use crate::network::message::{
    GameEvent, GameEventType, GamePhaseChange, Message, MessageType, PhaseType,
};

// ---------------------------------------------------------------------------
// Channel message types
// ---------------------------------------------------------------------------

/// Actions forwarded from the Dispatcher into the Room Runner task.
#[derive(Debug)]
pub enum RoomAction {
    Vote {
        voter_id: Uuid,
        target_id: Uuid,
    },
    NightAction {
        actor_id: Uuid,
        action_type: crate::game_logic::roles::SkillType,
        target_id: Option<Uuid>,
    },
    PlayerLeft {
        player_id: Uuid,
    },
}

// ---------------------------------------------------------------------------
// RoomRunner
// ---------------------------------------------------------------------------

/// Authoritative game-loop task for a single room.
///
/// Spawned by `handle_start_game()` in the Dispatcher; drives the
/// Night → Day → Vote → Night phase cycle until a winner is found.
pub struct RoomRunner {
    pub room_id: Uuid,
    pub app_state: Arc<RwLock<AppState>>,
    pub registry: Arc<DashMap<Uuid, UnboundedSender<Bytes>>>,
    pub action_rx: mpsc::UnboundedReceiver<RoomAction>,
}

impl RoomRunner {
    /// Entry point — drives the phase loop until a winner is declared.
    pub async fn run(mut self) {
        loop {
            // ── Night phase ──────────────────────────────────────────────
            self.run_night_phase().await;
            if self.check_and_announce_winner().await {
                return;
            }

            // ── Day phase ────────────────────────────────────────────────
            self.run_day_phase().await;
            if self.check_and_announce_winner().await {
                return;
            }

            // ── Vote phase ───────────────────────────────────────────────
            self.run_vote_phase().await;
            if self.check_and_announce_winner().await {
                return;
            }
        }
    }

    // -----------------------------------------------------------------------
    // Phase stubs (filled in Tasks 23-25)
    // -----------------------------------------------------------------------

    /// Night phase: collect night actions for 20 s, then resolve kills.
    async fn run_night_phase(&mut self) {
        let day_number = self.current_day_number().await;
        self.broadcast_phase_change(PhaseType::Night, day_number, 20).await;

        // ── Collect NightAction messages for 20 s ────────────────────────────
        let deadline = tokio::time::sleep(Duration::from_secs(20));
        tokio::pin!(deadline);

        let mut collected_actions: Vec<GameAction> = Vec::new();

        loop {
            tokio::select! {
                _ = &mut deadline => {
                    // Timer expired — stop collecting
                    break;
                }
                maybe_action = self.action_rx.recv() => {
                    match maybe_action {
                        Some(RoomAction::NightAction { actor_id, action_type, target_id }) => {
                            let (game_id, phase_id) = {
                                let state = self.app_state.read().await;
                                let rs = state.rooms.get(&self.room_id)
                                    .and_then(|r| r.game_state.as_ref())
                                    .map(|gs| (gs.game_id, gs.phase_machine.phase_id));
                                rs.unwrap_or((Uuid::nil(), Uuid::nil()))
                            };

                            let action = GameAction {
                                action_id: Uuid::new_v4(),
                                game_id,
                                phase_id,
                                actor_id,
                                target_id,
                                action_type: action_type.to_string(),
                                action_result: None,
                                created_at: Utc::now(),
                            };
                            collected_actions.push(action);
                        }
                        Some(RoomAction::PlayerLeft { player_id }) => {
                            tracing::info!(room_id = %self.room_id, player_id = %player_id, "Player left during night phase");
                        }
                        Some(RoomAction::Vote { .. }) => {
                            // Ignore votes during night phase
                        }
                        None => {
                            // Channel closed — stop collecting
                            break;
                        }
                    }
                }
            }
        }

        // ── Persist night actions to DB ──────────────────────────────────────
        if !collected_actions.is_empty() {
            let (db_pool, game_id) = {
                let state = self.app_state.read().await;
                let pool = state.db_pool.clone();
                let gid = state
                    .rooms
                    .get(&self.room_id)
                    .and_then(|r| r.game_state.as_ref())
                    .map(|gs| gs.game_id)
                    .unwrap_or_default();
                (pool, gid)
            };

            for action in &collected_actions {
                if let Err(e) = crate::network::dispatcher::Dispatcher::persist_game_action(
                    &db_pool,
                    &game_id,
                    &action.phase_id,
                    &action.actor_id,
                    action.target_id.as_ref(),
                    &action.action_type.to_string(),
                )
                .await
                {
                    tracing::error!(
                        room_id = %self.room_id,
                        actor_id = %action.actor_id,
                        error = %e,
                        "Failed to persist game_action to DB"
                    );
                }
            }
        }

        // ── Invoke NightResolver::resolve() ─────────────────────────────────
        let deaths = {
            let mut state = self.app_state.write().await;
            let roles = state.cached_roles.clone();
            if let Some(room_state) = state.rooms.get_mut(&self.room_id) {
                if let Some(game_state) = room_state.game_state.as_mut() {
                    NightResolver::resolve(&mut game_state.participants, &roles, &collected_actions)
                } else {
                    Vec::new()
                }
            } else {
                Vec::new()
            }
        };

        // ── Persist deaths to DB ─────────────────────────────────────────────
        if !deaths.is_empty() {
            let (db_pool, game_id) = {
                let state = self.app_state.read().await;
                let pool = state.db_pool.clone();
                let gid = state
                    .rooms
                    .get(&self.room_id)
                    .and_then(|r| r.game_state.as_ref())
                    .map(|gs| gs.game_id)
                    .unwrap_or_default();
                (pool, gid)
            };

            let died_at = chrono::Utc::now();
            for death in &deaths {
                if let Err(e) = crate::network::dispatcher::Dispatcher::mark_player_dead(
                    &db_pool,
                    &game_id,
                    &death.player_id,
                    died_at,
                )
                .await
                {
                    tracing::error!(
                        room_id = %self.room_id,
                        player_id = %death.player_id,
                        error = %e,
                        "Failed to persist death to DB"
                    );
                }
            }
        }

        // ── Broadcast GameEvent (0x34) with NightResolution ──────────────────
        let event = GameEvent {
            event_type: GameEventType::NightResolution,
            deaths,
            winner_faction: None,
            extra: None,
        };

        let msg = match Message::from_json(MessageType::GameEvent, &event) {
            Ok(m) => m,
            Err(e) => {
                tracing::error!(room_id = %self.room_id, "Failed to serialize GameEvent: {e}");
                return;
            }
        };
        self.broadcast_message(msg).await;
    }

    /// Day phase: open chat for 60 s, then advance.
    ///
    /// Requirements: 5.3, 16.1, 20.3, 21.2
    async fn run_day_phase(&mut self) {
        let day_number = self.current_day_number().await;

        // Broadcast GamePhaseChange (0x33) with night_chat_history from the
        // previous night (day_number - 1).  ChatSystem is not yet integrated
        // into GameState, so we pass None as documented in the task note.
        let night_chat_history: Option<Vec<crate::network::message::ChatEntry>> = None;

        let payload = crate::network::message::GamePhaseChange {
            phase: PhaseType::Day,
            day_number,
            duration_secs: 60,
            server_timestamp: unix_now(),
            night_chat_history,
        };

        let msg = match Message::from_json(MessageType::GamePhaseChange, &payload) {
            Ok(m) => m,
            Err(e) => {
                tracing::error!(room_id = %self.room_id, "Failed to serialize Day GamePhaseChange: {e}");
                return;
            }
        };
        self.broadcast_message(msg).await;

        // Wait 60 s; chat is handled directly by the Dispatcher — the Room
        // Runner only needs to drain non-relevant actions and wait for the
        // timer to expire.
        let deadline = tokio::time::sleep(Duration::from_secs(60));
        tokio::pin!(deadline);

        loop {
            tokio::select! {
                _ = &mut deadline => {
                    // Timer expired — advance to Vote phase.
                    break;
                }
                maybe_action = self.action_rx.recv() => {
                    match maybe_action {
                        Some(RoomAction::PlayerLeft { player_id }) => {
                            tracing::info!(
                                room_id = %self.room_id,
                                player_id = %player_id,
                                "Player left during day phase"
                            );
                        }
                        Some(_) => {
                            // Chat and other actions are handled by the Dispatcher;
                            // ignore them here.
                        }
                        None => {
                            // Channel closed — stop waiting.
                            break;
                        }
                    }
                }
            }
        }

        // Advance the phase machine: Day → Vote.
        {
            let mut state = self.app_state.write().await;
            if let Some(room_state) = state.rooms.get_mut(&self.room_id) {
                if let Some(game_state) = room_state.game_state.as_mut() {
                    game_state.phase_machine.next_phase();
                }
            }
        }
    }

    /// Vote phase: collect votes for 15 s, then resolve elimination.
    ///
    /// Requirements: 5.5, 17.1, 17.4, 17.5, 17.6, 21.3
    async fn run_vote_phase(&mut self) {
        let day_number = self.current_day_number().await;
        self.broadcast_phase_change(PhaseType::Vote, day_number, 15).await;

        // ── Collect Vote messages for 15 s ───────────────────────────────────
        let deadline = tokio::time::sleep(Duration::from_secs(15));
        tokio::pin!(deadline);

        // Collect votes locally so we can persist them after the timer.
        let mut collected_votes: Vec<(Uuid, Uuid)> = Vec::new();

        loop {
            tokio::select! {
                _ = &mut deadline => {
                    // Timer expired — stop collecting votes.
                    break;
                }
                maybe_action = self.action_rx.recv() => {
                    match maybe_action {
                        Some(RoomAction::Vote { voter_id, target_id }) => {
                            collected_votes.push((voter_id, target_id));
                            let mut state = self.app_state.write().await;
                            if let Some(room_state) = state.rooms.get_mut(&self.room_id) {
                                if let Some(game_state) = room_state.game_state.as_mut() {
                                    game_state.vote_system.cast_vote(voter_id, target_id);
                                }
                            }
                        }
                        Some(RoomAction::PlayerLeft { player_id }) => {
                            tracing::info!(
                                room_id = %self.room_id,
                                player_id = %player_id,
                                "Player left during vote phase"
                            );
                        }
                        Some(_) => {
                            // Ignore non-Vote messages during vote phase.
                        }
                        None => {
                            // Channel closed — stop collecting.
                            break;
                        }
                    }
                }
            }
        }

        // ── Invoke VoteSystem::resolve_vote() and collect deaths ─────────────
        let (vote_result, deaths) = {
            let mut state = self.app_state.write().await;
            if let Some(room_state) = state.rooms.get_mut(&self.room_id) {
                if let Some(game_state) = room_state.game_state.as_mut() {
                    let result = game_state.vote_system.resolve_vote(&mut game_state.participants);

                    // Build DeathInfo list for eliminated + extra_deaths.
                    let mut death_infos: Vec<crate::network::message::DeathInfo> = Vec::new();

                    let all_dead_ids: Vec<Uuid> = result
                        .eliminated
                        .iter()
                        .chain(result.extra_deaths.iter())
                        .cloned()
                        .collect();

                    for player_id in &all_dead_ids {
                        if let Some(p) = game_state.participants.get(player_id) {
                            death_infos.push(crate::network::message::DeathInfo {
                                player_id: *player_id,
                                username: p.username.clone(),
                                role_name: p
                                    .role
                                    .as_ref()
                                    .map(|r| r.name.clone())
                                    .unwrap_or_default(),
                            });
                        }
                    }

                    (result, death_infos)
                } else {
                    (
                        crate::game_logic::vote_system::VoteResult {
                            eliminated: None,
                            extra_deaths: vec![],
                            special_win: None,
                        },
                        vec![],
                    )
                }
            } else {
                (
                    crate::game_logic::vote_system::VoteResult {
                        eliminated: None,
                        extra_deaths: vec![],
                        special_win: None,
                    },
                    vec![],
                )
            }
        };

        // ── Persist vote and death records to DB ─────────────────────────────
        {
            let (db_pool, game_id, phase_id) = {
                let state = self.app_state.read().await;
                let pool = state.db_pool.clone();
                let (gid, pid) = state
                    .rooms
                    .get(&self.room_id)
                    .and_then(|r| r.game_state.as_ref())
                    .map(|gs| (gs.game_id, gs.phase_machine.phase_id))
                    .unwrap_or((Uuid::nil(), Uuid::nil()));
                (pool, gid, pid)
            };

            // Persist each vote cast this phase
            for (voter_id, candidate_id) in &collected_votes {
                if let Err(e) = crate::network::dispatcher::Dispatcher::persist_vote(
                    &db_pool,
                    &game_id,
                    &phase_id,
                    voter_id,
                    candidate_id,
                )
                .await
                {
                    tracing::error!(
                        room_id = %self.room_id,
                        voter_id = %voter_id,
                        error = %e,
                        "Failed to persist vote to DB"
                    );
                }
            }

            // Persist deaths from vote resolution
            let died_at = chrono::Utc::now();
            for death in &deaths {
                if let Err(e) = crate::network::dispatcher::Dispatcher::mark_player_dead(
                    &db_pool,
                    &game_id,
                    &death.player_id,
                    died_at,
                )
                .await
                {
                    tracing::error!(
                        room_id = %self.room_id,
                        player_id = %death.player_id,
                        error = %e,
                        "Failed to persist vote death to DB"
                    );
                }
            }
        }

        // ── Broadcast GameEvent (0x34) with VoteResult ───────────────────────
        let winner_faction = vote_result
            .special_win
            .as_ref()
            .map(|f| format!("{:?}", f));

        let event = GameEvent {
            event_type: GameEventType::VoteResult,
            deaths,
            winner_faction,
            extra: None,
        };

        let msg = match Message::from_json(MessageType::GameEvent, &event) {
            Ok(m) => m,
            Err(e) => {
                tracing::error!(room_id = %self.room_id, "Failed to serialize VoteResult GameEvent: {e}");
                return;
            }
        };
        self.broadcast_message(msg).await;

        // ── Check Win ────────────────────────────────────────────────────────
        let winner = {
            let state = self.app_state.read().await;
            let roles = &state.cached_roles;
            if let Some(room) = state.rooms.get(&self.room_id) {
                if let Some(gs) = &room.game_state {
                    WinChecker::check_win(&gs.participants, roles)
                } else {
                    None
                }
            } else {
                None
            }
        };
    }

    /// Check win conditions and, if a winner exists, broadcast GameOver.
    ///
    /// Returns `true` when the game is over (caller should stop the loop).
    ///
    /// Requirements: 5.6, 19.1–19.6
    async fn check_and_announce_winner(&self) -> bool {
        use crate::game_logic::win_checker::WinChecker;

        // ── Snapshot participants and game_id ────────────────────────────────
        let (participants, game_id) = {
            let state = self.app_state.read().await;
            let room_state = match state.rooms.get(&self.room_id) {
                Some(r) => r,
                None => return false,
            };
            let game_state = match room_state.game_state.as_ref() {
                Some(gs) => gs,
                None => return false,
            };
            (game_state.participants.clone(), game_state.game_id.clone())
        };

        // ── Check win conditions ─────────────────────────────────────────────
        let roles = {
            let state = self.app_state.read().await;
            state.cached_roles.clone()
        };
        let winning_faction = WinChecker::check_win(&participants, &roles);
        let faction = match winning_faction {
            Some(f) => f,
            None => return false,
        };

        let winner_faction_str = format!("{:?}", faction);

        // ── Persist game result to DB ────────────────────────────────────────
        let db_pool = {
            let state = self.app_state.read().await;
            state.db_pool.clone()
        };

        if let Err(e) = crate::network::dispatcher::Dispatcher::finish_game(
            &db_pool,
            &game_id,
            &winner_faction_str,
        )
        .await
        {
            tracing::error!(
                room_id = %self.room_id,
                game_id = %game_id,
                error = %e,
                "Failed to persist game result to DB"
            );
        }

        // ── Broadcast GameEvent (0x34) with GameOver ─────────────────────────
        let event = GameEvent {
            event_type: GameEventType::GameOver,
            deaths: vec![],
            winner_faction: Some(winner_faction_str.clone()),
            extra: None,
        };

        let msg = match Message::from_json(MessageType::GameEvent, &event) {
            Ok(m) => m,
            Err(e) => {
                tracing::error!(room_id = %self.room_id, "Failed to serialize GameOver event: {e}");
                return true; // still terminate the loop
            }
        };

        self.broadcast_message(msg).await;

        tracing::info!(
            room_id = %self.room_id,
            winner = %winner_faction_str,
            "Game over — winner announced"
        );

        true
    }

    // -----------------------------------------------------------------------
    // Helpers
    // -----------------------------------------------------------------------

    /// Broadcast a `GamePhaseChange (0x33)` frame to every participant in the room.
    async fn broadcast_phase_change(&self, phase: PhaseType, day_number: u32, duration_secs: u32) {
        let payload = GamePhaseChange {
            phase,
            day_number,
            duration_secs,
            server_timestamp: unix_now(),
            night_chat_history: None,
        };

        let msg = match Message::from_json(MessageType::GamePhaseChange, &payload) {
            Ok(m) => m,
            Err(e) => {
                tracing::error!(room_id = %self.room_id, "Failed to serialize GamePhaseChange: {e}");
                return;
            }
        };
        let bytes = msg.to_bytes();

        // Collect participant IDs while holding the read lock briefly.
        let participant_ids: Vec<Uuid> = {
            let state = self.app_state.read().await;
            state
                .rooms
                .get(&self.room_id)
                .and_then(|r| r.game_state.as_ref())
                .map(|gs| gs.participants.keys().cloned().collect())
                .unwrap_or_default()
        };

        for player_id in participant_ids {
            if let Some(sender) = self.registry.get(&player_id) {
                if sender.send(bytes.clone()).is_err() {
                    tracing::warn!(player_id = %player_id, "Write channel closed; removing from registry");
                    drop(sender);
                    self.registry.remove(&player_id);
                }
            }
        }
    }

    /// Read the current `day_number` from the room's phase machine.
    async fn current_day_number(&self) -> u32 {
        let state = self.app_state.read().await;
        state
            .rooms
            .get(&self.room_id)
            .and_then(|r| r.game_state.as_ref())
            .map(|gs| gs.phase_machine.day_number)
            .unwrap_or(1)
    }

    /// Broadcast an arbitrary `Message` to every participant in the room.
    async fn broadcast_message(&self, msg: Message) {
        let bytes = msg.to_bytes();

        let participant_ids: Vec<Uuid> = {
            let state = self.app_state.read().await;
            state
                .rooms
                .get(&self.room_id)
                .and_then(|r| r.game_state.as_ref())
                .map(|gs| gs.participants.keys().cloned().collect())
                .unwrap_or_default()
        };

        for player_id in participant_ids {
            if let Some(sender) = self.registry.get(&player_id) {
                if sender.send(bytes.clone()).is_err() {
                    tracing::warn!(player_id = %player_id, "Write channel closed; removing from registry");
                    drop(sender);
                    self.registry.remove(&player_id);
                }
            }
        }
    }
}

// ---------------------------------------------------------------------------
// Utility
// ---------------------------------------------------------------------------

fn unix_now() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs()
}
