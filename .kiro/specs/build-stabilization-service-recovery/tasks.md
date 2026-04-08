# Implementation Plan: Build Stabilization & Service Recovery

## Overview

Wire the "Are You Ghost?" game into a fully playable end-to-end multiplayer system. The implementation follows a bottom-up approach: protocol foundation → server state → command dispatching → game logic → room runner → database → Flutter listener → integration.

## Tasks

### Phase 1: Foundation — Protocol & Dependencies

- [x] 1. Add missing Cargo.toml dependencies
  - Add `dashmap = "5"` for the lock-free Connection Registry
  - Add `proptest = "1"` under `[dev-dependencies]` for property-based tests
  - Add `bcrypt = "0.15"` (or `argon2`) for password hashing
  - _Requirements: 1.3, 11.5, 25.2_

- [x] 2. Add new MessageType opcodes to `core/src/network/message.rs`
  - Add enum variants: `ReconnectRequest = 0x05`, `ReconnectResponse = 0x06`, `QuickJoinRequest = 0x17`, `QuickJoinResponse = 0x18`, `InvitePlayer = 0x1A`, `GameInviteReceived = 0x1B`
  - Add matching arms in `MessageType::from_byte()` for all six new opcodes
  - _Requirements: 8.1, 22.3_

- [x] 3. Add new payload structs to `core/src/network/message.rs`
  - Add `ReconnectRequest { session_id: String }`
  - Add `ReconnectResponse { success, room_id, phase, day_number, phase_remaining_secs, is_alive, role, error }`
  - Add `QuickJoinRequest { player_id: String }`
  - Add `QuickJoinResponse { room_id, current_players, lobby_remaining_secs }`
  - Add `InvitePlayerRequest { target_username: String, room_id: String }`
  - Add `GameInviteReceived { from_username: String, room_id: String, room_name: String }`
  - Add `RoomStateSync`, `ParticipantInfo`, `GamePhaseChange`, `GameEvent`, `DeathInfo`, `GameEventType` structs/enums
  - _Requirements: 8.1, 13.4, 22.3_

  - [ ]* 3.1 Write property test for protocol round-trip (P1)
    - **Property 1: Protocol Round-Trip** — for any valid `MessageType` and arbitrary payload bytes, `Message::to_bytes()` then `Message::from_bytes()` produces identical `msg_type` and `payload`
    - Use `proptest` with `any::<Vec<u8>>()` for payload and iterate over all known opcodes
    - **Validates: Requirements 8.1**

  - [ ]* 3.2 Write property test for CRC corruption rejection (P2)
    - **Property 2: CRC Corruption Rejection** — for any valid serialized frame, flipping any single bit in the payload region causes `Message::from_bytes()` to return `Err`
    - **Validates: Requirements 8.2**

  - [ ]* 3.3 Write property test for magic byte rejection (P3)
    - **Property 3: Magic Byte Rejection** — for any byte sequence where bytes 0–1 are not `[0xAE, 0x80]`, `Message::from_bytes()` returns `Err`
    - **Validates: Requirements 8.3**


### Phase 2: Server State & Connection Management

- [x] 4. Upgrade `AppState` in `core/src/game_logic/state.rs`
  - Add `sessions: HashMap<String, SessionInfo>` field (session_id → player_id + last_seen Instant)
  - Add `RoomMode` enum: `QuickPlay` | `Custom`
  - Add `lobby_start_time: Option<Instant>` to `RoomState`
  - Add `db_pool: sqlx::PgPool` to `AppState`
  - Add `host_id: String`, `action_tx: Option<mpsc::UnboundedSender<RoomAction>>`, `room_mode: RoomMode` to `RoomState`
  - Wrap `AppState` in `Arc<RwLock<AppState>>` at construction
  - _Requirements: 1.1, 1.3, 22.3, 27.2_

