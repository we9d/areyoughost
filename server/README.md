# Are You Ghost - Server

HTTP/WebSocket server for the Are You Ghost multiplayer game.

## Features

- ✅ **HTTP Health Check** - `GET /` and `GET /health`
- ✅ **WebSocket Support** - `GET /ws`  
- ✅ **Binds to 0.0.0.0:3000** - Allows external connections
- ✅ **CORS Enabled** - Browser client support
- ✅ **Cloudflare Tunnel Ready** - Works with Quick Tunnel

## Running the Server

### Start the server

```powershell
# From project root
cd server
cargo run

# Or from anywhere in the workspace
cargo run -p areyoughost_server
```

The server will start on `0.0.0.0:3000`:

```
🚀 Server listening on 0.0.0.0:3000
📍 Health check: http://localhost:3000/health
🔌 WebSocket: ws://localhost:3000/ws
```

### Test the health check

```powershell
curl.exe http://localhost:3000/health
```

Expected response:
```json
{"server":"areyoughost","status":"ok","timestamp":"2026-02-16T13:00:00Z"}
```

## Cloudflare Quick Tunnel

See [CLOUDFLARE_TUNNEL.md](../CLOUDFLARE_TUNNEL.md) for complete setup instructions.

**Quick start:**

1. Start the server: `cargo run`
2. In a new terminal: `cloudflared tunnel --url http://localhost:3000`
3. Share the generated `https://xxxx.trycloudflare.com` URL

## Project Structure

```
server/
├── src/
│   └── main.rs          # Server entry point
├── Cargo.toml           # Server dependencies
└── README.md            # This file
```

## Endpoints

| Method | Path | Description |
|--------|------|-------------|
| GET | `/` | Health check (returns JSON status) |
| GET | `/health` | Health check (same as `/`) |
| GET | `/ws` | WebSocket endpoint for game connections |

## Dependencies

- **axum** - Web framework
- **tower** - Middleware utilities
- **tower-http** - HTTP middleware (CORS, tracing)
- **tokio** - Async runtime
- **areyoughost_core** - Core game logic (from `../core`)

## Development

The server uses the `areyoughost_core` library for game logic. Any changes to the core library will be picked up when you rebuild the server.

```powershell
# Build server
cargo build -p areyoughost_server

# Run with logging
RUST_LOG=debug cargo run -p areyoughost_server

# Run tests
cargo test -p areyoughost_server
```
