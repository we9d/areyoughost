# Requirements Document

## Introduction

This document specifies the requirements for the "Build Stabilization & Service Recovery" feature — the final push to achieve end-to-end multiplayer playability for the "Are You Ghost?" (Ghost Village) social deduction game. The project uses a Rust backend (`core/`) with Tokio async runtime and a Flutter frontend (`frontend/`), communicating over a custom binary protocol (Areyoughost Protocol) on TCP port 8888.

The system supports 10–16 players per room across multiple concurrent game rooms. Players register and log in, join or create rooms, receive randomly assigned roles, and play through alternating Night and Day phases until a faction satisfies its win condition. The server is the sole authoritative source of truth; the Flutter client operates in a Zero-Trust model with no direct database access.

The current state has FFI bindings synced, a `NetworkService` singleton initialized, a stable Windows debug build, and frontend/backend aligned on the binary protocol. What remains is wiring up the authoritative server-side connection management, command dispatching, game loop orchestration, a continuous listener on the Flutter client, seeding the database with the 16 official roles and their skills, and implementing the full player-facing functional flows described in this document.

## Glossary

- **AppState**: The shared server-side state container holding all active rooms, player connections, and game sessions, protected by `Arc<RwLock<GameState>>`.
- **Areyoughost_Protocol**: The custom binary framing format: `[Magic 0xAE 0x80][Type 1B][Length 4B][Payload NB][CRC16 2B]`.
- **Bincode**: The binary serialization format used for payload encoding/decoding.
- **Broadcast_System**: A server-side function that iterates over all participants in a room and pushes a binary packet to each player's write channel.
- **Chat_System**: The module (`game_logic/chat_system.rs`) managing day-phase general chat and night-phase ghost-exclusive chat channels.
- **Connection_Registry**: A concurrent map (`DashMap<PlayerId, mpsc::UnboundedSender<Bytes>>`) inside AppState that tracks every connected player's outbound write channel.
- **Dispatcher**: A centralized command handler (`network/dispatcher.rs`) that routes inbound binary packets by opcode to the appropriate game logic handler.
- **Faction**: The alignment group a role belongs to — Villager, Ghost, or Special.
- **Game_Screen**: The Flutter widget (`ui/game/game_screen.dart`) that renders the active game state and reacts to server-pushed events.
- **Heartbeat**: A periodic keep-alive signal (opcode 0x50) sent by the client every 30 seconds to confirm the TCP connection is still alive.
- **Host**: The player who created the room and holds exclusive authority to issue the StartGame command.
- **Network_Service**: The Flutter singleton (`services/network_service.dart`) that manages the TCP socket connection and exposes game events to the UI.
- **Night_Resolver**: The module (`game_logic/night_resolver.rs`) that resolves all night actions (kills, protections, inspections) in priority order: Protection → Information → Action.
- **Opcode**: The 1-byte message type identifier in the Areyoughost Protocol (e.g., 0x14 = JoinRoomRequest, 0x33 = GamePhaseChange).
- **Phase_Machine**: The state machine (`game_logic/phase_machine.rs`) that tracks Day / Vote / Night phases and their durations (Day = 60 s, Vote = 15 s, Night = 20 s).
- **PlayerId**: A UUID string uniquely identifying a connected player.
- **Role_Distributor**: The module (`game_logic/role_distributor.rs`) that randomly assigns one role per player at game start.
- **Room_Runner**: An async task (`game_logic/room_task.rs`) that manages the authoritative game loop for a single room, including phase timeouts and automatic transitions.
- **Session**: A server-side record linking a PlayerId to an active TCP connection, preserved across brief disconnections to allow reconnection without losing game state.
- **TCP_Server**: The Tokio-based TCP listener (`network/tcp_server.rs`) that accepts incoming player connections on port 8888.
- **Vote_System**: The module (`game_logic/vote_system.rs`) that records player votes, tallies results, and resolves the eliminated player.
- **Win_Checker**: The module (`game_logic/win_checker.rs`) that evaluates faction counts after each phase resolution to determine if a win condition has been met.
- **Zero-Trust**: The architectural principle that the Flutter client holds no database credentials and cannot query the database directly; all state mutations go through the Rust server.

## Requirements

### Requirement 1: Connection Registry

