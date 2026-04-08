# Design Document — Build Stabilization & Service Recovery
## Are You Ghost? — End-to-End Multiplayer Playability

---

## Overview

This document describes the technical design for wiring the "Are You Ghost?" game into a fully playable end-to-end multiplayer system. The existing codebase has a stable Flutter frontend, a Rust `core/` library with game logic modules, and a PostgreSQL database. What is missing is the authoritative server-side connection management, command dispatching, game loop orchestration, a continuous Flutter listener, and database seed data for the 16 official roles.

The design follows a **Zero-Trust Client Isolation** model: the Flutter client holds no database credentials and communicates exclusively through the Areyoughost binary protocol over TCP port 8888. All game state mutations are authoritative on the server.

---

## Architecture

### 1. System Architecture

The system is composed of three tiers connected by the Areyoughost binary protocol and SQL respectively.

```mermaid
graph TB
    subgraph "Client Tier — Zero-Trust"
        Flutter["Flutter Desktop App\n(Windows / Android)"]
        NS["NetworkService singleton\n(dart:io Socket)"]
        SC["StreamController&lt;GameEvent&gt;"]
        GS["GameScreen Widget"]
        Flutter --> NS
        NS --> SC
        SC --> GS
    end

    subgraph "Server Tier — Authoritative"
        TCP["Tokio TCP Listener\nport 8888"]
        HTTP["Axum HTTP Server\nport 3000 (health/admin)"]
        APP["Arc&lt;RwLock&lt;AppState&gt;&gt;"]
        REG["DashMap&lt;PlayerId,\nUnboundedSender&lt;Bytes&gt;&gt;\n(Connection Registry)"]
        DISP["Dispatcher\n(network/dispatcher.rs)"]
        RR["Room Runner tasks\n(game_logic/room_task.rs)"]
        TCP --> APP
        TCP --> REG
        TCP --> DISP
        DISP --> RR
        APP --> REG
    end

    subgraph "Data Tier"
        DB[("PostgreSQL\nSupabase / Docker\nport 5433")]
    end

    Flutter -- "TCP :8888\nAreyoughost Binary Protocol" --> TCP
    Flutter -- "HTTP :3000\nPOST /auth/login|register" --> HTTP
    APP -- "sqlx async queries" --> DB
    HTTP -- "sqlx async queries" --> DB
```

**Zero-Trust Isolation**: The Flutter client never opens a database connection. It serializes user actions into binary frames and sends them to port 8888. The Rust server is the sole authority over all state mutations and database access.

**Dual-Port Design**:
- TCP 8888 — Areyoughost binary protocol (game traffic)
- HTTP 3000 — Health check, admin endpoints, and REST auth (login/register)

### 1.1 Server-Side Concurrency Model

```mermaid
graph LR
    subgraph "Per-Connection (spawned on accept)"
        RT["Read Task\nOwnedReadHalf\n→ parse frames\n→ send to Dispatcher"]
        WT["Write Task\nOwnedWriteHalf\n← recv from mpsc channel"]
    end

    subgraph "Shared State"
        APP2["Arc&lt;RwLock&lt;AppState&gt;&gt;"]
        REG2["DashMap Connection Registry"]
    end

    subgraph "Per-Room (spawned on StartGame)"
        RR2["Room Runner\ntokio::select!\nphase timer | action channel"]
    end

    RT -- "Message" --> DISP2["Dispatcher"]
    DISP2 -- "write AppState" --> APP2
    DISP2 -- "send Bytes" --> REG2
    REG2 -- "UnboundedSender" --> WT
    RR2 -- "broadcast via Registry" --> REG2
    RR2 -- "read/write" --> APP2
```

Each accepted TCP connection spawns exactly two Tokio tasks (Read + Write). The Write task owns the `OwnedWriteHalf` and drains an `mpsc::UnboundedReceiver<Bytes>`. The Read task owns the `OwnedReadHalf`, parses complete Areyoughost frames, and forwards `Message` structs to the Dispatcher. When either task terminates, it cancels the sibling and removes the player from the Connection Registry.

Each active game room has one Room Runner task that drives the phase machine via `tokio::select!` over a phase timeout and an inbound action channel.

### 1.2 Flutter Client Architecture

```mermaid
graph LR
    NS2["NetworkService\n(singleton)"]
    BG["Background listener loop\n(async isolate)"]
    SC2["StreamController\n&lt;GameEvent&gt;"]
    GS2["GameScreen\nStreamBuilder"]

    NS2 --> BG
    BG -- "parsed GameEvent" --> SC2
    SC2 -- "Stream&lt;GameEvent&gt;" --> GS2
```

`NetworkService` exposes a `Stream<GameEvent>` that `GameScreen` subscribes to via `StreamBuilder`. The background loop continuously reads and parses Areyoughost frames from the socket, deserializes payloads with Bincode, and pushes typed events into the `StreamController`.

### 1.3 Room Management Modes

The system supports two distinct room modes with separate server routing logic:

