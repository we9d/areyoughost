# Are You Ghost? (Project Ghost Game)

A desktop-first multiplayer social deduction game consisting of a Flutter frontend and a Rust core engine.

## Structure

- **frontend/**: Flutter application (UI Layer)
  - `lib/ui`: Screens and Widgets
  - `lib/ffi`: Rust integration
  - `lib/state`: App state management
  - `lib/services`: Logic adapters
- **core/**: Rust library (Network & Game Engine)
  - `api`: FFI exports
  - `network`: TCP socket handling
  - `game_logic`: State machine for the game
- **protocol/**: Protocol design documents
- **docs/**: Project documentation (Architecture, Database, Network)

## Getting Started

### Prerequisites

- Flutter SDK (latest stable)
- Rust (latest stable)
- SQLite (for database, if needed locally)

### Running the Frontend

```bash
cd frontend
flutter pub get
flutter run -d windows
```

### Checking the Core

```bash
cd core
cargo check
```
