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
  
- **Backend**: Rust
  - Core game logic and state machine
  - TCP networking for multiplayer
  - SQLite database for persistence
  - FFI exports for Flutter integration

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
- **Rust** (latest stable) - [Install Rust](https://www.rust-lang.org/tools/install)
- **SQLite** (bundled via rusqlite)

### Installation

1. **Clone the repository**
   ```bash
   git clone <repository-url>
   cd areyoughost
   ```

2. **Install Flutter dependencies**
   ```bash
   cd frontend
   flutter pub get
   ```

3. **Build Rust core**
   ```bash
   cd ../core
   cargo build
   ```

### Running the Application

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
- `rusqlite` - SQLite database with bundled library
- `serde` & `serde_json` - Serialization
- `flutter_rust_bridge` - FFI bridge
- `tokio` - Async runtime for networking
- `anyhow` - Error handling

## 🔧 Development Status

**Current Phase**: Early Development

- ✅ Project structure established
- ✅ Basic UI screens (Login, Lobby, Game)
- ✅ Mock API service layer
- ✅ Protocol documentation
- 🚧 FFI integration (in progress)
- 🚧 Rust game logic implementation
- 🚧 Network layer implementation
- ⏳ Database schema and operations
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