#### Mode 1: Quick Play (Public Matchmaking)

```mermaid
flowchart TD
    A[Player taps Quick Play] --> B[Send 0x17 QuickJoinRequest]
    B --> C{Server: find public room\nstatus=WAITING AND players < 16}
    C -- Found --> D[Add player to existing room]
    C -- Not found --> E[Create new public room\nStart 120s lobby timer]
    D --> F[Broadcast RoomStateSync 0x20]
    E --> F
    F --> G{Room full 16 players\nOR 120s timer expires}
    G -- Full --> H[Auto-start game immediately]
    G -- Timer expired --> I{players >= 4?}
    I -- Yes --> H
    I -- No --> J[Disband room, notify players 0xFF]
    H --> K[Assign roles, spawn Room Runner\nBroadcast ROLE_REVEAL then NIGHT]
```

- No host required — game starts automatically.
- Background: use `DayTimeBg` image during the 120s lobby wait.
- Multiple public rooms can run concurrently (one per 16-player group).
- Server tracks `lobby_start_time` in `RoomState` for the 120s countdown.

#### Mode 2: Custom Room (Play with Friends)

```mermaid
flowchart TD
    A[Host creates room\n0x12 CreateRoomRequest] --> B[Server creates private room\nHost = creator]
    B --> C[Host searches friend by username]
    C --> D[Host sends 0x1A InvitePlayer\nwith target username]
    D --> E[Server finds online player\nSends 0x1B GameInviteReceived to friend]
    E --> F[Friend sees invite in Mail Noti\nnew invite overwrites old one]
    F --> G{Friend accepts?}
    G -- Yes --> H[Friend sends 0x14 JoinRoomRequest]
    G -- No --> I[Friend sends 0x16 LeaveRoomRequest\nor ignores]
    H --> J[Broadcast RoomStateSync 0x20 to room]
    J --> K{Host presses Start Game\n0x11 StartGame}
    K --> L{players >= 4?}
    L -- Yes --> M[Assign roles, spawn Room Runner\nBroadcast ROLE_REVEAL then NIGHT]
    L -- No --> N[Server responds 0xFF: need >= 4 players]
```

- Only the Host can start the game (no auto-start timer).
- Invites are push-delivered via `0x1B GameInviteReceived` to the friend's active socket.
- A new invite from any host overwrites the previous pending invite in the Mail Noti UI.
- Room is private (`is_public = false`).

---

## Network Protocol Specification

### 2. Areyoughost Binary Protocol

The protocol operates over raw TCP (port 8888) and uses a fixed-header binary frame to solve the TCP sticky-packet problem via an explicit 4-byte length prefix.

#### 2.1 Frame Structure

```
 0       1       2       3       4       5       6       7
 +-------+-------+-------+-------+-------+-------+-------+
 | 0xAE  | 0x80  | Type  |      Payload Length (4B BE)    |
 +-------+-------+-------+-------+-------+-------+-------+
 |                  Payload (N bytes)                     |
 |                      ...                               |
 +-------+-------+-------+-------+-------+-------+-------+
 |    CRC16-IBM-SDLC (2B BE)     |
 +-------+-------+-------+-------+
```

| Field          | Size    | Description |
|----------------|---------|-------------|
| Magic          | 2 bytes | `0xAE 0x80` — identifies valid Areyoughost frames |
| Type           | 1 byte  | Opcode identifying the message type |
| Payload Length | 4 bytes | Big-Endian u32 — exact byte count of the payload |
| Payload        | N bytes | Bincode-serialized struct (JSON for legacy) |
| CRC16          | 2 bytes | Big-Endian u16 — CRC_16_IBM_SDLC over `[Type][Length(4B)][Payload]` |

**Minimum frame size**: 9 bytes (empty payload).  
**Maximum payload**: 10 MB (`MAX_MESSAGE_SIZE = 10_485_760`).  
**Sticky-packet resolution**: The receiver buffers bytes until `accumulated >= 9 + payload_length`, then slices exactly one frame.

#### 2.2 CRC16 Computation

```
crc_input = [type_byte] ++ length_bytes_be(4) ++ payload_bytes
checksum  = CRC_16_IBM_SDLC(crc_input)
```

The magic bytes are excluded from the CRC scope. The algorithm used is `CRC_16_IBM_SDLC` from the Rust `crc` crate (polynomial 0x1021, reflected).

#### 2.3 Full Opcode Table