- [x] 5. Upgrade `core/src/network/tcp_server.rs` — split streams + DashMap registry
  - Replace `HashMap<SocketAddr, TcpStream>` with `Arc<DashMap<String, UnboundedSender<Bytes>>>` registry
  - Add `app_state: Arc<RwLock<AppState>>` field
  - Implement `run(&self)` accept loop that calls `handle_connection` per accepted stream
  - Implement `handle_connection()`: call `stream.into_split()`, create `mpsc::unbounded_channel::<Bytes>()`, register sender in registry keyed by a temporary `PlayerId`
  - Spawn Read Task: reads `OwnedReadHalf`, accumulates bytes until a full Areyoughost frame is available (9 + payload_length bytes), parses with `Message::from_bytes()`, forwards to `Dispatcher::handle()`
  - Spawn Write Task: drains `UnboundedReceiver<Bytes>`, writes to `OwnedWriteHalf`
  - On Read Task error (bad magic, CRC mismatch, payload > 10 MB): log and drop connection
  - On either task termination: cancel sibling, remove player from registry
  - _Requirements: 1.1, 1.2, 1.3, 1.4, 2.1, 2.2, 2.3, 2.4, 2.5_

  - [ ]* 5.1 Write property test for disconnect cleans registry (P10)
    - **Property 10: Disconnect Cleans Registry** — after a player's TCP connection drops (simulated read/write error), the DashMap registry contains no entry for that `PlayerId`
    - Use `tokio::test` with an in-process `TcpListener` + `TcpStream` pair; drop the client side and assert registry is empty
    - **Validates: Requirements 1.2, 1.4**


### Phase 3: Command Dispatcher

- [x] 6. Create `core/src/network/dispatcher.rs` — Dispatcher struct and opcode router
  - Define `Dispatcher { app_state: Arc<RwLock<AppState>>, registry: Arc<DashMap<String, UnboundedSender<Bytes>>> }`
  - Implement `pub async fn handle(&self, player_id: &str, msg: Message) -> Result<()>` with a `match msg.msg_type` routing all opcodes from the full opcode table (0x01–0xFF)
  - Unknown opcodes → send `Error (0xFF)` with descriptive payload and log
  - Deserialize all payloads with `msg.parse_binary::<T>()` and validate required fields before processing
  - Register `dispatcher.rs` in `core/src/network.rs` module
  - _Requirements: 4.5, 4.6_

- [x] 7. Implement `handle_login()` and `handle_register()` in `dispatcher.rs`
  - `handle_register()`: validate username length (3–20), query DB for uniqueness, hash password with bcrypt (cost ≥ 10), insert into `players` table, respond with `RegisterResponse (0x04)`
  - `handle_login()`: query DB for username, verify bcrypt hash, create `SessionInfo` in `AppState.sessions`, set player `online_status = 'online'` in DB, respond with `LoginResponse (0x02)` containing `session_id` and `player_id`, register player in Connection Registry
  - Do NOT log or transmit plaintext passwords
  - _Requirements: 11.1, 11.2, 11.3, 11.4, 11.5, 12.3, 25.2_

- [x] 8. Implement `handle_reconnect()` in `dispatcher.rs`
  - Look up `session_id` in `AppState.sessions`; if found and `last_seen` within 30 s, re-register player's new sender in DashMap, restore game state (role, alive status, current phase, remaining time), respond with `ReconnectResponse (0x06)` containing full state
  - If session expired or not found, respond with `Error (0xFF)` "session expired, please login"
  - _Requirements: 22.3, 26.5_

- [x] 9. Implement `handle_create_room()` and `handle_quick_join()` in `dispatcher.rs`
  - `handle_create_room()`: create `RoomState` with `room_mode = RoomMode::Custom`, insert room into DB, respond with `CreateRoomResponse (0x13)` containing `room_id`
  - `handle_quick_join()`: search `AppState.rooms` for a public room with `status = WAITING` and `players < 16`; if found, add player; if not found, create new public room with `room_mode = RoomMode::QuickPlay` and record `lobby_start_time = Instant::now()`; respond with `QuickJoinResponse (0x18)` containing `room_id`, `current_players`, `lobby_remaining_secs`
  - _Requirements: 13.1, 13.2_

- [x] 10. Implement `handle_invite_player()` in `dispatcher.rs`
  - Look up `target_username` in DB; verify player is online (in Connection Registry)
  - If not online, respond with `Error (0xFF)` "player not online"
  - If online, serialize `GameInviteReceived (0x1B)` and call `unicast(target_player_id, msg)`
  - _Requirements: 13.2_

