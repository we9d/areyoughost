# Development Guide

This guide covers setting up the development environment for the **Are You Ghost** dual-port architecture.

## Getting Started

### Prerequisites
- **Rust** & **Flutter SDK**
- **Docker Desktop** (for PostgreSQL)
- **Wireshark** (Highly recommended for Layer 4 TCP packet analysis)

### Automated Setup (Recommended)
We provide a PowerShell script that initializes the environment, generates `.env`, and builds the workspace:

```powershell
# Run from the project root
powershell -ExecutionPolicy Bypass -File scripts/setup.ps1
```

## Running the Architecture

### 1. Database Layer
Start the PostgreSQL container (mapped to Port **5433** to avoid conflicts):

```powershell
docker-compose up -d
```

### 2. Backend Layer (Rust Server)
The server runs on two distinct ports. Start it with debug logging enabled to monitor incoming binary frames:

```powershell
$env:RUST_LOG="info,areyoughost_server=debug,areyoughost_core=debug"
cargo run -p areyoughost_server
```

**Expected Output:**
- 🌐 **HTTP Management API** listening on `0.0.0.0:3000`
- 🔌 **TCP Game Server** listening on `0.0.0.0:8080`

### 3. Frontend Layer (Flutter Client)
Run the desktop client:

```powershell
cd frontend
flutter run -d windows
```

## Network Testing & Debugging
Because we use a custom binary protocol, standard tools like Postman cannot interact with the game server on Port 8080.

### Testing the TCP Server
Use the custom Node.js script to simulate a client sending exact byte frames:

```powershell
node scripts/test_sockets.mjs
```

### Testing the Management API (HTTP)
You can still use standard tools for the health check port:

```powershell
curl http://localhost:3000/health
```

### Database Management
Access PgAdmin to verify game state persistence:
- **URL:** [http://localhost:5050](http://localhost:5050)
- **User:** `admin@areyoughost.com`
- **Password:** `admin`

## Common Troubleshooting
- **Os Error 10048 (Address already in use):** Port 8080 or 3000 is occupied. Kill the existing process:
  `netstat -ano | findstr :8080` then `taskkill /PID <PID> /F`
- **Database Connection Failed:** Ensure your `.env` points to port **5433** (as defined in `docker-compose.yml`), not 5432.
