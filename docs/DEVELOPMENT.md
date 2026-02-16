# Development Guide

## Getting Started

This guide will help you set up your development environment for **Are You Ghost**.

## Prerequisites

Ensure you have the following installed:

- **Rust** (latest stable) - [Install Rust](https://www.rust-lang.org/tools/install)
- **Flutter SDK** (latest stable) - [Install Flutter](https://flutter.dev/docs/get-started/install)
- **Visual Studio** (with C++ build tools) - [Download](https://visualstudio.microsoft.com/vs/community/)
- **Docker Desktop** (for PostgreSQL) - [Install Docker](https://www.docker.com/products/docker-desktop)
- **Git** - [Install Git](https://git-scm.com/downloads)

### Visual Studio Configuration

When installing Visual Studio, select:
- **Desktop development with C++**
- MSVC v143 - VS 2022 C++ x64/x86 build tools
- Windows 10/11 SDK
- C++ CMake tools for Windows

## Initial Setup

### 1. Clone the Repository

```powershell
git clone https://github.com/we9d/areyoughost.git
cd areyoughost
```

### 2. Set Up Environment Variables

Copy the example environment file and configure it:

```powershell
Copy-Item .env.example -Destination .env
```

Edit `.env` to match your local configuration. Default values work for local development.

### 3. Start the Database

Start PostgreSQL and PgAdmin using Docker Compose:

```powershell
docker-compose up -d
```

Verify the database is running:
- **PostgreSQL:** `localhost:5432`
- **PgAdmin:** http://localhost:8080
  - Email: `admin@areyoughost.com`
  - Password: `admin`

### 4. Build the Rust Workspace

Build all Rust components:

```powershell
cargo build --workspace
```

This will build both `core` and `server` crates.

### 5. Install Flutter Dependencies

```powershell
cd frontend
flutter pub get
```

## Development Workflow

### Running the Server

Start the backend server:

```powershell
# From project root
cargo run -p areyoughost_server

# Or from server directory
cd server
cargo run
```

The server will start on http://localhost:3000

**Endpoints:**
- Health Check: http://localhost:3000/health
- WebSocket: ws://localhost:3000/ws

### Running the Flutter App

Start the desktop application:

```powershell
cd frontend
flutter run -d windows
```

The app will launch in a centered window with mobile-like dimensions (390x844).

### Working with Database

#### Running Migrations

```powershell
# Install sqlx-cli if not already installed
cargo install sqlx-cli --features postgres

# Run migrations
cd core
sqlx migrate run
```

#### Creating New Migrations

```powershell
cd core
sqlx migrate add <migration_name>
```

Edit the generated SQL file in `core/migrations/`.

#### Accessing PgAdmin

1. Open http://localhost:8080
2. Login with credentials from `docker-compose.yml`
3. Add server connection:
   - Host: `db` (Docker service name)
   - Port: `5432`
   - Database: `areyoughost`
   - Username: `postgres`
   - Password: `password`

## Code Quality

### Formatting

Format all Rust code:

```powershell
cargo fmt --all
```

Check formatting without modifying files:

```powershell
cargo fmt --all -- --check
```

### Linting

Run Clippy on all workspace members:

```powershell
cargo clippy --workspace --all-targets
```

Fix Clippy warnings automatically (when safe):

```powershell
cargo clippy --workspace --all-targets --fix
```

### Testing

Run all tests:

```powershell
# All workspace tests
cargo test --workspace

# Specific package
cargo test -p areyoughost_core
cargo test -p areyoughost_server

# With output
cargo test -- --nocapture

# Specific test
cargo test test_name
```

## Hot Reload

### Flutter Hot Reload

While the Flutter app is running:
- Press `r` to hot reload UI changes
- Press `R` to hot restart (full app restart)

### Rust Changes

Rust requires recompiling. For faster iteration:

```powershell
# Use cargo-watch for auto-recompile
cargo install cargo-watch

# Watch and restart server on changes
cargo watch -x 'run -p areyoughost_server'
```

## Debugging

### Rust Debugging

Enable verbose logging:

```powershell
$env:RUST_LOG="debug,areyoughost_core=trace,areyoughost_server=trace"
cargo run -p areyoughost_server
```

Enable backtrace on panic:

```powershell
$env:RUST_BACKTRACE="1"
cargo run
```

### Flutter Debugging

Run Flutter in debug mode (default):

```powershell
flutter run -d windows
```

Enable verbose logging:

```powershell
flutter run -d windows -v
```

### Database Debugging

View query logs in real-time:

```powershell
docker-compose logs -f db
```

## Project Structure

```
areyoughost/
├── core/                   # Rust core library
│   ├── src/
│   │   ├── api.rs         # FFI exports
│   │   ├── game_logic/    # Game state machine
│   │   ├── network/       # Custom network stack
│   │   ├── db/            # Database layer
│   │   └── models.rs      # Data structures
│   ├── Cargo.toml
│   └── migrations/        # Database migrations
│
├── server/                # HTTP/WebSocket server
│   ├── src/
│   │   └── main.rs
│   └── Cargo.toml
│
├── frontend/              # Flutter desktop app
│   ├── lib/
│   │   ├── ui/           # Screens
│   │   ├── services/     # API layer
│   │   ├── state/        # State management
│   │   └── ffi/          # Rust FFI bindings
│   └── pubspec.yaml
│
├── docs/                  # Documentation
├── examples/              # Code examples
├── scripts/               # Build/dev scripts
├── protocol/              # Network protocol spec
└── docker-compose.yml     # Database services
```

## Common Tasks

### Add a New Rust Dependency

Edit `core/Cargo.toml` or `server/Cargo.toml`:

```toml
[dependencies]
new_crate = "1.0"
```

Then build:

```powershell
cargo build
```

### Add a New Flutter Dependency

Edit `frontend/pubspec.yaml`:

```yaml
dependencies:
  new_package: ^1.0.0
```

Then install:

```powershell
cd frontend
flutter pub get
```

### Generate FFI Bindings

After changing Rust FFI functions:

```powershell
cd frontend
flutter_rust_bridge_codegen generate
```

### Clean Build

Remove all build artifacts:

```powershell
# Rust
cargo clean

# Flutter
cd frontend
flutter clean
```

## Performance Profiling

### Rust Profiling

Use `cargo-flamegraph`:

```powershell
cargo install flamegraph

# Profile server
cargo flamegraph -p areyoughost_server
```

### Flutter Profiling

Run in profile mode:

```powershell
flutter run --profile -d windows
```

## Troubleshooting

### "Failed to bind to 0.0.0.0:3000"

Port 3000 is already in use. Find and kill the process:

```powershell
# Find process using port 3000
netstat -ano | findstr :3000

# Kill process (replace PID)
taskkill /PID <PID> /F
```

### Flutter Build Errors

Clean and rebuild:

```powershell
cd frontend
flutter clean
flutter pub get
flutter run -d windows
```

### Database Connection Failed

Ensure Docker containers are running:

```powershell
docker-compose ps
docker-compose up -d
```

### FFI Binding Errors

Regenerate bindings:

```powershell
cd frontend
flutter_rust_bridge_codegen generate
flutter pub get
```

## Contributing

See [CONTRIBUTING.md](../CONTRIBUTING.md) for contribution guidelines.

## Additional Resources

- [Rust Documentation](https://doc.rust-lang.org/)
- [Flutter Documentation](https://flutter.dev/docs)
- [Axum Guide](https://docs.rs/axum/)
- [sqlx Documentation](https://docs.rs/sqlx/)
- [Tokio Tutorial](https://tokio.rs/tokio/tutorial)