- [x] 11. Implement `handle_join_room()` in `dispatcher.rs`
  - Validate room exists and `status != PLAYING`; if PLAYING respond with `Error (0xFF)` "game already in progress"
  - Add player to room's participant list in `AppState`, insert `room_members` record in DB
  - Serialize `RoomStateSync (0x20)` with full participant list and call `broadcast_to_room()`
  - _Requirements: 4.1, 13.2, 13.3, 13.4_

- [x] 12. Implement `handle_start_game()` in `dispatcher.rs`
  - Validate sender is room Host; if not, respond with `Error (0xFF)` "not room host"
  - Validate `participants.len() >= 4`; if not, respond with `Error (0xFF)` "need >= 4 players"
  - Validate room is not already PLAYING; if so, respond with `Error (0xFF)` "game already started"
  - Invoke `RoleDistributor::assign_roles(player_count, Some(random_seed))`, unicast each player's role via `JoinRoomResponse (0x15)`
  - Create `GameState`, persist game record to DB, spawn `RoomRunner` task, broadcast `GamePhaseChange (0x33)` for Night phase 1 (20 s)
  - _Requirements: 4.2, 9.1, 9.2, 9.3, 9.4, 9.5, 14.2, 25.6_

- [x] 13. Implement `handle_cast_vote()` and `handle_night_action()` in `dispatcher.rs`
  - `handle_cast_vote()`: validate player is alive and phase is Vote; if not, respond with `Error (0xFF)`; register vote in `VoteSystem` via `action_tx` channel to Room Runner
  - `handle_night_action()`: validate player is alive, phase is Night, and player's role has a night-active skill; if not, respond with `Error (0xFF)`; forward action to Room Runner via `action_tx`
  - _Requirements: 4.3, 4.4, 15.2, 15.3, 17.2, 17.3, 18.2_

- [x] 14. Implement `handle_chat()` in `dispatcher.rs`
  - Validate sender `is_alive`; if dead, respond with `Error (0xFF)` "dead players cannot chat"
  - Day phase: accept from all alive players, broadcast `ChatMessage (0x30)` to all alive players in room
  - Night phase: accept only from Ghost/Special faction players; if Villager, respond with `Error (0xFF)` "night chat restricted"; broadcast only to Ghost-faction players
  - _Requirements: 16.2, 16.3, 20.1, 20.2_

- [x] 15. Implement `broadcast_to_room()` and `unicast()` helpers in `dispatcher.rs`
  - `broadcast_to_room(room_id, msg)`: serialize with `msg.to_bytes()`, iterate room participants, send `Bytes` to each player's `UnboundedSender` in registry; on send failure, remove player from registry and continue
  - `unicast(player_id, msg)`: serialize and send to single player's channel; on failure, remove from registry
  - Both helpers must not hold locks that block other Tokio tasks
  - _Requirements: 3.1, 3.2, 3.3_


### Phase 4: Game Logic Upgrades

- [x] 16. Fix `PhaseMachine` in `core/src/game_logic/phase_machine.rs`
  - Change `PhaseMachine::new()` to set `current_phase = PhaseType::Night` and `phase_end_time = Self::now() + 20`
  - Fix `next_phase()` cycle to: `Night → Day` (day_number++, 60 s), `Day → Vote` (15 s), `Vote → Night` (20 s)
  - _Requirements: 21.5, 5.2, 5.3_

  - [ ]* 16.1 Write property test for phase machine cycle (P7)
    - **Property 7: Phase Machine Cycle** — for any starting `PhaseType`, calling `next_phase()` three times returns the machine to the original phase, and `day_number` increments by exactly 1 after each complete Night→Day→Vote cycle
    - **Validates: Requirements 21.5, 5.2, 5.3**

