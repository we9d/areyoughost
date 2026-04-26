# Remote Demo via Tunnel (No VPS)

This guide is for running the game across different networks (different homes) **without renting a server**.

Current recommended workflow:

1. Keep local development stable first (`localhost` flow).
2. Use this document later when you need remote demo.

---

## 1) Goal

Run the backend on your own machine and expose it via a tunnel URL, so friends can connect remotely.

- Your machine = temporary host
- No VPS needed
- No router port-forward needed

---

## 2) Preconditions

- Backend runs successfully on your machine:
  - `cargo run -p areyoughost_server`
  - logs show server listening on port `3000`
- Database connectivity is healthy (Supabase reachable)
- Windows firewall allows the local process to run

---

## 3) Quick Option: ngrok

### 3.1 Install and authenticate

Install ngrok, then configure token once:

```powershell
ngrok config add-authtoken <YOUR_NGROK_AUTHTOKEN>
```

### 3.2 Start backend (terminal A)

```powershell
cargo run -p areyoughost_server
```

### 3.3 Start tunnel (terminal B)

```powershell
ngrok http 3000
```

You will get a public URL like:

- `https://abc123.ngrok-free.app`

---

## 4) URL Mapping Rules

If your tunnel URL is `https://abc123.ngrok-free.app`, use:

- HTTP API base: `https://abc123.ngrok-free.app`
- WebSocket URL: `wss://abc123.ngrok-free.app/ws`

Important:

- `https` must pair with `wss`
- Do not keep `localhost` in remote demo clients

---

## 5) How teammates connect

Each remote player needs:

1. Client build (`.exe`)
2. The current tunnel URL
3. Server host machine must stay online

If host closes backend/ngrok, all clients disconnect.

---

## 6) Recommended app-side improvement (later)

To avoid editing source code every time, add configurable endpoints:

- `API_BASE_URL`
- `WS_BASE_URL` or derive from API URL

Example launch-time config (future):

```powershell
flutter run -d windows --dart-define=API_BASE_URL=https://abc123.ngrok-free.app --dart-define=WS_URL=wss://abc123.ngrok-free.app/ws
```

---

## 7) Demo Checklist

- [ ] Backend starts and connects DB
- [ ] `/health` reachable from local machine
- [ ] ngrok tunnel URL is online
- [ ] Client can login/register through tunnel URL
- [ ] Host creates room successfully
- [ ] Invite code join works from another network
- [ ] Reconnect behavior is acceptable after short network interruption

---

## 8) Known limitations (no-VPS mode)

- Host uptime controls session uptime
- Tunnel free plans may rotate URLs
- Latency depends on host network quality
- Not production-grade reliability

---

## 9) Production note

For real production, use a dedicated always-on server (VPS/cloud), fixed domain, monitoring, and secure secret management.