| Opcode | Name               | Direction | Description |
|--------|--------------------|-----------|-------------|
| 0x01   | LoginRequest       | C→S       | Authenticate with username + password |
| 0x02   | LoginResponse      | S→C       | Returns `session_id`, `player_id`, or error |
| 0x03   | RegisterRequest    | C→S       | Create new account with username + password |
| 0x04   | RegisterResponse   | S→C       | Returns success or username-taken error |
| 0x05   | ReconnectRequest   | C→S       | Reconnect using stored session_id after socket drop |
| 0x06   | ReconnectResponse  | S→C       | Returns restored game state or error if session expired |
| 0x0F   | GetGameData        | C→S       | Request all 16 roles and skill definitions |
| 0x10   | RoomListRequest    | C→S       | Request list of open rooms |
| 0x11   | RoomListResponse / StartGame | C→S (StartGame) / S→C (RoomList) | Repurposed: host sends 0x11 to start game |
| 0x12   | CreateRoomRequest  | C→S       | Create a new lobby room |
| 0x13   | CreateRoomResponse | S→C       | Returns `room_id` or error |
| 0x14   | JoinRoomRequest    | C→S       | Join an existing lobby by `room_id` |
| 0x15   | JoinRoomResponse   | S→C       | Unicast: player's assigned role at game start |
| 0x16   | LeaveRoomRequest   | C→S       | Leave lobby or active game |
| 0x17   | QuickJoinRequest   | C→S       | Request to join or create a public matchmaking room |
| 0x18   | QuickJoinResponse  | S→C       | Returns room_id and remaining lobby wait time in seconds |
| 0x1A   | InvitePlayer       | C→S       | Host invites a friend by username to the private room |
| 0x1B   | GameInviteReceived | S→C       | Push notification to invited player's Mail Noti |
| 0x20   | RoomStateSync      | S→C (broadcast) | Full participant list with usernames and online status |
| 0x30   | ChatMessage        | C→S / S→C (broadcast) | In-game chat; day = all alive, night = ghost-only |
| 0x31   | CastVote           | C→S       | Submit vote during Vote phase |
| 0x32   | NightAction        | C→S       | Submit night skill action |
| 0x33   | GamePhaseChange    | S→C (broadcast) | Phase transition with phase type, day number, duration |
| 0x34   | GameEvent          | S→C (broadcast) | Deaths, role reveals, win announcements |
| 0x50   | Heartbeat          | C→S / S→C | Keep-alive; server echoes within 5 s |
| 0x51   | LatencyPing        | C→S       | Round-trip latency measurement |
| 0x60   | PositionSync       | C→S       | Reserved for future use |
| 0x70   | Disconnect         | C→S       | Graceful disconnect notification |
| 0xFF   | Error              | S→C       | Error response with descriptive payload |
| 0x00   | Unknown            | —         | Fallback for unrecognized opcodes |

#### 2.4 Key Payload Structures (Bincode)

```rust
// 0x01 LoginRequest
struct LoginRequest { username: String, password: String }

// 0x02 LoginResponse
struct LoginResponse { success: bool, session_id: Option<String>, player_id: Option<String>, error: Option<String> }

// 0x05 ReconnectRequest
struct ReconnectRequest { session_id: String }

// 0x06 ReconnectResponse
struct ReconnectResponse {
    success: bool,
    room_id: Option<String>,
    phase: Option<PhaseType>,
    day_number: Option<u32>,
    phase_remaining_secs: Option<u32>,
    is_alive: Option<bool>,
    role: Option<RoleInfo>,
    error: Option<String>,
}

// 0x17 QuickJoinRequest
struct QuickJoinRequest { player_id: String }

// 0x18 QuickJoinResponse
struct QuickJoinResponse { room_id: String, current_players: u32, lobby_remaining_secs: u32 }

// 0x1A InvitePlayer
struct InvitePlayerRequest { target_username: String, room_id: String }

// 0x1B GameInviteReceived
struct GameInviteReceived { from_username: String, room_id: String, room_name: String }

// 0x20 RoomStateSync
struct RoomStateSync { room_id: String, participants: Vec<ParticipantInfo>, alive_count: u32 }
struct ParticipantInfo { player_id: String, username: String, is_online: bool, seat_number: i32 }

// 0x33 GamePhaseChange
struct GamePhaseChange {
    phase: PhaseType,
    day_number: u32,
    duration_secs: u32,
    server_timestamp: u64,           // Unix epoch seconds when server started this phase
    night_chat_history: Option<Vec<ChatEntry>>,
}

// 0x34 GameEvent
struct GameEvent { event_type: GameEventType, deaths: Vec<DeathInfo>, winner_faction: Option<String>, extra: Option<serde_json::Value> }
enum GameEventType { NightResolution, VoteResult, GameOver, AvengerVengeance, NemesisWin, FoolWin }
struct DeathInfo { player_id: String, username: String, role_name: String }
```


---

## Game State Machine

### 3. Game Loop and Phase Transitions

#### 3.1 Full Game State Diagram

