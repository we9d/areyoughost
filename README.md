# Are You Ghost? 👻🎮

[![License](https://img.shields.io/badge/license-MIT%2FApache--2.0-blue.svg)](LICENSE)
[![Rust](https://img.shields.io/badge/rust-2021-orange.svg)](https://www.rust-lang.org)
[![Flutter](https://img.shields.io/badge/flutter-latest-blue.svg)](https://flutter.dev)

A desktop-first multiplayer social deduction game where players must identify the "ghost" among them through discussion and voting. Built with **Flutter** for the frontend and **Rust** for the backend engine.

## 🎮 About the Game

**Are You Ghost?** is a social deduction game inspired by Mafia and Werewolf. Players engage in rounds of discussion and voting to identify hidden ghost players before it's too late.

**Features:**
- 🏠 **Multiplayer Lobbies** - Support for up to 16 players per room
- 💬 **Real-Time Chat** - In-game discussion during day phases
- 🗳️ **Voting Mechanics** - Democratic elimination system
- 🖥️ **Desktop-Optimized** - Native Windows application (Mac/Linux planned)
- 🌐 **Network Play** - Connect via Cloudflare Tunnel for easy multiplayer

## 📋 Table of Contents

- [About the Game](#-about-the-game)
- [Architecture](#-architecture)
- [Quick Start](#-quick-start)
- [Installation](#-installation)
- [Development](#-development)
- [Project Structure](#-project-structure)
- [Project Components](#-project-components)
  - [1. Frontend](#1-frontend---flutter-desktop-application)
  - [2. Backend Server](#2-backend-server---rust-axum-httpwebsocket-server)
  - [3. Core Library](#3-core-library---rust-game-logic--networking)
  - [4. Database](#4-database---postgresql)
  - [5. Network Protocol](#5-network-protocol---custom-tcpudp-layer)
- [Development Tools & Scripts](#-development-tools--scripts)
- [Cargo Workspace](#-cargo-workspace)
- [Documentation](#-documentation)
- [Network & Communication](#-network--communication)
- [Testing & Quality Assurance](#-testing--quality-assurance)
- [Database Schema](#-database-schema-quick-reference)
- [Troubleshooting](#-troubleshooting)
- [Configuration](#-configuration--environment-variables)
- [Deployment](#-deployment--production)
- [Quick Reference](#-quick-reference-commands)
- [Development Status](#-development-status)
- [Contributing](#-contributing)
- [License](#-license)
- [Resources](#-resources)

## 🏗️ Architecture

This is a **monorepo workspace** with clear separation between frontend and backend:

### Components

```mermaid
graph LR
    A[Flutter Desktop] -->|FFI| B[Rust Core Library]
    A -->|WebSocket| C[Rust Server]
    C --> B
    C --> D[(PostgreSQL)]
```

- **Frontend:** Flutter desktop application (Windows)
- **Core:** Rust library with game logic, networking, and FFI exports
- **Server:** Standalone Axum HTTP/WebSocket server
- **Database:** PostgreSQL for persistent storage

### Technology Stack

| Layer | Technology |
|-------|------------|
| **Frontend** | Flutter (Desktop), Dart |
| **Backend** | Rust 2021, Tokio (async runtime) |
| **Server** | Axum (HTTP/WebSocket framework) |
| **Database** | Supabase PostgreSQL 16, sqlx |
| **FFI Bridge** | flutter_rust_bridge |
| **Networking** | WebSockets for Real-Time Game Sync |

**[→ Detailed Architecture Documentation](docs/ARCHITECTURE.md)**

## 🚀 Quick Start

### Prerequisites

- [Rust](https://www.rust-lang.org/tools/install) (latest stable)
- [Flutter](https://flutter.dev/docs/get-started/install) (latest stable)
- [Visual Studio](https://visualstudio.microsoft.com/vs/community/) (with C++ build tools)
- [Docker Desktop](https://www.docker.com/products/docker-desktop) (for PostgreSQL)
- [Git](https://git-scm.com/downloads)

### Run the Server

```powershell
# Start database
docker-compose up -d

# Run server
cargo run -p areyoughost_server
```

The server will start on http://localhost:3000

### Run the Flutter App

```powershell
cd frontend
flutter pub get
flutter run -d windows
```

The desktop app will launch in a centered window.

## 📦 Installation

### 1. Clone the Repository

```powershell
git clone https://github.com/we9d/areyoughost.git
cd areyoughost
```

### 2. Set Up Flutter

**Windows Installation:**
1. Extract Flutter SDK to `C:\flutter`
2. Add `C:\flutter\bin` to your PATH:
   - Search "Edit the system environment variables"
   - Click "Environment Variables"
   - Under "User variables", edit "Path"
   - Add new entry: `C:\flutter\bin`
   - Click OK on all windows
3. Verify installation:
   ```powershell
   flutter --version
   ```

### 3. Configure Visual Studio

Install Visual Studio with these workloads:
- **Desktop development with C++**

Required components:
- MSVC v143 - VS 2022 C++ x64/x86 build tools
- Windows 10 SDK or Windows 11 SDK
- C++ CMake tools for Windows

### 4. Install Rust

Download and run: [rustup-init.exe (x64)](https://www.rust-lang.org/tools/install)

Verify installation:
```powershell
rustc --version
cargo --version
```

### 5. Set Up Environment

Copy the environment template:
```powershell
Copy-Item .env.example -Destination .env
```

Edit `.env` with your local configuration (defaults work for development).

### 6. Start PostgreSQL

```powershell
docker-compose up -d
```

This starts:
- PostgreSQL on `localhost:5432`
- PgAdmin on http://localhost:8080

### 7. Build the Project

**Build Rust workspace:**
```powershell
cargo build --workspace
```

**Install Flutter dependencies:**
```powershell
cd frontend
flutter pub get
```

## 💻 Development

### Running Components

**Backend Server:**
```powershell
cargo run -p areyoughost_server
```

**Flutter Desktop App:**
```powershell
cd frontend
flutter run -d windows
```

**Database Management:**
- PgAdmin: http://localhost:8080
  - Email: `admin@areyoughost.com`
  - Password: `admin`

### Code Quality

**Format code:**
```powershell
cargo fmt --all
```

**Run linter:**
```powershell
cargo clippy --workspace --all-targets
```

**Run tests:**
```powershell
cargo test --workspace
```

**[→ Full Development Guide](docs/DEVELOPMENT.md)**

## 📁 Project Structure

```
areyoughost/
├── core/                          # Rust Core Library - Shared game logic & networking
│   ├── src/
│   │   ├── api.rs               # FFI exports to Flutter Desktop
│   │   ├── lib.rs               # Core library entry point
│   │   ├── models.rs            # Shared data structures & game models
│   │   ├── db.rs                # Database module initialization
│   │   ├── http_client.rs       # HTTP client for server communication
│   │   ├── network.rs           # Network protocol handler (TCP/UDP/WebSocket)
│   │   ├── game_logic/          # Game State Machine
│   │   │   ├── state.rs         # Main game state management
│   │   │   ├── roles.rs         # Role definitions (Ghost, Civilian, etc.)
│   │   │   ├── phase_machine.rs # Game phase transitions
│   │   │   ├── vote_system.rs   # Voting mechanics & tallying
│   │   │   ├── chat_system.rs   # In-game chat messages
│   │   │   ├── night_resolver.rs # Night phase logic & role actions
│   │   │   └── win_checker.rs   # Win condition validation
│   │   ├── network/             # Network Stack Implementation
│   │   │   ├── message.rs       # Message types & serialization
│   │   │   ├── tcp_client.rs    # TCP client implementation
│   │   │   ├── tcp_server.rs    # TCP server socket handling
│   │   │   ├── bandwidth.rs     # Bandwidth throttling & monitoring
│   │   │   └── benchmarks.rs    # Network performance testing
│   │   └── db/
│   │       └── postgres.rs      # PostgreSQL connection pooling & queries
│   ├── migrations/              # SQL migration scripts (Sqlx)
│   │   └── 20240216000000_init.sql
│   ├── examples/
│   │   └── migrate.rs           # Database migration example
│   └── Cargo.toml               # Core dependencies & FFI configuration
│
├── server/                        # Rust Backend Server - Axum HTTP/WebSocket
│   ├── src/
│   │   ├── main.rs              # Server entry point & setup
│   │   ├── auth/                # Authentication & JWT tokens
│   │   ├── routes/              # HTTP endpoint handlers
│   │   ├── ws/                  # WebSocket handlers
│   │   ├── network/             # Server-side network logic
│   │   ├── state/               # Server application state
│   │   └── bin/                 # Binary executables
│   └── Cargo.toml               # Server dependencies (Axum, Tokio, SQLx)
│
├── frontend/                      # Flutter Desktop Application - Windows
│   ├── lib/
│   │   ├── main.dart            # Application entry point
│   │   ├── ui/                  # UI Components & Screens
│   │   │   ├── login.dart
│   │   │   ├── lobby.dart
│   │   │   └── game_screen.dart
│   │   ├── services/            # Business Logic & API Layer
│   │   ├── state/               # State Management (Provider/Riverpod)
│   │   ├── models/              # Dart data models
│   │   ├── theme/               # UI theming & styling
│   │   ├── src/                 # Generated FFI bindings
│   │   └── ffi/                 # FFI bridge to Rust Core
│   ├── android/                 # Android platform support (future)
│   ├── ios/                     # iOS platform support (future)
│   ├── windows/                 # Windows platform support (CMake build)
│   ├── linux/                   # Linux platform support (future)
│   ├── macos/                   # macOS platform support (future)
│   ├── web/                     # Web platform support (future)
│   ├── assets/                  # Game assets
│   │   ├── images/              # UI images & backgrounds
│   │   ├── icons/               # Application icons
│   │   └── fonts/               # Custom fonts
│   ├── test/                    # Widget & unit tests
│   ├── pubspec.yaml             # Flutter dependencies
│   ├── analysis_options.yaml    # Dart linting rules
│   ├── devtools_options.yaml    # DevTools configuration
│   └── flutter_rust_bridge.yaml # FFI code generation config
│
├── docs/                          # Documentation & Specifications
│   ├── ARCHITECTURE.md           # System architecture & design patterns
│   ├── DEVELOPMENT.md            # Development setup & workflow
│   └── PROTOCOL.md               # Network protocol specification
│
├── protocol/                      # Protocol Documentation
│   └── protocol_spec.md          # Custom TCP/UDP protocol details
│
├── examples/                      # Example Code
│   ├── tcp_client_example.rs     # TCP client usage example
│   └── README.md                 # Example documentation
│
├── scripts/                       # Development & Deployment Tools
│   ├── setup.ps1                # Initial project setup script
│   ├── test_all.ps1             # Run all tests
│   └── test_sockets.mjs         # Network socket testing script
│
├── .env.example                  # Environment variables template
├── docker-compose.yml            # PostgreSQL + PgAdmin Docker setup
├── Cargo.toml                    # Rust workspace configuration
├── Cargo.lock                    # Dependency lock file
├── clippy.toml                   # Rust linter configuration
├── rustfmt.toml                  # Rust formatter configuration
└── README.md                     # This file
```

## 🛠️ Project Components

### 1. **Frontend** - Flutter Desktop Application

**Location:** `frontend/`

**Technology Stack:**
- **Framework:** Flutter (Desktop-optimized for Windows)
- **Language:** Dart 3.x
- **FFI Bridge:** flutter_rust_bridge (communicates with Rust Core)
- **Networking:** WebSocket (for server communication)
- **State Management:** Provider (planned implementation)
- **UI Kit:** Material Design + Custom Widgets

**Key Features:**
- Desktop-native Windows application
- Real-time multiplayer UI
- Game lobby & room management
- In-game chat interface
- Vote visualization
- Role reveal screens
- FFI integration with Rust Core library

**Dependencies:**
- `flutter_rust_bridge` - FFI code generation & bindings
- `web_socket_channel` - WebSocket client
- `shared_preferences` - Local storage
- `http` - HTTP requests
- `google_fonts` - Custom fonts
- `flutter_svg` - SVG asset support

---

### 2. **Backend Server** - Rust Axum HTTP/WebSocket Server

**Location:** `server/`

**Technology Stack:**
- **Framework:** Axum 0.7 (HTTP/WebSocket server)
- **Async Runtime:** Tokio (multi-threaded)
- **Database:** SQLx with PostgreSQL 16
- **Authentication:** JWT (jsonwebtoken) + Argon2 password hashing
- **Serialization:** Serde + JSON
- **Error Handling:** Anyhow + Thiserror

**Key Responsibilities:**
- HTTP endpoint handlers for authentication & game management
- WebSocket server for real-time game updates
- JWT-based user authentication
- Player session management
- Game lobby coordination
- Database persistence

**Endpoints:**
- `POST /auth/register` - User registration
- `POST /auth/login` - User authentication
- `WS /game/:room_id` - WebSocket game connection
- `GET /lobbies` - List available game rooms
- `POST /lobbies` - Create new game room

**Server Startup:**
```powershell
cargo run -p areyoughost_server
# Starts on http://localhost:3000
```

---

### 3. **Core Library** - Rust Game Logic & Networking

**Location:** `core/`

**Technology Stack:**
- **Language:** Rust 2021 Edition
- **Async Runtime:** Tokio
- **FFI:** flutter_rust_bridge (exports to Flutter)
- **Database:** SQLx + PostgreSQL driver
- **Serialization:** Serde + Serde_JSON
- **Networking:** tokio-tungstenite (WebSocket client)
- **HTTP Client:** Reqwest (async HTTP)

**Core Modules:**

#### **3.1 Game Logic** - `game_logic/`
- **`state.rs`** - Main game state machine, phase management
- **`roles.rs`** - Role types: Ghost, Civilian, with role-specific abilities
- **`phase_machine.rs`** - Day/Night phase transitions
- **`vote_system.rs`** - Vote tallying & elimination logic
- **`chat_system.rs`** - Message validation & history
- **`night_resolver.rs`** - Night phase actions (if roles have abilities)
- **`win_checker.rs`** - Win condition validation (Ghosts win vs. Civilians win)

#### **3.2 Network Protocol** - `network/`
- **`message.rs`** - Game message types (Join, Leave, Chat, Vote, etc.)
- **`tcp_client.rs`** - Direct TCP client for socket communication
- **`tcp_server.rs`** - TCP server for direct socket connections
- **`bandwidth.rs`** - Rate limiting & bandwidth throttling
- **`benchmarks.rs`** - Network performance benchmarking

#### **3.3 Database** - `db/`
- **`postgres.rs`** - PostgreSQL connection pooling & query builders

#### **3.4 FFI Exports** - `api.rs`
- FFI functions exported to Flutter Desktop
- Wraps game logic functions for GUI access

---

### 4. **Database** - PostgreSQL

**Location:** Docker Compose setup via `docker-compose.yml`

**Configuration:**
- **Host:** localhost
- **Port:** 5432
- **Database:** areyoughost
- **Admin UI:** PgAdmin on http://localhost:8080

**Tables:**
- `users` - Player accounts & authentication
- `lobbies/rooms` - Game room data
- `game_sessions` - Active game state
- `players` - Player assignments in games
- `chat_messages` - Game chat history
- `votes` - Vote records

**Migrations:**
- Located in `core/migrations/`
- Executed with `sqlx migrate` commands

**Access:**
```powershell
# Start PostgreSQL
docker-compose up -d

# Access PgAdmin
# URL: http://localhost:8080
# Email: admin@areyoughost.com
# Password: admin
```

---

### 5. **Network Protocol** - Custom TCP/UDP Layer

**Location:** `protocol/protocol_spec.md` & `core/network/`

**Protocol Stack (OSI Model):**
```
Layer 7: Application    - Game messages (Chat, Vote, Join, etc.)
Layer 6: Presentation   - Binary serialization (Serde)
Layer 5: Session        - Connection state, Session IDs
Layer 4: Transport      - TCP (reliable) / UDP (fast) + Bandwidth control
```

**Key Features:**
- **Custom Headers:** Version, Flags, Sequence Numbers, Checksums
- **Session Management:** UUID-based session tracking
- **Bandwidth Control:** Rate limiting & monitoring
- **Binary Protocol:** Efficient serialization with optional compression
- **Error Handling:** CRC checksum validation

**Message Types:**
- `JoinGame` - Player joins a game room
- `LeaveGame` - Player leaves a room
- `ChatMessage` - In-game chat message
- `Vote` - Player votes for elimination
- `PhaseChange` - Day/Night phase transition
- `RoleReveal` - Role reveal at game end

**Packet Structure:**
```
| Transport Header | Session Header | Presentation | Payload |
|  (12 bytes)      | (24 bytes)     | (4 bytes)    | (var)   |
```

---

## 🔧 Development Tools & Scripts

**Location:** `scripts/`

### **setup.ps1** - Initial Project Setup
Automated setup script that:
- ✅ Checks prerequisites (Rust, Flutter, Docker)
- ✅ Creates `.env` configuration file
- ✅ Installs Flutter dependencies
- ✅ Builds Rust workspace
- ✅ Starts PostgreSQL database

**Usage:**
```powershell
.\scripts\setup.ps1
```

### **test_all.ps1** - Comprehensive Testing
Runs all workspace tests:
- Unit tests for game logic
- Network protocol tests
- Database integration tests

**Usage:**
```powershell
.\scripts\test_all.ps1
```

### **test_sockets.mjs** - Network Testing
Node.js script for testing socket connectivity:
- TCP connection tests
- WebSocket handshake tests
- Bandwidth throttling tests
- Message serialization tests

**Usage:**
```powershell
node scripts/test_sockets.mjs
```

---

## 📊 Cargo Workspace

**Location:** `Cargo.toml`

**Workspace Members:**
1. **`core`** - areyoughost_core library
   - Game logic
   - Networking primitives
   - FFI exports
   
2. **`server`** - areyoughost_server binary
   - Axum HTTP/WebSocket server
   - User authentication
   - Game orchestration

**Shared Dependencies:**
- `tokio` - Async runtime
- `serde` - Serialization
- `uuid` - Unique identifiers
- `chrono` - Datetime handling
- `tracing` - Structured logging

**Key Commands:**
```powershell
# Build all workspace members
cargo build --workspace

# Test all members
cargo test --workspace

# Format code
cargo fmt --all

# Lint with Clippy
cargo clippy --workspace --all-targets

# Build for release
cargo build --workspace --release
```

---

## 📖 Documentation

- **[Architecture Overview](docs/ARCHITECTURE.md)** - System architecture, component design, and interaction patterns
- **[Development Guide](docs/DEVELOPMENT.md)** - Setup, build, debugging, and development workflow
- **[Protocol Specification](docs/PROTOCOL.md)** - High-level network protocol overview
- **[Network Protocol Details](protocol/protocol_spec.md)** - Custom TCP/UDP protocol with OSI layers
- **[Cloudflare Tunnel Setup](CLOUDFLARE_TUNNEL.md)** - External server deployment for multiplayer
- **[Contributing Guide](CONTRIBUTING.md)** - Code style, workflow, and pull request process

## 🌐 Network & Communication

The project implements a **multi-layered protocol** for real-time multiplayer:

**HTTP/WebSocket Server:**
- **Authentication:** JWT-based login and session management
- **Real-Time Sync:** WebSocket events for game state updates
- **Room Management:** Create, Join, Leave with persistent DB storage
- **REST API:** Game lobbies, user management, statistics

**Custom Protocol:**
- **Layer 4 (Transport):** TCP for reliable game messages, UDP for bandwidth-critical updates
- **Layer 5 (Session):** UUID-based identification and connection management
- **Layer 6 (Presentation):** Binary serialization with optional LZ4 compression
- **Layer 7 (Application):** Game messages (Join, Chat, Vote, Phase, Role, Win/Loss)

**Message Examples:**
```json
{ "type": "JoinGame", "player_id": "uuid", "room_id": "uuid" }
{ "type": "ChatMessage", "text": "...", "timestamp": 1234567890 }
{ "type": "Vote", "player_id": "uuid", "target_id": "uuid" }
{ "type": "PhaseChange", "phase": "day|night", "duration": 300 }
```

## 🧪 Testing & Quality Assurance

### Running Tests

**Run all tests in workspace:**
```powershell
cargo test --workspace -- --nocapture
```

**Run tests for specific package:**
```powershell
cargo test --package areyoughost_core --lib
cargo test --package areyoughost_server --lib
```

**Run tests with output:**
```powershell
cargo test --workspace -- --nocapture --test-threads=1
```

**Run specific test:**
```powershell
cargo test game_logic::state::tests -- --nocapture
```

### Code Quality Tools

**Format code with rustfmt:**
```powershell
cargo fmt --all
```

**Lint with Clippy:**
```powershell
cargo clippy --workspace --all-targets --all-features
```

**Check for security vulnerabilities:**
```powershell
cargo audit
```

**Generate documentation:**
```powershell
cargo doc --workspace --no-deps --open
```

### Flutter/Dart Testing

**Run Flutter tests:**
```powershell
cd frontend
flutter test
```

**Analyze Flutter code:**
```powershell
flutter analyze
```

**Format Dart code:**
```powershell
dart format lib/
```

---

## 📊 Database Schema Quick Reference

**Main Tables:**

| Table | Purpose | Key Fields |
|-------|---------|-----------|
| `users` | Player accounts | `id`, `username`, `email`, `password_hash` |
| `lobbies` | Game rooms | `id`, `name`, `host_id`, `max_players`, `status` |
| `game_sessions` | Active games | `id`, `lobby_id`, `current_phase`, `round` |
| `players` | Player assignments | `id`, `user_id`, `game_id`, `role`, `is_alive` |
| `chat_messages` | Game chat | `id`, `game_id`, `sender_id`, `text`, `created_at` |
| `votes` | Vote records | `id`, `game_id`, `voter_id`, `target_id`, `round` |

**Connect to PostgreSQL:**
```powershell
# Via PgAdmin GUI
# http://localhost:8080
# Email: admin@areyoughost.com, Password: admin

# Via psql CLI (if installed)
psql -h localhost -U admin -d areyoughost
```

---

## 🐛 Troubleshooting

### Common Issues

**1. Port Already in Use (3000)**
```powershell
# Find process using port 3000
netstat -ano | findstr :3000

# Kill the process (replace PID with actual process ID)
taskkill /PID <PID> /F

# Or run server on different port
$env:PORT=3001
cargo run -p areyoughost_server
```

**2. PostgreSQL Connection Failed**
```powershell
# Check if containers are running
docker ps

# Restart containers
docker-compose restart

# Check logs
docker-compose logs postgres
```

**3. Flutter Build Fails**
```powershell
cd frontend

# Clean build
flutter clean
flutter pub get
flutter pub upgrade

# Rebuild
flutter build windows
```

**4. Rust Compilation Errors**
```powershell
# Update Rust toolchain
rustup update

# Clean build artifacts
cargo clean

# Rebuild
cargo build --workspace
```

**5. FFI Issues (Flutter ↔ Rust)**
```powershell
# Regenerate FFI bindings
cd frontend
flutter_rust_bridge_codegen generate
```

### Debugging

**Enable Rust backtrace:**
```powershell
$env:RUST_BACKTRACE=1
cargo run -p areyoughost_server
```

**Enable logging:**
```powershell
$env:RUST_LOG=debug
cargo run -p areyoughost_server
```

**Check database connectivity:**
```powershell
Select-String -Path .env -Pattern "^DATABASE_URL"
# Test connection with sqlx-cli
cargo install sqlx-cli
sqlx db create
sqlx migrate run
```

### Performance Testing

**Run network benchmarks:**
```powershell
cargo test --package areyoughost_core network::benchmarks -- --nocapture --test-threads=1
```

**Check binary sizes:**
```powershell
du -sh target/release/
```

---

## ⚙️ Configuration & Environment Variables

### Environment Setup

**Create `.env` file from template:**
```powershell
Copy-Item .env.example -Destination .env
```

**Key Environment Variables:**

```env
# Database Configuration
DATABASE_URL=postgres://admin:admin@localhost:5432/areyoughost
DB_CONNECTION_POOL_SIZE=10

# Server Configuration
HOST=127.0.0.1
PORT=3000
LOG_LEVEL=info

# JWT/Authentication
JWT_SECRET=your-secret-key-here
SESSION_EXPIRY_HOURS=24

# Game Configuration
MAX_PLAYERS_PER_ROOM=16
DAY_PHASE_DURATION_SECONDS=300
NIGHT_PHASE_DURATION_SECONDS=120

# Network Configuration
BANDWIDTH_LIMIT_MBPS=10
PACKET_MAX_SIZE_BYTES=65536

# Cloudflare Tunnel (for external access)
CLOUDFLARE_TUNNEL_TOKEN=your-token-here
CLOUDFLARE_TUNNEL_URL=your-tunnel.cfargotunnel.com
```

### Docker Compose Variables

**Edit `docker-compose.yml`:**
```yaml
services:
  postgres:
    environment:
      POSTGRES_USER: admin
      POSTGRES_PASSWORD: admin
      POSTGRES_DB: areyoughost
    ports:
      - "5432:5432"
  
  pgadmin:
    environment:
      PGADMIN_DEFAULT_EMAIL: admin@areyoughost.com
      PGADMIN_DEFAULT_PASSWORD: admin
    ports:
      - "8080:80"
```

---

## 🚀 Deployment & Production

### Building for Release

**Build Rust binaries:**
```powershell
cargo build --workspace --release
# Output: target/release/server.exe
```

**Build Flutter for Windows:**
```powershell
cd frontend
flutter build windows --release
# Output: build/windows/runner/Release/
```

### Docker Deployment

**Build Docker image:**
```powershell
docker build -f Dockerfile -t areyoughost:latest .
```

**Run in production:**
```powershell
docker run -p 3000:3000 \
  -e DATABASE_URL=postgres://user:pass@db:5432/areyoughost \
  -e LOG_LEVEL=warn \
  areyoughost:latest
```

### Using Cloudflare Tunnel

**Setup external access:** 
[→ Cloudflare Tunnel Setup Guide](CLOUDFLARE_TUNNEL.md)

---

## 🎯 Quick Reference Commands

### Rust Workspace

```powershell
# Development
cargo run -p areyoughost_server          # Run server
cargo run --example migrate              # Run migrations
cargo test --workspace                   # Run all tests
cargo build --workspace                  # Development build
cargo build --workspace --release        # Release build

# Code Quality
cargo fmt --all                          # Format code
cargo clippy --workspace                 # Lint code
cargo doc --workspace --open             # Generate docs  
cargo audit                              # Check vulnerabilities

# Database
sqlx db create                           # Create database
sqlx migrate run                         # Run migrations
sqlx migrate add <name>                  # Create migration
```

### Flutter Frontend

```powershell
cd frontend

# Setup & Build
flutter pub get                          # Install dependencies
flutter pub upgrade                      # Upgrade dependencies
flutter pub outdated                     # Check outdated packages

# Running
flutter run -d windows                   # Run on Windows
flutter build windows --release          # Build release version

# Testing & Quality
flutter test                             # Run tests
flutter analyze                          # Lint code
dart format lib/                         # Format code
flutter clean                            # Clean build artifacts
```

### Docker

```powershell
# Database Management
docker-compose up -d                     # Start services
docker-compose down                      # Stop services
docker-compose logs postgres             # View database logs
docker-compose ps                        # List running containers
docker-compose exec postgres psql ...    # Run psql commands
```

---

**Current Phase:** Frontend Integration (Phase 5)

### Completed ✅
- [x] Project structure and workspace setup
- [x] Flutter UI screens (Login, Lobby, Game)
- [x] HTTP/WebSocket server with health checks
- [x] Supabase PostgreSQL integration and schema migrations
- [x] FFI bridge configuration
- [x] Cloudflare Tunnel integration
- [x] Real-time multiplayer room synchronization (WebSockets)
- [x] Comprehensive documentation

### In Progress 🚧
- [ ] Frontend to Backend FFI / WebSocket Integration
- [ ] Game state machine implementation
- [ ] Matchmaking system
- [ ] Voice/Text Chat integration
- [ ] Role distribution system
- [ ] Vote counting and win conditions

### Planned ⏳
- [ ] Complete game logic (all roles)
- [ ] Replay system
- [ ] Player statistics
- [ ] Matchmaking system
- [ ] Mobile support (iOS/Android)

## 🤝 Contributing

Contributions are welcome! Please read our [Contributing Guide](CONTRIBUTING.md) for:

- Code style guidelines
- Development workflow
- Pull request process
- Testing requirements

**[→ Contributing Guide](CONTRIBUTING.md)**

## 📄 License

This project is dual-licensed under:
- **MIT License** ([LICENSE-MIT](LICENSE-MIT))
- **Apache License 2.0** ([LICENSE-APACHE](LICENSE-APACHE))

You may choose either license for your use.

## 🔗 Resources

- [Rust Book](https://doc.rust-lang.org/book/)
- [Flutter Documentation](https://flutter.dev/docs)
- [Tokio Async Runtime](https://tokio.rs)
- [Axum Web Framework](https://docs.rs/axum/)
- [sqlx Database Library](https://docs.rs/sqlx/)

## 👥 Team

**This hole has a story team**

---

**Built with ❤️ using Rust and Flutter**