- [x] 17. Upgrade `NightResolver` in `core/src/game_logic/night_resolver.rs`
  - Implement full priority order: (1) PROTECT — Doctor marks `protected_targets`; (2) INFORMATION — Seer inspects faction (DeceiverGhost returns VILLAGER), Police inspects aura (QueenGhost returns GOOD), Monk blocks inspection on target, Medium views dead player's role; (3) KILL — Ghost/SK kill; check `protected_targets` before marking `is_alive = false`
  - Handle Soldier self-protect: if Soldier is targeted by KILL and `skill_usage < 1`, activate self-protect (consume 1 use), skip death
  - Return `Vec<DeathInfo>` with player_id, username, role_name for each death
  - _Requirements: 15.4, 15.5_

  - [ ]* 17.1 Write property test for night resolver protection invariant (P8)
    - **Property 8: Night Resolver Protection Invariant** — for any set of night actions containing at least one PROTECT targeting player P and at least one KILL targeting player P, `NightResolver::resolve()` shall not set `is_alive = false` for player P
    - **Validates: Requirements 15.4**

- [x] 18. Upgrade `VoteSystem` in `core/src/game_logic/vote_system.rs`
  - Fix `resolve_vote()` to return `None` on tie (two or more candidates tied for max votes)
  - After resolving the voted-out player, check if their role is `AvengerGhost`; if so, pick one random alive player and mark them dead (drag-to-death), include in returned deaths
  - Check if voted-out player's role is `Fool`; if so, signal Fool win immediately
  - Check `WinTrigger::DayVote` for Nemesis hidden target match; if match, signal Nemesis win
  - Return `VoteResult { eliminated: Option<String>, extra_deaths: Vec<String>, special_win: Option<Faction> }`
  - _Requirements: 17.4, 17.5, 17.6, 19.6_

  - [ ]* 18.1 Write property test for vote resolution correctness (P5)
    - **Property 5: Vote Resolution Correctness** — for any non-empty vote map, `resolve_vote()` returns `Some(id)` where `id` has strictly more votes than all others, or `None` if two or more candidates are tied for maximum
    - **Validates: Requirements 17.4, 17.5**

- [x] 19. Upgrade `WinChecker` in `core/src/game_logic/win_checker.rs`
  - Verify all 5 win conditions are correctly implemented: Villager (ghosts==0 AND sk==0), Ghost (ghost_count >= all others), SerialKiller (sk>0 AND total_alive<=2 AND ghosts==0), Draw (SK==1 AND Ghost==1 AND total==2), Nemesis (DayVote trigger AND nemesis.hidden_target == voted_out)
  - Ensure `living_nemesis` is excluded from the Ghost win denominator correctly
  - _Requirements: 19.1, 19.2, 19.3, 19.4, 19.5, 19.6_

  - [ ]* 19.1 Write property test for win condition correctness (P6)
    - **Property 6: Win Condition Correctness** — for any participant map where `living_ghosts == 0` and `living_sk == 0`, `check_win()` returns `Some(Faction::Villager)`; for any map where `living_ghosts >= living_villagers + living_sk + living_nemesis` (and ghosts > 0), returns `Some(Faction::Ghost)`
    - **Validates: Requirements 19.1, 19.2, 19.3**

- [x] 20. Upgrade `RoleDistributor` in `core/src/game_logic/role_distributor.rs`
  - Replace current simplified pool with the full 16-role pool using proper faction ratios for player counts 4–16
  - Support seeded random via `rand::rngs::StdRng::seed_from_u64(seed)` for reproducibility
  - Ensure exactly one role per player, no duplicates for `is_unique` roles
  - _Requirements: 9.1, 14.1, 14.5_

  - [ ]* 20.1 Write property test for role distribution count (P4)
    - **Property 4: Role Distribution Count** — for any player count N ≥ 1, `RoleDistributor::assign_roles(N, seed)` returns a `Vec<Role>` of length exactly N
    - **Validates: Requirements 9.1, 14.1**