```mermaid
stateDiagram-v2
    [*] --> LOBBY : Room created (0x12 or 0x17)

    LOBBY --> ROLE_REVEAL : StartGame triggered\n(Host 0x11 OR QuickPlay auto-start)
    note right of LOBBY
        Quick Play: auto-start when
        16 players OR 120s timer expires
        Custom Room: Host presses Start
    end note

    ROLE_REVEAL --> NIGHT_1 : Roles unicast (0x15) complete\nBroadcast GamePhaseChange NIGHT (0x33)\n20s countdown begins

    NIGHT_1 --> DAY_1 : 20s timeout\nResolve night actions → GameEvent (0x34)\nCheck win condition\nBroadcast GamePhaseChange DAY (0x33)

    DAY_1 --> VOTE_1 : 60s timeout\nBroadcast GamePhaseChange VOTE (0x33)

    VOTE_1 --> NIGHT_2 : 15s timeout\nResolve votes → GameEvent (0x34)\nCheck win condition\nBroadcast GamePhaseChange NIGHT (0x33)

    NIGHT_2 --> DAY_2 : 20s timeout\nResolve night actions → GameEvent (0x34)\nCheck win condition

    DAY_2 --> VOTE_2 : 60s timeout
    VOTE_2 --> NIGHT_3 : 15s timeout

    VOTE_1 --> GAME_OVER : Win condition met after vote
    NIGHT_1 --> GAME_OVER : Win condition met after night
    NIGHT_2 --> GAME_OVER : Win condition met after night
    GAME_OVER --> [*] : Broadcast GameEvent winner (0x34)\nRoom Runner terminates
```

#### 3.2 Phase Durations and Transitions

| Phase | Duration | Trigger to Advance | Action on Advance |
|-------|----------|--------------------|-------------------|
| LOBBY (Quick Play) | Up to 120s | 16 players joined OR 120s timer | Auto-assign roles, spawn Room Runner |
| LOBBY (Custom) | Unlimited | Host sends 0x11 StartGame | Assign roles, spawn Room Runner |
| ROLE_REVEAL | ~2s | Automatic after all unicasts sent | Broadcast **NIGHT** phase start (0x33) |
| **NIGHT** | **20s** | **Timeout or all night actions received** | **Resolve actions → GameEvent (0x34), advance to DAY** |
| DAY | 60s | Timeout | Advance to VOTE, broadcast 0x33 |
| VOTE | 15s | Timeout or majority vote | Resolve votes → GameEvent (0x34), advance to NIGHT |
| GAME_OVER | — | Win condition detected | Broadcast 0x34 winner, terminate Room Runner |

**Phase order in PhaseMachine**: `Night → Day → Vote → Night → Day → Vote → ...`  
`day_number` increments after each `Night → Day` transition.

#### 3.3 Night Action Priority

```mermaid
flowchart TD
    A[Night phase ends] --> B[Collect all NightAction 0x32 messages]
    B --> C{Priority 1: PROTECT}
    C --> D[Doctor marks protected_targets]
    D --> E{Priority 2: INFORMATION}
    E --> F[Seer: inspect faction\nPolice: inspect aura\nMedium: view dead role\nMonk: block inspection]
    F --> G{Priority 3: KILL}
    G --> H{Target in protected_targets?}
    H -- Yes --> I[Log: protected, no death]
    H -- No --> J[Mark is_alive = false]
    J --> K[Broadcast GameEvent deaths 0x34]
    I --> K
    K --> L[Win_Checker.check_win]
    L -- Win found --> M[Broadcast GameEvent winner 0x34\nTerminate Room Runner]
    L -- No win --> N[Advance to DAY, day_number++\nNote: Night 1 announces 'The night begins...'\nno deaths from previous night]
```

#### 3.4 Special Role Triggers

| Role | Trigger | Effect |
|------|---------|--------|
| AvengerGhost | Voted out during Vote phase | Drags one random alive player to death |
| Nemesis | Hidden target voted out | Nemesis wins immediately (DayVote trigger) |
| Fool | Voted out during Vote phase | Fool wins immediately |
| Soldier | Targeted by Kill at night | Self-protect activates once (max 1 use) |
| DarkShaman | Night action | Target player is silenced for next Day phase |
| DeceiverGhost | Passive | Seer inspection returns VILLAGER instead of GHOST |
| QueenGhost | Passive | Aura inspection returns GOOD instead of EVIL |

#### 3.5 Win Condition Check Points

Win conditions are evaluated by `WinChecker::check_win()` after every phase resolution:

```mermaid
flowchart LR
    A[After Night Resolve] --> W[Win_Checker]
    B[After Vote Resolve] --> W
    W --> V{ghosts==0 AND sk==0?}
    V -- Yes --> VW[Villager Win]
    W --> G{ghost_count >= all others?}
    G -- Yes --> GW[Ghost Win]
    W --> S{sk>0 AND total_alive<=2 AND ghosts==0?}
    S -- Yes --> SW[Serial Killer Win]
    W --> D{SK==1 AND Ghost==1 AND total==2?}
    D -- Yes --> DW[Draw]
    W --> N{DayVote trigger AND nemesis.hidden_target == voted_out?}
    N -- Yes --> NW[Nemesis Win]
```


#### 3.6 Timer Synchronization and UI State