**User Story:** As a server operator, I want every connected player to have a dedicated outbound write channel registered in AppState, so that the server can push messages to any player at any time.

#### Acceptance Criteria

1. WHEN a player establishes a TCP connection, THE TCP_Server SHALL create an `mpsc::UnboundedSender<Bytes>` channel and register it in the Connection_Registry keyed by PlayerId.
2. WHEN a player disconnects or the TCP connection drops, THE TCP_Server SHALL remove the corresponding entry from the Connection_Registry.
3. THE Connection_Registry SHALL use a `DashMap<PlayerId, mpsc::UnboundedSender<Bytes>>` to allow concurrent read and write access from multiple Tokio tasks without blocking.
4. IF a write to a player's channel fails (receiver dropped), THEN THE TCP_Server SHALL remove that player from the Connection_Registry and log the disconnection.

### Requirement 2: TCP Stream Splitting and Per-Connection Tasks

**User Story:** As a server developer, I want each TCP connection to be split into independent read and write halves, so that inbound parsing and outbound pushing can operate concurrently without contention.

#### Acceptance Criteria

1. WHEN a new TCP connection is accepted, THE TCP_Server SHALL call `into_split()` on the `TcpStream` to produce separate `OwnedReadHalf` and `OwnedWriteHalf` handles.
2. THE TCP_Server SHALL spawn a dedicated Write Task per connection that receives `Bytes` from the player's `mpsc::UnboundedReceiver` and writes them to the `OwnedWriteHalf`.
3. THE TCP_Server SHALL spawn a dedicated Read Task per connection that continuously reads from the `OwnedReadHalf`, parses complete Areyoughost Protocol frames (magic + type + length + payload + CRC16), and forwards parsed `Message` structs to the Dispatcher.
4. IF the Read Task encounters a malformed frame (invalid magic bytes, CRC mismatch, or payload exceeding 10 MB), THEN THE TCP_Server SHALL log the error and drop the connection.
5. IF either the Read Task or Write Task terminates, THEN THE TCP_Server SHALL cancel the sibling task and clean up the Connection_Registry entry.

### Requirement 3: Broadcast System

**User Story:** As a game engine, I want to broadcast a binary message to all active participants in a room, so that game state changes are pushed to every player simultaneously.

#### Acceptance Criteria

1. WHEN `broadcast_to_room(room_id, message)` is called, THE Broadcast_System SHALL serialize the message using `Message::to_bytes()` and send the resulting `Bytes` to every player's `UnboundedSender` in the Connection_Registry whose PlayerId is a participant of the specified room.
2. IF a player's channel send fails during broadcast, THEN THE Broadcast_System SHALL skip that player, remove the player from the Connection_Registry, and continue broadcasting to remaining participants.
3. THE Broadcast_System SHALL complete the broadcast without holding any locks that block other Tokio tasks from reading or writing to the Connection_Registry.

### Requirement 4: Command Dispatcher

**User Story:** As a server developer, I want a centralized dispatcher that routes inbound binary packets to the correct handler based on opcode, so that game commands are processed consistently.

#### Acceptance Criteria

1. WHEN a parsed Message with opcode 0x14 (JoinRoomRequest) is received, THE Dispatcher SHALL update the room's participant list in AppState and broadcast a RoomStateSync (0x20) message to all room members.
2. WHEN a parsed Message with opcode 0x11 (StartGame) is received, THE Dispatcher SHALL initialize roles using the Role_Distributor, persist the game session, and spawn a Room_Runner task for the room.
3. WHEN a parsed Message with opcode 0x31 (CastVote) is received, THE Dispatcher SHALL register the vote in the Vote_System and trigger a phase change to Night if a majority of alive players have voted.
4. WHEN a parsed Message with opcode 0x32 (NightAction) is received, THE Dispatcher SHALL register the action via the Night_Resolver for resolution at the end of the Night phase.
5. IF an unknown or unsupported opcode is received, THEN THE Dispatcher SHALL respond with an Error message (0xFF) containing a descriptive error payload and log the event.
6. THE Dispatcher SHALL deserialize all payloads using Bincode and validate required fields before processing.

### Requirement 5: Authoritative Room Runner

**User Story:** As a game designer, I want an authoritative server-side game loop per room that enforces phase durations and automatically transitions phases on timeout, so that the game progresses even if no player action triggers a transition.

#### Acceptance Criteria