- [x] 21. Upgrade `ChatSystem` in `core/src/game_logic/chat_system.rs`
  - Add `add_message(&mut self, msg: ChatMessage, phase: &PhaseType, sender_faction: &Faction) -> Result<(), ChatError>` with phase-aware validation
  - Return `ChatError::DeadPlayerCannotChat` if sender is dead
  - Return `ChatError::NightChatRestrictedToGhosts` if phase is Night and sender faction is Villager
  - Add `get_day_history(day_number: u32) -> Vec<&ChatMessage>`
  - Add `get_night_history(day_number: u32) -> Vec<&ChatMessage>` (ghost-only messages)
  - Add `get_night_history_for_villagers(day_number: u32) -> Vec<&ChatMessage>` (returns night ghost chat for villager review at day start)
  - Store messages keyed by `(room_id, day_number, scope)` for replay on reconnection
  - _Requirements: 16.2, 16.3, 20.1, 20.2, 20.3, 20.4_


### Phase 5: Room Runner (Authoritative Game Loop)

- [x] 22. Create `core/src/game_logic/room_task.rs` — RoomRunner struct and channel types
  - Define `RoomAction` enum: `Vote { voter_id, target_id }`, `NightAction { actor_id, action_type, target_id }`, `PlayerLeft { player_id }`
  - Define `RoomRunner { room_id: String, app_state: Arc<RwLock<AppState>>, registry: Arc<DashMap<...>>, action_rx: mpsc::UnboundedReceiver<RoomAction> }`
  - Implement `pub async fn run(mut self)` entry point that drives the phase loop: Night → Day → Vote → Night, calling `check_and_announce_winner()` after each phase
  - Register `room_task.rs` in `core/src/game_logic.rs` module
  - _Requirements: 5.1, 5.7_

- [x] 23. Implement `run_night_phase()` in `room_task.rs`
  - Broadcast `GamePhaseChange (0x33)` with `phase = Night`, `day_number`, `duration_secs = 20`, `server_timestamp = now()`
  - Use `tokio::select!` over `tokio::time::sleep(Duration::from_secs(20))` and `action_rx.recv()` to collect `NightAction` messages
  - On timeout or all expected actions received: invoke `NightResolver::resolve()`, collect `Vec<DeathInfo>`, update `is_alive` in `AppState`, persist deaths to DB
  - Broadcast `GameEvent (0x34)` with `event_type = NightResolution` and `deaths`
  - _Requirements: 5.2, 5.4, 15.1, 15.4, 15.5, 21.4_

- [x] 24. Implement `run_day_phase()` in `room_task.rs`
  - Broadcast `GamePhaseChange (0x33)` with `phase = Day`, `day_number`, `duration_secs = 60`, `server_timestamp`, and `night_chat_history` from `ChatSystem::get_night_history_for_villagers()`
  - Use `tokio::select!` over 60 s timer and `action_rx.recv()` to accept `ChatMessage` forwarding (Dispatcher routes chat; Room Runner just waits for timer)
  - On timeout: advance phase
  - _Requirements: 5.3, 16.1, 20.3, 21.2_

- [x] 25. Implement `run_vote_phase()` in `room_task.rs`
  - Broadcast `GamePhaseChange (0x33)` with `phase = Vote`, `duration_secs = 15`, `server_timestamp`
  - Use `tokio::select!` over 15 s timer and `action_rx.recv()` to collect `Vote` actions into `VoteSystem`
  - On timeout: invoke `VoteSystem::resolve_vote()`, apply eliminations (set `is_alive = false`), persist vote and death records to DB
  - Broadcast `GameEvent (0x34)` with `event_type = VoteResult`, `deaths`, and any `special_win` events (AvengerGhost, Fool, Nemesis)
  - _Requirements: 5.5, 17.1, 17.4, 17.5, 17.6, 21.3_

- [x] 26. Implement `check_and_announce_winner()` in `room_task.rs`
  - After each phase resolution, call `WinChecker::check_win(&participants, trigger)`
  - If a winning faction is found: broadcast `GameEvent (0x34)` with `event_type = GameOver`, `winner_faction`, persist `games.winner_faction` and `ended_at` to DB, return `true` to terminate the run loop
  - If no winner, return `false` to continue
  - _Requirements: 5.6, 19.1–19.6_