The server is the authoritative timer. The `GamePhaseChange (0x33)` payload includes `duration_secs` (e.g., 60 for Day) and `server_timestamp` (Unix epoch u64). The Flutter client starts a local countdown from `duration_secs` when it receives the packet. The client can compute clock drift by comparing `server_timestamp` against its local clock.

**UI State Machine for Timer**:
```
COUNTING_DOWN  →  (local timer hits 0)  →  WAITING_FOR_SERVER
WAITING_FOR_SERVER  →  (0x33 received)  →  COUNTING_DOWN
```

- When the local countdown reaches 0 but no new `0x33` has arrived, the Flutter `GameScreen` SHALL display a "Waiting for server..." overlay instead of advancing the UI phase.
- The UI MUST NOT change the displayed phase until a `0x33 GamePhaseChange` is received from the server.
- This prevents UI/server desync caused by network jitter or processing delay.

---

## Database Schema

### 4. ER Diagram

```mermaid
erDiagram
    players {
        uuid player_id PK
        text username UK "UNIQUE, length 3-20"
        text password_hash "bcrypt, cost >= 10"
        text online_status "online | offline"
        timestamptz created_at
        timestamptz updated_at
        timestamptz last_login
    }

    rooms {
        uuid room_id PK
        uuid owner_id FK
        text room_name
        int max_players "1-16"
        boolean is_public
        text room_status "WAITING | PLAYING | CLOSED"
        timestamptz created_at
        timestamptz updated_at
    }

    room_members {
        uuid room_member_id PK
        uuid room_id FK
        uuid player_id FK
        text member_status "JOINED | LEFT"
        timestamptz joined_at
    }

    roles {
        int role_id PK
        text role_code UK
        text role_name UK
        text faction "VILLAGER | GHOST | SPECIAL"
        text description
        text seer_result "VILLAGER | GHOST"
        text aura_result "GOOD | EVIL"
        int min_players
        int max_players
        boolean is_unique
        boolean is_enabled
        int role_priority
    }

    skills {
        int skill_id PK
        text skill_code UK
        text skill_name
        text skill_type "KILL | PROTECT | CHECK | PASSIVE | SPECIAL"
        text phase "DAY | NIGHT | ANY"
        int max_uses "NULL = unlimited"
        text description
    }

    role_skills {
        int id PK
        int role_id FK
        int skill_id FK
    }

    games {
        uuid game_id PK
        uuid room_id FK
        text game_status "WAITING | ONGOING | FINISHED"
        bigint random_seed
        timestamptz started_at
        timestamptz ended_at
        text winner_faction
    }

    game_participants {
        uuid id PK
        uuid game_id FK
        uuid player_id FK
        int role_id FK
        boolean is_alive
        int seat_number
        timestamptz joined_at
        timestamptz died_at
    }

    game_phases {
        uuid phase_id PK
        uuid game_id FK
        text phase_type "DAY | NIGHT"
        int phase_order
        timestamptz started_at
        timestamptz ended_at
    }

    game_actions {
        uuid action_id PK
        uuid game_id FK
        uuid phase_id FK
        uuid actor_id FK
        uuid target_id FK
        text action_type
        jsonb payload
        timestamptz created_at
    }

    votes {
        uuid vote_id PK
        uuid game_id FK
        uuid phase_id FK
        uuid voter_id FK
        uuid candidate_id FK
        timestamptz created_at
    }

    chat_messages {
        uuid message_id PK
        uuid game_id FK
        uuid sender_id FK
        text chat_scope "PUBLIC | GHOST"
        text message_text
        int day_number
        timestamptz created_at
    }

    players ||--o{ rooms : "owns"
    players ||--o{ room_members : "joins"
    rooms ||--o{ room_members : "has"
    rooms ||--o{ games : "hosts"
    games ||--o{ game_participants : "includes"
    games ||--o{ game_phases : "has"
    games ||--o{ game_actions : "records"
    games ||--o{ votes : "records"
    games ||--o{ chat_messages : "stores"
    players ||--o{ game_participants : "plays as"
    roles ||--o{ game_participants : "assigned to"
    roles ||--o{ role_skills : "has"
    skills ||--o{ role_skills : "used by"
    players ||--o{ game_actions : "performs"
    players ||--o{ votes : "casts"
    players ||--o{ chat_messages : "sends"
    game_phases ||--o{ game_actions : "contains"
    game_phases ||--o{ votes : "contains"
```

### 4.1 Key Constraints

- `players.username`: UNIQUE, length CHECK (3–20 chars)
- `roles.faction`: CHECK IN ('VILLAGER', 'GHOST', 'SPECIAL')
- `roles.aura_result`: CHECK IN ('GOOD', 'EVIL')
- `roles.seer_result`: CHECK IN ('VILLAGER', 'GHOST')
- `rooms.room_status`: CHECK IN ('WAITING', 'PLAYING', 'CLOSED')
- `games.game_status`: CHECK IN ('WAITING', 'ONGOING', 'FINISHED')
- `chat_messages.chat_scope`: CHECK IN ('PUBLIC', 'GHOST')
- `game_participants(game_id, player_id)`: UNIQUE — one participant record per player per game
- `role_skills(role_id, skill_id)`: UNIQUE — no duplicate mappings