1. WHEN a Room_Runner task is spawned for a room, THE Room_Runner SHALL use `tokio::select!` to listen for both incoming game actions (via an mpsc channel) and a phase timeout timer simultaneously.
2. WHILE the Phase_Machine is in the Night phase, THE Room_Runner SHALL set a timeout of 20 seconds and broadcast a GamePhaseChange (0x33) message to all room participants when the timeout expires.
3. WHILE the Phase_Machine is in the Day phase, THE Room_Runner SHALL set a timeout of 60 seconds and broadcast a GamePhaseChange (0x33) message to all room participants when the timeout expires.
4. WHEN the Night phase ends (by timeout or all actions received), THE Room_Runner SHALL invoke the Night_Resolver to resolve all pending actions and broadcast a GameEvent (0x34) message containing death and effect results.
5. WHEN the Vote phase ends (by timeout or majority vote reached), THE Room_Runner SHALL invoke the Vote_System to resolve the vote, apply eliminations, and broadcast a GameEvent (0x34) message with the result.
6. AFTER each phase resolution, THE Room_Runner SHALL invoke the Win_Checker and, if a winning faction is determined, broadcast a GameEvent (0x34) with the game result and terminate the Room_Runner task.
7. IF all players disconnect from a room, THEN THE Room_Runner SHALL terminate the game loop and clean up the room state.

### Requirement 6: Flutter Continuous Listener

**User Story:** As a player, I want my Flutter client to continuously listen for server-pushed binary packets, so that I see phase changes, game events, and death notifications in real time without polling.

#### Acceptance Criteria

1. WHEN the Network_Service establishes a TCP connection, THE Network_Service SHALL start a background loop that continuously reads and parses Areyoughost Protocol frames from the socket.
2. WHEN a GamePhaseChange (0x33) packet is received, THE Network_Service SHALL deserialize the payload and push a phase-change event to a `StreamController` so that the Game_Screen can update the UI immediately.
3. WHEN a GameEvent (0x34) packet is received, THE Network_Service SHALL deserialize the payload and push a game-event to the `StreamController` so that the Game_Screen can display death notifications, role reveals, or game-over screens.
4. WHEN a RoomStateSync (0x20) packet is received, THE Network_Service SHALL update the local room model and notify the Game_Screen of player join/leave changes.
5. IF the background listener encounters a socket error or EOF, THEN THE Network_Service SHALL set `isConnected` to false, close the `StreamController`, and notify the UI of the disconnection.
6. THE Network_Service SHALL expose a `Stream<GameEvent>` that the Game_Screen subscribes to for reactive UI updates.

### Requirement 7: Database Role and Skill Seed Data

**User Story:** As a game designer, I want the database to contain all 16 official roles with their Thai-language descriptions and the shared skill definitions, so that the server can distribute roles and validate skill usage from a single source of truth.

#### Acceptance Criteria

1. THE Database migration SHALL insert 16 role records into the `roles` table covering Villager faction (Villager, Seer, Doctor, Soldier, Police, Monk, Medium, Undertaker, Fool), Ghost faction (Ghost, QueenGhost, AvengerGhost, DeceiverGhost, DarkShaman), and Special faction (SerialKiller, Nemesis).
2. THE Database migration SHALL insert skill records into the `skills` table for shared skills: KILL (Night), PROTECT (Night), INSPECT_FACTION (Night), INSPECT_AURA (Night), BLOCK_CHECK (Night), VIEW_DEAD_ROLE (Night), SILENCE (Night), SELF_PROTECT (Night, max 1 use), DRAG_TO_DEATH (Night, max 1 use), FOOL_VICTORY (Day, passive), and HIDDEN_TARGET_WIN (Day, passive).
3. THE Database migration SHALL insert role-skill mapping records into the `role_skills` table linking each role to its applicable skills.
4. EACH role record SHALL include `role_code`, `role_name` (Thai), `faction`, `description` (Thai), `seer_result`, `aura_result`, `min_players`, `max_players`, `is_unique`, `is_enabled`, and `role_priority` fields matching the existing schema constraints.
5. THE seed data migration SHALL be idempotent — running the migration multiple times SHALL produce the same result without duplicate records (using `ON CONFLICT DO NOTHING` or equivalent).

### Requirement 8: Binary Protocol Integrity

