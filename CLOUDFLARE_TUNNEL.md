# Cloudflare Quick Tunnel Setup Guide

This guide explains how to expose your local Are You Ghost server to the internet using Cloudflare Quick Tunnel, allowing friends to connect from anywhere.

## Prerequisites

✅ **Server binds to `0.0.0.0`** (not `127.0.0.1`)  
✅ **Health check endpoint** available at `/` or `/health`  
✅ **WebSocket endpoint** available at `/ws`

---

## Host Machine Setup

### 1. Start the Database

```powershell
docker compose up -d db
```

This starts the PostgreSQL database in the background.

### 2. Start the Server

```powershell
cd server
$env:DATABASE_URL="postgres://postgres:password@localhost:5432/areyoughost"
cargo run
```

The server will start and listen on **http://localhost:3000**

You should see output like:
```
Server listening on 0.0.0.0:3000
```

> **Note:** Server is ready when you see this message. Test with: `curl http://localhost:3000/health`

### 3. Install Cloudflared

Download `cloudflared` from the [Cloudflare Downloads page](https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/downloads/).

**Direct download links:**
- **Windows**: Download `cloudflared-windows-amd64.exe` and rename to `cloudflared.exe`
- **macOS**: Use Homebrew: `brew install cloudflare/cloudflare/cloudflared`
- **Linux**: Download the appropriate binary for your architecture

**Windows:** Download the `.exe` file  
**macOS:** Use Homebrew: `brew install cloudflare/cloudflare/cloudflared`  
**Linux:** Download the binary or use package manager

### 4. Run Quick Tunnel

Open a **new terminal** and run:

```powershell
cloudflared tunnel --url http://localhost:3000
```

> **Note:** Use this command as-is (replace the port if your server runs on a different port).

You will see output like:

```
Your quick Tunnel has been created! Visit it at (it may take some time to be reachable):
https://xxxx-yyyy-zzzz.trycloudflare.com
```

### 5. Share the URL

Send the `https://xxxx.trycloudflare.com` URL to your friends.

> **Note:** Quick Tunnel URLs are temporary and change each time you run the command.

---

## Client Setup (Your Friends)

### 1. Download the Game

Download the `.exe` file for the game (provided by host).

### 2. Configure Server URL

In the game settings, enter the Cloudflare URL:

**Server URL:** `https://xxxx.trycloudflare.com`

The game will automatically connect to:
- **HTTP endpoints:** `https://xxxx.trycloudflare.com/health`
- **WebSocket:** `wss://xxxx.trycloudflare.com/ws`

> **Note:** The protocol changes from `http://` to `https://` and `ws://` to `wss://` when using Cloudflare tunnel.

### 3. Play!

Launch the game and connect. The Cloudflare tunnel handles all the networking automatically.

---

## Method B: Automated URL Sharing (Recommended)

Instead of manually sharing URLs, the host can configure the URL once and the game automatically manages it.

### Host Setup

1. **Get the Cloudflare URL** from the tunnel output:
   ```
   https://successful-trip-mechanism-midwest.trycloudflare.com/
   ```

2. **Configure in game once:**
   - Open the game as host
   - Enter Server URL: `https://successful-trip-mechanism-midwest.trycloudflare.com/`
   - Game saves this to a config file (e.g., `server_config.json`)

3. **Important - URL changes each time:**
   - ⚠️ **Quick Tunnel URL is temporary** - It changes every time you restart `cloudflared`
   - **Host must update the URL in game settings each time the tunnel restarts**
   - This is a limitation of Quick Tunnel (for permanent URLs, use Named Tunnels)

### Client (Friends) Setup

Friends only need to:

1. **Download the game `.exe`** (no other dependencies)
2. **Open the game**
3. **Enter Server URL in settings/connection screen:**
   - Look for "Server URL" or "Connect to Server" screen
   - Enter: `https://xxxxx.trycloudflare.com`
   - ⚠️ **Note:** If the game doesn't have a connection settings screen yet, this feature needs to be implemented first