### 4.2 Seed Data (16 Roles + Skills)

The migration inserts all 16 roles using `ON CONFLICT DO NOTHING` for idempotency:

**Villager Faction (9)**: VILLAGER, SEER, DOCTOR, SOLDIER, POLICE, MONK, MEDIUM, UNDERTAKER, FOOL  
**Ghost Faction (5)**: GHOST, QUEENGHOST, AVENGERGHOST, DECEIVERGHOST, DARKSHAMAN  
**Special Faction (2)**: SERIALKILLER, NEMESIS

**Skills (11)**: KILL, PROTECT, INSPECT_FACTION, INSPECT_AURA, BLOCK_CHECK, VIEW_DEAD_ROLE, SILENCE, SELF_PROTECT (max 1), DRAG_TO_DEATH (max 1), FOOL_VICTORY (passive), HIDDEN_TARGET_WIN (passive)


---

## Module Design

### 5. Components and Interfaces

#### 5.1 New Files

**`core/src/network/dispatcher.rs`**
```rust
pub struct Dispatcher {
    app_state: Arc<RwLock<AppState>>,
    registry: Arc<DashMap<String, UnboundedSender<Bytes>>>,
}

impl Dispatcher {
    pub async fn handle(&self, player_id: &str, msg: Message) -> Result<()>;
    async fn handle_join_room(&self, player_id: &str, payload: JoinRoomRequest) -> Result<()>;
    async fn handle_start_game(&self, player_id: &str, payload: StartGameRequest) -> Result<()>;
    async fn handle_cast_vote(&self, player_id: &str, payload: CastVoteRequest) -> Result<()>;
    async fn handle_night_action(&self, player_id: &str, payload: NightActionRequest) -> Result<()>;
    async fn handle_chat(&self, player_id: &str, payload: ChatPayload) -> Result<()>;
    async fn handle_login(&self, player_id: &str, payload: LoginRequest) -> Result<()>;
    async fn handle_register(&self, player_id: &str, payload: RegisterRequest) -> Result<()>;
    async fn handle_reconnect(&self, temp_player_id: &str, payload: ReconnectRequest) -> Result<()>;
    async fn handle_quick_join(&self, player_id: &str, payload: QuickJoinRequest) -> Result<()>;
    async fn handle_invite_player(&self, player_id: &str, payload: InvitePlayerRequest) -> Result<()>;
    async fn broadcast_to_room(&self, room_id: &str, msg: Message) -> Result<()>;
    async fn unicast(&self, player_id: &str, msg: Message) -> Result<()>;
}
```

**`core/src/game_logic/room_task.rs`**
```rust
pub struct RoomRunner {
    room_id: String,
    app_state: Arc<RwLock<AppState>>,
    registry: Arc<DashMap<String, UnboundedSender<Bytes>>>,
    action_rx: mpsc::UnboundedReceiver<RoomAction>,
}

impl RoomRunner {
    pub async fn run(mut self);
    async fn run_day_phase(&mut self) -> PhaseResult;
    async fn run_vote_phase(&mut self) -> PhaseResult;
    async fn run_night_phase(&mut self) -> PhaseResult;
    async fn broadcast_phase_change(&self, phase: PhaseType, day_number: u32, duration: u32);
    async fn check_and_announce_winner(&self) -> bool;
}

pub enum RoomAction {
    Vote { voter_id: String, target_id: String },
    NightAction { actor_id: String, action_type: String, target_id: Option<String> },
    PlayerLeft { player_id: String },
}
```

#### 5.2 Modified Files

**`core/src/network/tcp_server.rs`** — Stream splitting + DashMap registry
```rust
pub struct TcpServer {
    listener: TcpListener,
    app_state: Arc<RwLock<AppState>>,
    registry: Arc<DashMap<String, UnboundedSender<Bytes>>>,
}

impl TcpServer {
    pub async fn bind(addr: &str, app_state: Arc<RwLock<AppState>>) -> Result<Self>;
    pub async fn run(&self);  // accept loop
    async fn handle_connection(stream: TcpStream, app_state: Arc<RwLock<AppState>>, registry: Arc<DashMap<String, UnboundedSender<Bytes>>>);
    // Spawns Read Task + Write Task via into_split()
}
```

**`core/src/game_logic/state.rs`** — AppState upgrade
```rust
pub struct AppState {
    pub rooms: HashMap<String, RoomState>,
    pub sessions: HashMap<String, SessionInfo>,  // session_id -> player_id + last_seen
    pub db_pool: sqlx::PgPool,
}

pub enum RoomMode { QuickPlay, Custom }

pub struct RoomState {
    pub room: Room,
    pub game_state: Option<GameState>,
    pub host_id: String,
    pub action_tx: Option<mpsc::UnboundedSender<RoomAction>>,
    pub room_mode: RoomMode,                     // Quick Play or Custom
    pub lobby_start_time: Option<Instant>,       // for Quick Play 120s timer
}
```