**User Story:** As a network engineer, I want the binary protocol serialization and deserialization to be verified end-to-end, so that no data corruption occurs between Flutter client and Rust server.

#### Acceptance Criteria

1. FOR ALL valid Message structs, serializing with `Message::to_bytes()` then deserializing with `Message::from_bytes()` SHALL produce an equivalent Message (round-trip property).
2. WHEN a frame with an invalid CRC16 trailer is received, THE Message parser SHALL return an error and reject the frame.
3. WHEN a frame with invalid magic bytes is received, THE Message parser SHALL return an error and reject the frame.
4. THE Message serializer SHALL encode the payload length as a 4-byte Big-Endian unsigned integer.
5. THE CRC16 checksum SHALL be computed over the Type byte, Length bytes, and Payload bytes using the IBM-SDLC (CCITT) algorithm.

### Requirement 9: Start Game Command Flow

**User Story:** As a room host, I want to press "Start Game" and have the server assign roles, notify all players of their role, and begin the first Day phase, so that the game begins seamlessly.

#### Acceptance Criteria

1. WHEN the Dispatcher receives a StartGame command (0x11) from the room Host, THE Dispatcher SHALL invoke the Role_Distributor to assign roles to all participants in the room.
2. WHEN roles are assigned, THE Dispatcher SHALL send each player a personalized JoinRoomResponse (0x15) containing only that player's own role information (not other players' roles).
3. WHEN all role assignments are sent, THE Dispatcher SHALL spawn a Room_Runner task and broadcast a GamePhaseChange (0x33) indicating the start of Day phase 1 with a 60-second timer.
4. IF the room has fewer than 4 players when StartGame is received, THEN THE Dispatcher SHALL respond with an Error (0xFF) message indicating insufficient players.
5. IF a StartGame command is received for a room that is already in PLAYING status, THEN THE Dispatcher SHALL respond with an Error (0xFF) message indicating the game has already started.

### Requirement 10: End-to-End Playability Verification

**User Story:** As a developer, I want to verify that two Flutter Windows clients can connect to the server and complete a full game loop (login → room join → start game → role reveal → night/day transitions), so that the system is confirmed playable.

#### Acceptance Criteria

1. WHEN two Flutter clients connect to the TCP_Server on port 8888, THE TCP_Server SHALL accept both connections and register them in the Connection_Registry.
2. WHEN both clients send JoinRoomRequest (0x14), THE Dispatcher SHALL add both players to the room and broadcast RoomStateSync (0x20) to both.
3. WHEN the Host client sends StartGame (0x11), THE Dispatcher SHALL assign roles and both clients SHALL receive their role assignment and a GamePhaseChange (0x33) for Day phase 1.
4. WHEN the Day phase timer expires, THE Room_Runner SHALL broadcast a GamePhaseChange (0x33) transitioning to the Vote phase, and both clients SHALL update their UI accordingly.
5. WHEN the Night phase completes, THE Room_Runner SHALL broadcast a GameEvent (0x34) with night resolution results, and both clients SHALL display death notifications if applicable.

### Requirement 11: Player Registration and Login

**User Story:** As a new user, I want to register an account and log in, so that my identity and game history are persisted across sessions.

#### Acceptance Criteria

1. WHEN a RegisterRequest (0x03) is received with a username and password, THE Dispatcher SHALL validate that the username is unique in the database before creating the account.
2. IF the requested username already exists, THEN THE Dispatcher SHALL respond with a RegisterResponse (0x04) containing an error indicating the username is taken.
3. WHEN a LoginRequest (0x01) is received with valid credentials, THE Dispatcher SHALL create a Session record, respond with a LoginResponse (0x02) containing a `session_id` and `player_id`, and register the player in the Connection_Registry.
4. IF a LoginRequest is received with invalid credentials, THEN THE Dispatcher SHALL respond with a LoginResponse (0x02) where `success` is false and `error` contains a descriptive message.
5. THE Dispatcher SHALL store passwords as bcrypt hashes and SHALL NOT store or transmit plaintext passwords.
6. WHEN a player sends a Heartbeat (0x50), THE TCP_Server SHALL update the Session's last-seen timestamp and respond with a Heartbeat (0x50) acknowledgement within 5 seconds.

### Requirement 12: Player Profile Management

**User Story:** As a registered player, I want to update my username and view my online status, so that I can manage my identity in the game.

