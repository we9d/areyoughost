# Are You Ghost - Backend Server
The authoritative backend server for the Are You Ghost multiplayer game.

This server implements a **Dual-Port Architecture** to separate high-performance, real-time game traffic from standard web-based management requests, fulfilling the requirements for the Data Communications and Network course.

## Features
- 🔌 **Areyoughost Binary Protocol (Port 8080)** - A custom raw TCP socket implementation (Layer 4) with strict binary framing ([Magic][Type][Len][Payload][CRC]) for zero-latency game state synchronization.
- 🌐 **HTTP Management API (Port 3000)** - A lightweight HTTP server for basic health checks and infrastructure monitoring.
- 🔒 **Zero-Trust Client Isolation** - The server acts as the sole authority communicating with the PostgreSQL database. Clients never access the database directly.
- 🧵 **Arc-Based State Management** - Thread-safe, asynchronous state handling using tokio to support 16 concurrent players without data races.

## Running the Server
### Prerequisites
Ensure your database is running on port **5433** (via Docker or local setup) and your `.env` file is properly configured.

### Start the server
```powershell
# From project root
cd server
cargo run

# Or from anywhere in the workspace
cargo run -p areyoughost_server
```

When started successfully, the server will bind to multiple ports:
```plaintext
🚀 HTTP Management API listening on 0.0.0.0:3000
🔌 Areyoughost TCP Game Server listening on 0.0.0.0:8080
📍 Health check available at: http://localhost:3000/health
```

### Test the Management API
```powershell
curl.exe http://localhost:3000/health
```
Expected HTTP response:
```json
{"server":"areyoughost","status":"ok","timestamp":"2026-03-26T12:00:00Z"}
```

## Network Interfaces & Ports
| Protocol | Port | Path / Interface | Description |
|----------|------|------------------|-------------|
| **TCP** | 8080 | Raw Socket | Primary Game Protocol. Expects binary frames with magic bytes `0xAE 0x80`. |
| **HTTP** | 3000 | `/health` | Server health check and uptime status. |
| **HTTP** | 3000 | `/` | Root endpoint (same as `/health`). |

*(Note: WebSocket (`/ws`) has been entirely deprecated in favor of the custom Layer 4 TCP implementation).*

## Project Structure
```plaintext
server/
├── src/
│   ├── main.rs          # Server entry point (Initializes Tokio runtime)
│   ├── tcp_server.rs    # Port 8080: TCP Listener & Binary Frame Parser
│   ├── http_server.rs   # Port 3000: Axum Management API
│   └── engine.rs        # Prioritized skill execution & Arc-based game state
├── Cargo.toml           # Server dependencies
└── README.md            # This file
```

## Core Dependencies
- **tokio** - Asynchronous runtime underlying both the TCP and HTTP servers.
- **bincode / serde** - Fast, compact binary serialization for Layer 6 presentation.
- **crc** - Calculates the CRC16-IBM-SDLC checksums for Layer 7 data integrity.
- **axum** - Lightweight framework used only for the Port 3000 Management API.
- **areyoughost_core** - Core game logic, state machines, and protocol definitions (from `../core`).

## Development & Debugging
The server strictly depends on the `areyoughost_core` library. To monitor binary frames and protocol parsing, enable debug logging:

```powershell
# Run with detailed TCP frame logging
$env:RUST_LOG="info,areyoughost_server=debug,areyoughost_core=debug"
cargo run -p areyoughost_server
```

To verify the protocol integrity at the packet level, run **Wireshark**, attach to the loopback interface (**Adapter for loopback traffic capture**), and filter by `tcp.port == 8080`.