4. **Click Test/Connect** (to verify connection)
5. **Login/Register** and play!

> **For developers:** If your game doesn't have a server URL input screen yet, you'll need to add:
> - Settings/Connection screen with URL input field
> - "Test Connection" button that validates the URL
> - Config file to save the URL between sessions

---

## Postman (For Collaborators/Testing)

For team members who need to test or work with the API directly:

### Quick Setup

1. **Install Postman** - Download from https://www.postman.com/downloads/

2. **Set base URL variable:**
   - Create environment variable: `baseUrl`
   - Value: `https://xxxx.trycloudflare.com` (your tunnel URL)

3. **Test connection:**
   ```
   GET {{baseUrl}}/
   GET {{baseUrl}}/health
   ```
   Should return: `{"status":"ok",...}`

### Authentication Flow

**1. Register a new user:**
```
POST {{baseUrl}}/auth/register
Content-Type: application/json

{
  "player_name": "test1",
  "password": "1234"
}
```

**2. Login and save token:**
```
POST {{baseUrl}}/auth/login
Content-Type: application/json

{
  "player_name": "test1",
  "password": "1234"
}
```

Response includes: `{"token": "eyJ..."}`

**3. Save token to environment:**
- In Postman Tests tab, add:
  ```javascript
  pm.environment.set("token", pm.response.json().token);
  ```

**4. Use token for protected endpoints:**

Add to request headers:
```
Authorization: Bearer {{token}}
```

### Example CRUD Operations

**Create room:**
```
POST {{baseUrl}}/rooms
Authorization: Bearer {{token}}
Content-Type: application/json

{
  "room_name": "My Game",
  "max_players": 6
}
```

**List rooms:**
```
GET {{baseUrl}}/rooms?status=WAITING
Authorization: Bearer {{token}}
```

**Join room:**
```
POST {{baseUrl}}/rooms/:room_id/join
Authorization: Bearer {{token}}
```

> **Tip:** Create a Postman collection and share it with your team. Include the auth flow and common endpoints.

### Implementation Notes

**For developers:**
- Save server URL to config file: `~/.areyoughost/config.json`
- Auto-populate URL field on next launch
- Validate URL format before connecting
- Show connection status indicator

**Example config structure:**
```json
{
  "server_url": "https://xxxxx.trycloudflare.com",
  "last_connected": "2026-02-16T20:00:00Z"
}
```

---

## Troubleshooting

### ❌ Problem A: Quick Tunnel won't start (config.yml issue)

**Symptoms:**
- `cloudflared tunnel --url` returns error about existing configuration
- Message about "config.yml already exists"