#### Acceptance Criteria

1. WHEN a player submits a username-change request with a new username, THE Dispatcher SHALL validate that the new username is unique before persisting the change.
2. IF the new username is already taken, THEN THE Dispatcher SHALL respond with an error indicating the conflict.
3. WHEN a player establishes a TCP connection and completes login, THE Dispatcher SHALL set that player's status to "online" in the database.
4. WHEN a player's TCP connection closes or a Disconnect (0x70) message is received, THE Dispatcher SHALL set that player's status to "offline" in the database.

### Requirement 13: Game Room Management

**User Story:** As a player, I want to create or join a game room and see the current player list, so that I can organize a game session with others.

#### Acceptance Criteria

1. WHEN a CreateRoomRequest (0x12) is received, THE Dispatcher SHALL create a new room record, designate the requesting player as Host, and respond with a CreateRoomResponse (0x13) containing the room ID.
2. WHEN a JoinRoomRequest (0x14) is received for an existing room that is not yet in PLAYING status, THE Dispatcher SHALL add the player to the room's participant list and broadcast a RoomStateSync (0x20) to all current room members.
3. IF a JoinRoomRequest is received for a room already in PLAYING status, THEN THE Dispatcher SHALL respond with an Error (0xFF) indicating the game is already in progress.
4. WHEN a RoomStateSync (0x20) is broadcast, THE Broadcast_System SHALL include the full current participant list with each player's username and online status.
5. WHILE a room is in LOBBY status, THE Game_Screen SHALL display the Host indicator and a "Start Game" button only for the player whose PlayerId matches the room's Host field.

### Requirement 14: Role Assignment and Privacy

**User Story:** As a player, I want to receive my role privately at game start, so that other players cannot learn my role from the network traffic.

#### Acceptance Criteria

1. WHEN the Role_Distributor assigns roles, THE Role_Distributor SHALL randomly shuffle the selected role pool and assign exactly one role per participant.
2. THE Dispatcher SHALL send each player's role information in a separate unicast message addressed only to that player's PlayerId — not as a broadcast.
3. THE Dispatcher SHALL NOT include any other player's role in the role-assignment message sent to a given player.
4. WHEN a player receives their role assignment, THE Game_Screen SHALL display the role name, faction, and skill description only to that player.
5. WHERE a room configuration includes multiple role types from the same faction, THE Role_Distributor SHALL support assigning more than one instance of non-unique roles (e.g., multiple Villagers).

### Requirement 15: Night Phase System

**User Story:** As a player with a night-active role, I want to submit my night action during the Night phase, so that my skill is resolved by the server at the end of the night.

#### Acceptance Criteria

1. WHEN the Phase_Machine transitions to Night, THE Room_Runner SHALL broadcast a GamePhaseChange (0x33) with phase type Night and a 20-second countdown.
2. WHILE the Phase_Machine is in the Night phase, THE Dispatcher SHALL accept NightAction (0x32) messages only from players whose role has a night-active skill.
3. IF a NightAction (0x32) is received from a player whose role has no night-active skill, THEN THE Dispatcher SHALL respond with an Error (0xFF) indicating the action is not permitted.
4. WHEN the Night phase ends, THE Night_Resolver SHALL apply actions in priority order: Protection first, then Information (Inspect), then Kill actions.
5. WHEN night resolution is complete, THE Room_Runner SHALL broadcast a GameEvent (0x34) listing which players were eliminated and which protection effects were applied, without revealing the identities of the acting players.

### Requirement 16: Day Phase and Discussion Chat

**User Story:** As a player, I want to chat with other alive players during the Day phase, so that I can discuss and coordinate before voting.

#### Acceptance Criteria

1. WHEN the Phase_Machine transitions to Day, THE Room_Runner SHALL broadcast a GamePhaseChange (0x33) with phase type Day, the current day number, and a 60-second countdown.
2. WHILE the Phase_Machine is in the Day phase, THE Chat_System SHALL accept ChatMessage (0x30) messages from all alive players and broadcast each message to all alive players in the room.
3. IF a ChatMessage (0x30) is received from a player whose `is_alive` status is false, THEN THE Dispatcher SHALL reject the message with an Error (0xFF) indicating dead players cannot send day-phase chat.
4. WHEN a GamePhaseChange (0x33) for Day is broadcast, THE Broadcast_System SHALL include the current count of alive players in the payload.