- [x] 27. Implement Quick Play lobby timer in `dispatcher.rs` / `room_task.rs`
  - When a QuickPlay room is created, spawn a background `tokio::task` that sleeps 120 s
  - On wake: if `participants.len() >= 4`, trigger auto-start (same flow as `handle_start_game()`); if `< 4`, disband room, send `Error (0xFF)` "not enough players, room closed" to all participants, remove room from `AppState`
  - If room fills to 16 players before 120 s, cancel the timer task and auto-start immediately
  - _Requirements: 5.1 (Quick Play mode)_

  - [ ]* 27.1 Write property test for broadcast completeness (P9)
    - **Property 9: Broadcast Completeness** — for any room with N registered participants in the Connection Registry, `broadcast_to_room(room_id, message)` attempts to send to exactly N channels, and the `Bytes` sent to each channel equals `message.to_bytes()`
    - Use an in-process registry with N mock `UnboundedSender` channels and assert all N receive the correct bytes
    - **Validates: Requirements 3.1**

- [x] 28. Checkpoint — Ensure all server-side tests pass
  - Ensure all tests pass, ask the user if questions arise.


### Phase 6: Database

- [x] 29. Create migration for `players` table additions
  - Add `online_status text NOT NULL DEFAULT 'offline' CHECK (online_status IN ('online','offline'))` column to existing `players` table (the base table already exists in `20240216000000_init.sql`)
  - Create new migration file `core/migrations/20240217000001_add_online_status.sql`
  - _Requirements: 7.4, 12.3, 12.4_

- [x] 30. Create migration for `rooms` and `room_members` table additions
  - Verify `rooms` and `room_members` tables match the design ER diagram (already exist in init migration); add any missing columns (e.g., `lobby_start_time timestamptz`)
  - Create migration file `core/migrations/20240217000002_rooms_additions.sql`
  - _Requirements: 7.4_

- [x] 31. Create migration for game tables additions
  - Verify `games`, `game_participants`, `game_phases`, `game_actions`, `votes`, `chat_messages` tables match the design ER diagram; add `day_number int` column to `chat_messages` for night history keying
  - Create migration file `core/migrations/20240217000003_game_tables_additions.sql`
  - _Requirements: 7.4, 20.4_

- [x] 32. Add full seed data migration for 16 roles + 11 skills + role_skills mappings
  - Create `core/migrations/20240217000004_seed_roles_skills.sql`
  - Insert all 16 role records with `ON CONFLICT (role_code) DO NOTHING` for idempotency: Villager, Seer, Doctor, Soldier, Police, Monk, Medium, Undertaker, Fool (Villager faction); Ghost, QueenGhost, AvengerGhost, DeceiverGhost, DarkShaman (Ghost faction); SerialKiller, Nemesis (Special faction)
  - Insert 11 skill records with `ON CONFLICT (skill_code) DO NOTHING`: KILL, PROTECT, INSPECT_FACTION, INSPECT_AURA, BLOCK_CHECK, VIEW_DEAD_ROLE, SILENCE, SELF_PROTECT (max_uses=1), DRAG_TO_DEATH (max_uses=1), FOOL_VICTORY (passive), HIDDEN_TARGET_WIN (passive)
  - Insert `role_skills` mappings with `ON CONFLICT (role_id, skill_id) DO NOTHING`
  - Include correct `seer_result`, `aura_result`, `faction`, `role_priority`, `is_unique`, `min_players`, `max_players` for each role
  - _Requirements: 7.1, 7.2, 7.3, 7.4, 7.5_

- [x] 33. Implement sqlx DB queries in `dispatcher.rs`
  - `register_player(username, password_hash)` → `INSERT INTO players`
  - `find_player_by_username(username)` → `SELECT` for login
  - `update_online_status(player_id, status)` → `UPDATE players SET online_status`
  - `create_room(owner_id, room_name, is_public)` → `INSERT INTO rooms`
  - `add_room_member(room_id, player_id)` → `INSERT INTO room_members`
  - `create_game(room_id, random_seed)` → `INSERT INTO games`
  - `insert_game_participant(game_id, player_id, role_id, seat_number)` → `INSERT INTO game_participants`
  - `persist_game_action(game_id, phase_id, actor_id, target_id, action_type)` → `INSERT INTO game_actions`
  - `persist_vote(game_id, phase_id, voter_id, candidate_id)` → `INSERT INTO votes`
  - `mark_player_dead(game_id, player_id, died_at)` → `UPDATE game_participants SET is_alive=false`
  - `finish_game(game_id, winner_faction)` → `UPDATE games SET game_status='FINISHED', winner_faction, ended_at`
  - _Requirements: 11.1, 11.3, 12.3, 12.4, 18.1, 26.4_


