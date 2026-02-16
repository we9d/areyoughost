# Are You Ghost?

A desktop-first multiplayer social deduction game where players must identify the "ghost" among them through discussion and voting. Built with Flutter for the frontend and Rust for the backend engine.

## 🎮 About the Game

**Are You Ghost?** is a social deduction game inspired by Mafia and Werewolf. Players engage in rounds of discussion and voting to identify hidden ghost players before it's too late. The game features:

- **Multiplayer lobbies** supporting up to 16 players per room
- **Real-time chat** during discussion phases
- **Voting mechanics** to eliminate suspected ghosts
- **Desktop-optimized UI** with mobile-like display (390x844) centered on screen

## 🏗️ Architecture

This is a **monorepo** project with a clear separation between frontend and backend:

### Tech Stack

- **Frontend**: Flutter (Desktop - Windows)
  - UI framework for cross-platform desktop application
  - FFI integration with Rust backend
  - State management for game flow
  - Network monitoring and control UI
  
- **Backend**: Rust
  - **Custom Network Stack** (OSI Layers 4-7)
    - Raw TCP/UDP socket programming
    - Custom protocol design (no pre-built networking libraries)
    - Bandwidth throttling and QoS control
    - Multi-connection async runtime (Tokio)
  - **Core Game Logic**: State machine and rule enforcement
  - **Database**: PostgreSQL (via `sqlx`) for persistence
  - **API**: HTTP/WebSocket (Axum) for communication
  - **FFI**: Exports for Flutter integration
  - FFI exports for Flutter integration

### Network Architecture

Our custom network implementation provides control over all OSI layers:

- **Layer 7 (Application)**: Game protocol, message routing
- **Layer 6 (Presentation)**: Custom serialization, compression
- **Layer 5 (Session)**: Connection management, session state
- **Layer 4 (Transport)**: Raw TCP/UDP sockets, bandwidth control
- **Layers 1-3**: Monitored via socket statistics

### Project Structure

```
areyoughost/
├── frontend/              # Flutter application (UI Layer)
│   └── lib/
│       ├── ui/           # Screens (Login, Lobby, Game)
│       ├── ffi/          # Rust FFI bindings
│       ├── state/        # App state management
│       ├── services/     # API service layer (RustApi)
│       ├── models/       # Data models
│       └── theme/        # UI theming
│
├── core/                 # Rust library (Game Engine & Network)
│   └── src/
│       ├── api/          # FFI exports to Flutter
│       ├── network/      # TCP socket handling
│       ├── game_logic/   # Game state machine
│       ├── db/           # Database operations
│       ├── models/       # Data structures
│       └── utils/        # Helper functions
│
├── protocol/             # Network protocol specifications
│   ├── message_types.md  # Message type definitions
│   └── packet_format.md  # Packet structure
│
└── docs/                 # Project documentation
```

## 🚀 Getting Started

### Prerequisites

- **Flutter SDK** (latest stable) - [Install Flutter](https://flutter.dev/docs/get-started/install)
- **Visual Studio** (latest stable) - [Install Visual Studio](https://visualstudio.microsoft.com/vs/community/)
- **Git Hub Desktop** (latest stable) - [Install Git Hub Desktop](https://desktop.github.com/download/)
- **Git** (latest stable) - [Install Git](https://gitforwindows.org/)
- **Rust** (latest stable) - [Install Rust: RUSTUP-ININT.exe (x64)](https: //www.rust-lang.org/tools/install)
- **PostgreSQL** (running via Docker or local)

### Installation
1. **Git Hub Desktop**
```
   Log in with your Git Hub account
   ;If don't have ,create.

```
2. **Git**

```
   Set up the git 
```

3. **Clone the repository**

   ```bash
   git clone https://github.com/we9d/areyoughost.git
   cd areyoughost
   ```
4. **Set path of flutter**

   ```
   -Extact zip file of flutter ,then select path to "C:\flutter" .
   -Search "Edit the system environment variable" in window.
   -Select "Environment variable".
   -Double click on "Path" in section of "User variable for ...".
   -Click "Add new" ,then browse path "C:\flutter\bin" .
   -Click "ok" all of windows.
   -Check version of flutter in cmd ,type "flutter --version"
   -If it show version ,then it complete!
   ```

4. **Set up Visual Studio**

   ```Open Vs
   Work Load : Desktop development with C++
   Installation Detail (Right side) : Select All of these
   - MSVC v143 - VS 2022 C++ x64/x86 build tools
   - Windows 10 SDK หรือ Windows 11 SDK
   - C++ CMake tools for Windows
   ```

5. **Install Flutter dependencies in Vs code**

   ```bash
   cd frontend
   flutter pub get
   ```

6. **Build Rust core in Vs code**

   ```bash
   cd ../core
   cargo build
   ```

### Running the Application
1. **Run App Frontend**

   ```bash
   cd frontend
   flutter run
   Enter 1  windows
   ```
2. **Run App Core**
   ```bash
      cd core
      cargo run
   ```


#### Frontend (Flutter Desktop)

```bash
cd frontend
flutter pub get
flutter run -d windows
```

The app will launch in a desktop window with a centered mobile-like display (390x844 resolution).

#### Backend (Rust Core)

To check the Rust code:

```bash
cd core
cargo check
```

To run tests:

```bash
cargo test
```

## 📦 Dependencies

### Frontend (Flutter)

- `flutter_rust_bridge` - FFI integration with Rust
- Custom UI components for game screens

### Backend (Rust)

- `sqlx` - PostgreSQL client (async)
- `serde` & `serde_json` - Serialization
- `flutter_rust_bridge` - FFI bridge
- `tokio` - Async runtime for networking
- `anyhow` - Error handling

## 🔧 Development Status

**Current Phase**: Network Stack Implementation

- ✅ Project structure established
- ✅ Basic UI screens (Login, Lobby, Game)
- ✅ Mock API service layer
- ✅ Architecture planning complete
- 🚧 **Custom Network Stack** (in progress)
  - 🚧 Raw socket implementation (TCP/UDP)
  - 🚧 Custom packet protocol design
  - 🚧 Bandwidth control system
  - 🚧 OSI layer monitoring
- 🚧 FFI integration
- 🚧 Rust game logic implementation
- 🚧 Database schema (PostgreSQL)
- ⏳ Real-time multiplayer functionality

## 📝 Protocol

The game uses a custom TCP-based protocol for client-server communication. See the `protocol/` directory for detailed specifications:

- **Message Types**: Defines all message types (login, room actions, game events)
- **Packet Format**: Binary packet structure and encoding

## 🤝 Contributing

This is a project in active development. Contributions, issues, and feature requests are welcome!

## 📄 License

[Add your license here]

## 🔗 Links

- [Flutter Documentation](https://flutter.dev/docs)
- [Rust Documentation](https://www.rust-lang.org/learn)