### Requirement 17: Voting System

**User Story:** As an alive player, I want to cast a vote during the Vote phase to eliminate a suspect, so that the group can remove a potential threat.

#### Acceptance Criteria

1. WHEN the Phase_Machine transitions to Vote, THE Room_Runner SHALL broadcast a GamePhaseChange (0x33) with phase type Vote and a 15-second countdown.
2. WHILE the Phase_Machine is in the Vote phase, THE Dispatcher SHALL accept CastVote (0x31) messages only from players whose `is_alive` status is true.
3. IF a CastVote (0x31) is received from a player whose `is_alive` status is false, THEN THE Dispatcher SHALL respond with an Error (0xFF) indicating dead players cannot vote.
4. WHEN the Vote phase ends, THE Vote_System SHALL tally all received votes, determine the player with the most votes, and return that PlayerId as the eliminated player.
5. IF two or more players are tied for the most votes at the end of the Vote phase, THE Vote_System SHALL select no elimination (no-vote result) and broadcast a GameEvent (0x34) indicating a tie.
6. WHEN the eliminated player is determined, THE Room_Runner SHALL broadcast a GameEvent (0x34) containing the eliminated player's username and role.

### Requirement 18: Player Elimination

**User Story:** As a game engine, I want eliminated players to be marked as dead and restricted from game actions, so that the game state remains consistent.

#### Acceptance Criteria

1. WHEN a player is eliminated (by night kill or day vote), THE Room_Runner SHALL set that player's `is_alive` field to false in AppState and persist the change to the database.
2. AFTER a player is eliminated, THE Dispatcher SHALL reject any CastVote (0x31) or NightAction (0x32) messages from that player with an Error (0xFF).
3. WHEN a player is eliminated, THE Broadcast_System SHALL send a GameEvent (0x34) to all room participants containing the eliminated player's username and revealed role.
4. AFTER elimination, THE Game_Screen SHALL display the eliminated player with a visual "Dead" indicator in the player list.

### Requirement 19: Win Condition Checking

**User Story:** As a player, I want the game to automatically detect and announce the winning faction after each elimination, so that the game ends correctly without manual intervention.

#### Acceptance Criteria