**`core/src/game_logic/chat_system.rs`** — Phase-aware chat
```rust
impl ChatSystem {
    pub fn add_message(&mut self, msg: ChatMessage, phase: &PhaseType, sender_faction: &Faction) -> Result<(), ChatError>;
    pub fn get_day_history(&self, day_number: u32) -> Vec<&ChatMessage>;
    pub fn get_night_history(&self, day_number: u32) -> Vec<&ChatMessage>;  // ghost-only
    pub fn get_night_history_for_villagers(&self, day_number: u32) -> Vec<&ChatMessage>;
}

pub enum ChatError {
    DeadPlayerCannotChat,
    NightChatRestrictedToGhosts,
}
```

**`core/src/game_logic/phase_machine.rs`** — Phase order corrected to start at Night
```rust
impl PhaseMachine {
    pub fn new() -> Self {
        Self {
            current_phase: PhaseType::Night,  // starts at Night after ROLE_REVEAL
            day_number: 1,
            phase_end_time: Self::now() + 20,  // 20s for first Night
        }
    }

    pub fn next_phase(&mut self) {
        match self.current_phase {
            PhaseType::Night => {
                self.current_phase = PhaseType::Day;
                self.day_number += 1;  // day increments Night→Day
                self.phase_end_time = Self::now() + 60;
            },
            PhaseType::Day => {
                self.current_phase = PhaseType::Vote;
                self.phase_end_time = Self::now() + 15;
            },
            PhaseType::Vote => {
                self.current_phase = PhaseType::Night;
                self.phase_end_time = Self::now() + 20;
            },
        }
    }
}
```
```dart
class NetworkService {
  static final NetworkService _instance = NetworkService._internal();
  factory NetworkService() => _instance;

  Socket? _socket;
  final StreamController<GameEvent> _eventController = StreamController.broadcast();
  Stream<GameEvent> get events => _eventController.stream;
  bool isConnected = false;

  Future<void> connect(String host, int port);
  Future<void> sendMessage(Message msg);
  void _startListenerLoop();  // background async loop
  void _parseFrame(Uint8List buffer);
  void disconnect();
}
```


---

## Correctness Properties

*A property is a characteristic or behavior that should hold true across all valid executions of a system — essentially, a formal statement about what the system should do. Properties serve as the bridge between human-readable specifications and machine-verifiable correctness guarantees.*

### Property 1: Protocol Round-Trip

*For any* valid `MessageType` and arbitrary payload bytes, serializing a `Message` with `Message::to_bytes()` and then deserializing with `Message::from_bytes()` shall produce a `Message` with the same `msg_type` and identical `payload` bytes.

**Validates: Requirements 8.1**

### Property 2: CRC Corruption Rejection

*For any* valid serialized frame, flipping any single bit in the payload region shall cause `Message::from_bytes()` to return `Err` with a CRC mismatch error.

**Validates: Requirements 8.2**

### Property 3: Magic Byte Rejection

*For any* byte sequence where the first two bytes are not `[0xAE, 0x80]`, `Message::from_bytes()` shall return `Err` indicating invalid magic bytes.

**Validates: Requirements 8.3**

### Property 4: Role Distribution Count

*For any* player count N ≥ 1, `RoleDistributor::assign_roles(N, seed)` shall return a `Vec<Role>` of length exactly N.

**Validates: Requirements 9.1, 14.1**

### Property 5: Vote Resolution Correctness

*For any* non-empty map of votes (voter_id → target_id), `VoteSystem::resolve_vote()` shall return `Some(player_id)` where `player_id` has strictly more votes than all other candidates, or `None` if two or more candidates are tied for the maximum vote count.

**Validates: Requirements 17.4, 17.5**

### Property 6: Win Condition Correctness

*For any* participant map where `living_ghosts == 0` and `living_sk == 0`, `WinChecker::check_win()` shall return `Some(Faction::Villager)`. *For any* participant map where `living_ghosts >= living_villagers + living_sk + living_nemesis` (and ghosts > 0), it shall return `Some(Faction::Ghost)`.

**Validates: Requirements 19.1, 19.2, 19.3**

### Property 7: Phase Machine Cycle

*For any* starting `PhaseType`, calling `PhaseMachine::next_phase()` three times shall return the machine to the original phase, and `day_number` shall increment by exactly 1 after each complete Day→Vote→Night cycle.

**Validates: Requirements 21.5, 5.2, 5.3**

### Property 8: Night Resolver Protection Invariant

*For any* set of night actions containing at least one PROTECT action targeting player P and at least one KILL action targeting player P, `NightResolver::resolve()` shall not set `is_alive = false` for player P.

**Validates: Requirements 15.4**

### Property 9: Broadcast Completeness