### Phase 7: Flutter Continuous Listener

- [x] 34. Add new opcodes to Dart `MessageType` enum
  - Locate the Dart `MessageType` enum in `frontend/lib/` (likely `services/network_service.dart` or a protocol file)
  - Add: `reconnectRequest(0x05)`, `reconnectResponse(0x06)`, `quickJoinRequest(0x17)`, `quickJoinResponse(0x18)`, `invitePlayer(0x1A)`, `gameInviteReceived(0x1B)`
  - _Requirements: 6.1, 8.1_

- [x] 35. Update `NetworkService` — implement `_startListenerLoop()` background async loop
  - In `frontend/lib/services/network_service.dart`, implement `void _startListenerLoop()` as an async loop that continuously reads bytes from `_socket`
  - Accumulate bytes in a `Uint8List` buffer; when `buffer.length >= 9 + payload_length` (parsed from bytes 3–6 as big-endian u32), slice exactly one frame and call `_parseFrame(frameBytes)`
  - Call `_startListenerLoop()` immediately after `connect()` succeeds
  - On socket error or EOF: set `isConnected = false`, close `_eventController`, notify UI
  - _Requirements: 6.1, 6.5, 6.6_

- [x] 36. Implement Dart frame parser `_parseFrame(Uint8List frame)` in `NetworkService`
  - Verify magic bytes `[0xAE, 0x80]`; if invalid, log and skip
  - Read type byte, payload length (4B BE), payload bytes, CRC16 (2B BE)
  - Verify CRC16-IBM-SDLC over `[type][length(4B)][payload]`; if mismatch, log and skip
  - Dispatch to the appropriate handler based on type byte
  - _Requirements: 6.1, 8.1, 8.2, 8.3_

- [x] 37. Handle `0x33 GamePhaseChange` in Flutter `NetworkService`
  - Deserialize payload (Bincode or JSON per current Dart implementation) into a `GamePhaseChange` model
  - Push a `PhaseChangeEvent` to `_eventController`
  - Start a local countdown timer from `duration_secs`; when timer hits 0, transition UI state to `WAITING_FOR_SERVER` (do not advance displayed phase)
  - _Requirements: 6.2, 21.1_

- [x] 38. Handle `0x34 GameEvent` in Flutter `NetworkService`
  - Deserialize payload into a `GameEvent` model
  - Push to `_eventController` so `GameScreen` can display death notifications, role reveals, or game-over screens
  - _Requirements: 6.3_

- [x] 39. Handle `0x20 RoomStateSync` in Flutter `NetworkService`
  - Deserialize payload into a `RoomStateSync` model
  - Update the local room model (participant list, online statuses)
  - Push a `RoomSyncEvent` to `_eventController` so `GameScreen` updates the player list
  - _Requirements: 6.4, 13.4_

- [x] 40. Handle `0x1B GameInviteReceived` in Flutter `NetworkService`
  - Deserialize payload into a `GameInviteReceived` model
  - Trigger Mail Noti sound asset playback
  - Push an `InviteEvent` to `_eventController` so the UI shows the invite overlay (new invite overwrites previous pending invite)
  - _Requirements: 23.1_

- [x] 41. Implement timer sync UI state in Flutter `GameScreen`
  - Add `TimerState` enum: `COUNTING_DOWN` | `WAITING_FOR_SERVER`
  - When local countdown reaches 0 and no new `0x33` has arrived, set state to `WAITING_FOR_SERVER` and display "Waiting for server..." overlay
  - When `0x33` is received, reset to `COUNTING_DOWN` with new `duration_secs`
  - The UI MUST NOT change the displayed phase until `0x33` is received
  - _Requirements: 6.2, 21.1_