**Cause:** 
Quick Tunnel is **disabled** if a `config.yml` file exists in the `.cloudflared` directory (as specified in Cloudflare's trycloudflare docs).

**Solution:**
```powershell
# Windows
cd %USERPROFILE%\.cloudflared
rename config.yml config.yml.backup

# macOS/Linux
cd ~/.cloudflared
mv config.yml config.yml.backup
```

Alternatively, temporarily rename the entire `.cloudflared` folder:
```powershell
# Windows
cd %USERPROFILE%
rename .cloudflared .cloudflared_backup

# macOS/Linux  
cd ~
mv .cloudflared .cloudflared_backup
```

Then run the Quick Tunnel command again.

---

### ❌ Problem B: Friends can access URL but game won't connect

**Symptoms:**
- Browser can open `https://xxxxx.trycloudflare.com/health`
- Game shows "Connection failed" or timeout

**Common causes:**

1. **Base URL path issue:**
   - Game adds duplicate paths (e.g., `https://xxx.com/auth/auth`)
   - Game hardcodes localhost instead of using config URL
   
2. **Client still using localhost:**
   - Check if game code has hardcoded `http://127.0.0.1:3000`
   - Client not reading URL from UI/config properly

3. **Wrong endpoint construction:**
   - Client building URLs incorrectly
   - Missing or double slashes

**Solution:**

**In your client code:**
```dart
// BAD - Hardcoded localhost
final url = 'http://127.0.0.1:3000/auth';

// GOOD - Use base URL from config
final baseUrl = config.serverUrl; // from UI/config file
final url = '$baseUrl/auth'; // https://xxx.trycloudflare.com/auth
```

**Validation checklist:**
- [ ] Client reads server URL from config/UI (not hardcoded)
- [ ] Base URL is used for ALL requests (HTTP & WebSocket)
- [ ] No duplicate path segments
- [ ] Test connection button validates before gameplay

---

### ❌ Problem C: WebSocket won't connect but HTTP works

**Symptoms:**
- `curl https://xxx.trycloudflare.com/health` works ✓
- WebSocket connection fails or times out ✗

**Common causes:**

1. **Wrong protocol:**
   - Using `ws://` instead of `wss://`
   - Protocol mismatch with HTTPS tunnel

2. **Missing /ws path:**
   - Connecting to base URL instead of `/ws` endpoint
   - Wrong WebSocket path

3. **Server route not configured:**
   - Server doesn't have `/ws` route
   - WebSocket upgrade handler missing

**Solution:**

**Client must use `wss://` with HTTPS tunnel:**
```dart
// BAD - Wrong protocol with HTTPS tunnel
final wsUrl = 'ws://xxx.trycloudflare.com/ws';

// GOOD - Use wss:// with HTTPS
final wsUrl = 'wss://xxx.trycloudflare.com/ws';
```

**Important protocol rules:**
- Local server: `ws://localhost:3000/ws`
- Through Cloudflare tunnel: `wss://xxx.trycloudflare.com/ws`
- **Never** use `ws://` with `https://` URLs

**Server verification:**
```powershell
# Check if /ws route exists
curl.exe -i http://localhost:3000/ws
# Should return: HTTP/1.1 426 Upgrade Required (normal for WebSocket)

# Test WebSocket through tunnel
wscat -c wss://xxx.trycloudflare.com/ws
# Should connect and receive welcome message
```

**Note:** Cloudflare fully supports WebSocket proxying through tunnels (see [Cloudflare WebSockets docs](https://developers.cloudflare.com/cloudflare-one/connections/connect-apps/)).

---

## Testing Your Setup

### Test Health Check

```powershell
# Local test
curl http://localhost:3000/health

# Through tunnel (replace with your URL)
curl https://xxxx.trycloudflare.com/health
```

Both should return:
```json
{
  "status": "ok",
  "server": "areyoughost",
  "timestamp": "2026-02-16T12:00:00Z"
}
```

### Test WebSocket

Use a WebSocket client like [wscat](https://github.com/websockets/wscat):

```powershell
# Install wscat
npm install -g wscat

# Test local WebSocket
wscat -c ws://localhost:3000/ws

# Test through tunnel
wscat -c wss://xxxx.trycloudflare.com/ws
```

You should receive a welcome message: `"Welcome to Are You Ghost!"`

---

## Architecture Diagram

```
[Client Game .exe]
       |
       | HTTPS/WSS
       ↓
[Cloudflare Tunnel]
  (xxxx.trycloudflare.com)
       |
       | HTTP (port 3000)
       ↓
[Your Server: 0.0.0.0:3000]
       |
       ↓
[PostgreSQL Database]
```

---

## Tips

⚠️ **Quick Tunnel URL changes EVERY TIME** - Each time you run `cloudflared`, you get a new URL
- Host must update the URL in game settings each restart
- Friends need the new URL every time
- For persistent URLs, use [Named Tunnels](https://developers.cloudflare.com/cloudflare-one/connections/connect-apps/) instead

💡 **No authentication** - Anyone with the URL can connect. For production, add authentication

💡 **Port 3000** is conventional but can be changed - Update both server bind address and tunnel URL

💡 **Free tier limits** - Quick Tunnel is free but has usage limits. For heavy use, consider Cloudflare Teams

---

## Next Steps

- [ ] Implement game authentication on WebSocket connections
- [ ] Add rate limiting to prevent abuse
- [ ] Set up Named Tunnel for persistent URL
- [ ] Configure proper CORS for production