*For any* room with N registered participants in the Connection Registry, calling `broadcast_to_room(room_id, message)` shall attempt to send the serialized message to exactly N channels, and the resulting `Bytes` sent to each channel shall equal `message.to_bytes()`.

**Validates: Requirements 3.1**

### Property 10: Disconnect Cleans Registry

*For any* player registered in the Connection Registry, after the player's TCP connection drops (read/write error detected), the Connection Registry shall contain no entry keyed by that player's `PlayerId`.

**Validates: Requirements 1.2, 1.4**

---

## Error Handling

### 6. Error Handling Strategy

| Error Condition | Handler | Response |
|-----------------|---------|----------|
| Invalid magic bytes | Read Task | Drop connection, log warning |
| CRC mismatch | Read Task | Drop connection, log warning |
| Payload > 10 MB | Read Task | Drop connection, log warning |
| Unknown opcode | Dispatcher | Send Error (0xFF) with description |
| Unauthenticated action | Dispatcher | Send Error (0xFF) "not authenticated" |
| Dead player action | Dispatcher | Send Error (0xFF) "player is dead" |
| Non-host StartGame | Dispatcher | Send Error (0xFF) "not room host" |
| Room already playing | Dispatcher | Send Error (0xFF) "game in progress" |
| Insufficient players | Dispatcher | Send Error (0xFF) "need >= 4 players" |
| Channel send failure | Broadcast | Skip player, remove from registry, log |
| Room Runner panic | Tokio task | Broadcast Error (0xFF) to room, clean up |
| DB query failure | sqlx | Log error, return Error (0xFF) to client |
| Reconnect within 30s | Dispatcher | Restore session state, re-register in registry |
| ReconnectRequest with expired session | Dispatcher | Send Error (0xFF) "session expired, please login" |
| QuickJoin room disbanded (< 4 players after 120s) | Room Runner | Send Error (0xFF) "not enough players, room closed" |
| InvitePlayer target not online | Dispatcher | Send Error (0xFF) "player not online" |
| InvitePlayer target already in a game | Dispatcher | Send Error (0xFF) "player already in game" |

All errors are logged with structured fields: `room_id`, `player_id`, `opcode`, `timestamp` using the `tracing` crate.

---

## Testing Strategy

### 7. Dual Testing Approach

Both unit tests and property-based tests are required. They are complementary: unit tests catch concrete bugs in specific scenarios; property tests verify universal correctness across all inputs.

#### 7.1 Property-Based Testing

Library: **`proptest`** (Rust) for server-side properties; **`fast_check`** (Dart) for Flutter-side properties.

Each property test runs a minimum of **100 iterations** with randomized inputs. Each test is tagged with a comment referencing the design property it validates.

```rust
// Feature: build-stabilization-service-recovery, Property 1: Protocol Round-Trip
#[test]
fn prop_protocol_round_trip() {
    proptest!(|(type_byte in 0u8..=0xFFu8, payload in any::<Vec<u8>>())| {
        // ...
    });
}
```

| Property | Test Name | Library | Iterations |
|----------|-----------|---------|------------|
| P1: Protocol round-trip | `prop_protocol_round_trip` | proptest | 100 |
| P2: CRC corruption rejection | `prop_crc_corruption_rejected` | proptest | 100 |
| P3: Magic byte rejection | `prop_magic_rejection` | proptest | 100 |
| P4: Role distribution count | `prop_role_count_equals_players` | proptest | 100 |
| P5: Vote resolution correctness | `prop_vote_resolution` | proptest | 100 |
| P6: Win condition correctness | `prop_win_condition` | proptest | 100 |
| P7: Phase machine cycle | `prop_phase_cycle` | proptest | 100 |
| P8: Night resolver protection | `prop_protection_invariant` | proptest | 100 |
| P9: Broadcast completeness | `prop_broadcast_completeness` | proptest | 100 |
| P10: Disconnect cleans registry | `prop_disconnect_cleanup` | proptest | 100 |

#### 7.2 Unit Tests

Unit tests focus on specific examples, integration points, and edge cases that property tests do not cover:

- `test_login_success` / `test_login_wrong_password` — LoginRequest/Response round-trip
- `test_register_duplicate_username` — username uniqueness enforcement
- `test_start_game_insufficient_players` — Error (0xFF) on < 4 players
- `test_avenger_ghost_drags_victim` — AvengerGhost special trigger
- `test_nemesis_wins_on_target_vote` — Nemesis win condition
- `test_fool_wins_on_vote_out` — Fool win condition
- `test_night_chat_restricted_to_ghosts` — ChatSystem phase-aware filtering
- `test_db_seed_has_16_roles` — database seed idempotency
- `test_phase_machine_day_number_increments` — day counter after Night→Day
- `test_vote_tie_returns_none` — tie-breaking edge case

#### 7.3 Integration Tests

End-to-end tests using two in-process TCP connections:
- Full login → create room → join room → start game → Day → Vote → Night cycle
- Reconnection within 30 s restores game state
- Broadcast reaches all N participants in a room