1. AFTER every night resolution and every vote resolution, THE Win_Checker SHALL evaluate the current alive player counts to determine if any faction's win condition is satisfied.
2. WHEN the Win_Checker determines that the Villager faction wins (all Ghosts and Serial Killers are dead), THE Room_Runner SHALL broadcast a GameEvent (0x34) announcing Villager victory and terminate the Room_Runner task.
3. WHEN the Win_Checker determines that the Ghost faction wins (Ghost count equals or exceeds the combined count of all other alive players), THE Room_Runner SHALL broadcast a GameEvent (0x34) announcing Ghost victory and terminate the Room_Runner task.
4. WHEN the Win_Checker determines that the Serial Killer wins (Serial Killer is the last or second-to-last player alive with no Ghosts remaining), THE Room_Runner SHALL broadcast a GameEvent (0x34) announcing Serial Killer victory and terminate the Room_Runner task.
5. WHEN the Win_Checker determines a draw condition (e.g., Serial Killer vs. one Ghost remaining), THE Room_Runner SHALL broadcast a GameEvent (0x34) announcing a draw and terminate the Room_Runner task.
6. WHEN the Nemesis win condition is triggered (the Nemesis's hidden target is voted out), THE Win_Checker SHALL detect this during the DayVote trigger and THE Room_Runner SHALL broadcast a GameEvent (0x34) announcing Nemesis victory.

### Requirement 20: Chat Room System (Night Ghost Chat and History)

**User Story:** As a Ghost-faction player, I want a private night chat channel, and as a Villager-faction player I want to read the night chat history after the night ends, so that information asymmetry is preserved correctly.

#### Acceptance Criteria

1. WHILE the Phase_Machine is in the Night phase, THE Chat_System SHALL accept ChatMessage (0x30) messages only from players whose Faction is Ghost or Special (night-active roles) and broadcast those messages only to other Ghost-faction players in the room.
2. IF a ChatMessage (0x30) is received during the Night phase from a Villager-faction player, THEN THE Dispatcher SHALL reject the message with an Error (0xFF) indicating night chat is restricted.
3. WHEN the Night phase ends and Day begins, THE Chat_System SHALL make the night chat history readable to all alive Villager-faction players by including it in the GamePhaseChange (0x33) payload or a follow-up broadcast.
4. THE Chat_System SHALL store night chat messages in an ordered log keyed by room ID and day number so that history can be replayed on reconnection.

### Requirement 21: Time Management and Phase Auto-Transition

**User Story:** As a player, I want each phase to have a visible countdown timer and to transition automatically when time runs out, so that the game never stalls waiting for slow players.

#### Acceptance Criteria

1. WHEN the Phase_Machine enters any phase, THE Room_Runner SHALL include the phase duration in seconds in the GamePhaseChange (0x33) broadcast so that all clients can display a synchronized countdown.
2. WHEN the Day phase timer (60 seconds) expires without a manual transition, THE Room_Runner SHALL automatically advance the Phase_Machine to the Vote phase and broadcast a GamePhaseChange (0x33).
3. WHEN the Vote phase timer (15 seconds) expires, THE Room_Runner SHALL resolve the current vote tally and advance the Phase_Machine to the Night phase.
4. WHEN the Night phase timer (20 seconds) expires, THE Room_Runner SHALL invoke the Night_Resolver and advance the Phase_Machine to the next Day phase.
5. THE Phase_Machine SHALL enforce the phase order: Day → Vote → Night → Day (repeating), incrementing the day number after each Night phase.

### Requirement 22: Game Control — Leave and Disconnection Handling

**User Story:** As a player, I want to be able to leave a game in progress, and I want the server to handle unexpected disconnections gracefully, so that the game can continue for remaining players.

#### Acceptance Criteria

1. WHEN a player sends a LeaveRoomRequest (0x16) during an active game, THE Dispatcher SHALL mark that player as eliminated (is_alive = false), broadcast a GameEvent (0x34) notifying remaining players, and invoke the Win_Checker.
2. WHEN a player's TCP connection drops without a LeaveRoomRequest, THE TCP_Server SHALL detect the disconnection via a failed write or read error, mark the player as eliminated, and broadcast a GameEvent (0x34) to remaining players.
3. IF a disconnected player reconnects within 30 seconds using the same `session_id`, THEN THE Dispatcher SHALL restore the player's game state (role, alive status, phase) and re-register the player in the Connection_Registry without treating the disconnection as an elimination.
4. WHEN a player leaves or disconnects, THE Win_Checker SHALL be invoked to check if the remaining player distribution satisfies any win condition.
5. WHILE a room is in LOBBY status (game not yet started), THE Dispatcher SHALL allow a player to leave without triggering elimination logic, and SHALL broadcast an updated RoomStateSync (0x20) to remaining lobby members.

### Requirement 23: Notification Sounds

**User Story:** As a player, I want to hear an audio notification when I receive a game invitation, so that I am alerted even when the app is in the background.

#### Acceptance Criteria

1. WHEN a RoomStateSync (0x20) is received indicating the local player has been added to a room by another player (invitation flow), THE Game_Screen SHALL play the game invitation sound asset.
2. THE Game_Screen SHALL provide a volume adjustment control that persists the player's preferred volume level across sessions using local storage.
3. WHERE the device volume is set to zero or the player has muted notifications, THE Game_Screen SHALL suppress the invitation sound without error.

---

## Non-Functional Requirements

### Requirement 24: Performance

**User Story:** As a player, I want the game to respond quickly to my actions and transitions, so that the experience feels smooth and real-time.

#### Acceptance Criteria

1. WHEN a player submits any game action (vote, night action, chat), THE Dispatcher SHALL process the action and send a response or broadcast within 15 seconds under normal server load.
2. WHEN a phase transition is triggered (by timeout or player action), THE Room_Runner SHALL broadcast the GamePhaseChange (0x33) to all room participants within 5 seconds of the trigger.
3. THE system SHALL support 10 to 16 players per room without degradation in message delivery latency.
4. WHEN a ChatMessage (0x30) is sent by a player, THE Chat_System SHALL broadcast the message to all eligible recipients within 3 seconds.
5. THE TCP_Server SHALL support multiple concurrent game rooms without one room's load causing message delays exceeding 5 seconds in another room.

### Requirement 25: Security

**User Story:** As a system operator, I want all player data and communications to be protected, so that the game is resistant to cheating and unauthorized access.

#### Acceptance Criteria

1. THE Dispatcher SHALL reject any game action (NightAction, CastVote, StartGame) from a player whose Session is not authenticated (no valid `session_id`).
2. THE Dispatcher SHALL store all player passwords as bcrypt hashes with a minimum cost factor of 10 and SHALL NOT log or transmit plaintext passwords.
3. THE Dispatcher SHALL send each player only their own role information and SHALL NOT include other players' roles in any unicast or broadcast message during an active game.
4. THE TCP_Server SHALL use TLS over the TCP connection to encrypt all Areyoughost Protocol frames in transit.
5. THE Dispatcher SHALL validate the CRC16 checksum of every inbound frame before processing and SHALL reject frames with checksum mismatches.
6. THE Dispatcher SHALL enforce that only the room Host can issue a StartGame (0x11) command, rejecting the command with an Error (0xFF) if issued by a non-Host player.

### Requirement 26: Reliability

**User Story:** As a player, I want the game server to remain available and recover from failures without losing critical game state, so that games are not interrupted unexpectedly.

#### Acceptance Criteria

1. THE TCP_Server SHALL maintain 99% uptime measured over any 30-day period, excluding scheduled maintenance windows.
2. WHEN an unhandled error occurs in a Room_Runner task, THE Room_Runner SHALL log the error with full context and attempt to resume from the last known Phase_Machine state before terminating.
3. IF a Room_Runner task terminates unexpectedly, THEN THE TCP_Server SHALL broadcast an Error (0xFF) to all room participants notifying them of the interruption.
4. THE system SHALL persist all game actions (votes, night actions, eliminations) to the database before broadcasting results, ensuring no critical game data is lost on server restart.
5. WHEN a player reconnects within 30 seconds using a valid `session_id`, THE Dispatcher SHALL restore the player's full game state without requiring re-authentication.

### Requirement 27: Scalability

**User Story:** As a system operator, I want the server to handle multiple concurrent game rooms and growing player counts, so that the system can support a larger user base without architectural changes.

#### Acceptance Criteria

1. THE TCP_Server SHALL support multiple concurrent game rooms, each with an independent Room_Runner task, without shared mutable state between rooms.
2. THE AppState SHALL use `Arc<RwLock<GameState>>` to allow concurrent read access from all Room_Runner tasks while serializing write operations.
3. WHEN the number of concurrent rooms increases, THE TCP_Server SHALL spawn additional Room_Runner tasks dynamically without requiring a server restart.
4. THE Connection_Registry SHALL use `DashMap` to allow lock-free concurrent access from all active Room_Runner and Dispatcher tasks.

### Requirement 28: Maintainability

**User Story:** As a developer, I want the codebase to be modular and well-documented, so that new roles and features can be added without breaking existing functionality.

#### Acceptance Criteria

1. THE `game_logic/roles.rs` module SHALL define all role types as a `RoleType` enum so that adding a new role requires only adding a new enum variant and its `Role::new()` match arm.
2. THE server SHALL emit structured log entries (using `tracing` or equivalent) for every Dispatcher routing decision, phase transition, and player elimination, including the room ID, player ID, and timestamp.
3. THE `build.rs` script SHALL auto-generate role enum bindings from the database schema so that the Rust role enum and the database `roles` table remain in sync.
4. EACH game logic module (Phase_Machine, Vote_System, Night_Resolver, Win_Checker, Chat_System) SHALL be independently testable with unit tests that do not require a live database or TCP connection.

### Requirement 29: Data Privacy

**User Story:** As a player, I want the system to collect only the data necessary to operate the game and to protect my personal information, so that my privacy is respected.

#### Acceptance Criteria

1. THE system SHALL collect only the following player data: username, bcrypt-hashed password, online status, and game participation history.
2. THE Dispatcher SHALL NOT log message payloads that contain player credentials (LoginRequest, RegisterRequest).
3. THE system SHALL provide a clear privacy policy accessible from the login/register screen describing what data is collected and how it is used.
4. THE database SHALL NOT store plaintext passwords, payment information, or government-issued identifiers.
5. WHEN a player requests account deletion, THE Dispatcher SHALL remove the player's username and password hash from the database within 30 days, retaining only anonymized game history records.