- [x] 42. Implement reconnect logic in Flutter `NetworkService`
  - On successful login, store `session_id` in `SharedPreferences`
  - On socket drop (EOF or error), attempt to reconnect to the same host:port
  - On reconnect, send `ReconnectRequest (0x05)` with stored `session_id`
  - On `ReconnectResponse (0x06)` with `success = true`, restore local game state from payload and resume listener loop
  - On `success = false`, clear stored `session_id` and navigate to login screen
  - _Requirements: 22.3, 26.5_


### Phase 8: Integration & Verification

- [x] 43. Wire everything together in the main server binary
  - In `core/src/main.rs` (create if not exists) or `core/src/lib.rs`: initialize `sqlx::PgPool` from `DATABASE_URL` env var, construct `Arc<RwLock<AppState>>` with the pool, construct `Arc<DashMap>` registry, construct `Dispatcher`, call `TcpServer::bind("0.0.0.0:8888", app_state).await` and `server.run().await`
  - Initialize `tracing_subscriber` for structured logging
  - _Requirements: 1.1, 4.1, 28.2_

- [x] 44. End-to-end integration test: full game loop
  - Write an async integration test in `core/src/tests/integration.rs` (or `#[cfg(test)]` module)
  - Spawn an in-process `TcpServer` on a random port
  - Connect 2 in-process `TcpClient` instances, send `LoginRequest` for each, verify `LoginResponse` with `session_id`
  - Client 1 sends `CreateRoomRequest`, Client 2 sends `JoinRoomRequest`; assert both receive `RoomStateSync (0x20)` with 2 participants
  - Client 1 (host) sends `StartGame (0x11)`; assert both clients receive `JoinRoomResponse (0x15)` with role and `GamePhaseChange (0x33)` for Night phase
  - Wait 20 s (or mock timer); assert both clients receive `GameEvent (0x34)` for night resolution and `GamePhaseChange (0x33)` for Day
  - Wait 60 s; assert both clients receive `GamePhaseChange (0x33)` for Vote
  - Wait 15 s; assert both clients receive `GameEvent (0x34)` for vote result and `GamePhaseChange (0x33)` for Night
  - _Requirements: 10.1, 10.2, 10.3, 10.4, 10.5_

  - [ ]* 44.1 Verify reconnect: client drops socket mid-game, reconnects within 30 s, game state restored
    - In the integration test, after Night phase starts, drop Client 2's socket
    - Reconnect Client 2 within 30 s, send `ReconnectRequest (0x05)` with stored `session_id`
    - Assert `ReconnectResponse (0x06)` contains correct `phase`, `day_number`, `is_alive`, and `role`
    - Assert Client 2 continues to receive subsequent `GamePhaseChange` broadcasts
    - _Requirements: 22.3, 26.5_

  - [ ]* 44.2 Verify Quick Play: 2 clients QuickJoin → auto-start after 120 s timer → game begins at Night phase
    - Connect 2 clients, both send `QuickJoinRequest (0x17)`; assert both receive `QuickJoinResponse (0x18)` with same `room_id`
    - Wait for 120 s lobby timer to expire (use `tokio::time::pause()` + `advance()` for test speed)
    - Assert both clients receive `JoinRoomResponse (0x15)` with roles and `GamePhaseChange (0x33)` for Night phase
    - _Requirements: 5.1 (Quick Play auto-start)_

- [x] 45. Final checkpoint — Ensure all tests pass
  - Ensure all tests pass, ask the user if questions arise.

## Notes

- Tasks marked with `*` are optional and can be skipped for a faster MVP
- Each task references specific requirements for traceability
- Checkpoints at tasks 28 and 45 ensure incremental validation
- Property tests (P1–P10) validate universal correctness properties using `proptest`
- Unit tests validate specific examples and edge cases
- The phase order after ROLE_REVEAL is: Night (20 s) → Day (60 s) → Vote (15 s) → Night → ...
- `day_number` increments on Night → Day transition
- All DB writes happen before broadcasting results (Requirement 26.4)
- The Flutter client MUST NOT advance UI phase until `0x33 GamePhaseChange` is received from server
