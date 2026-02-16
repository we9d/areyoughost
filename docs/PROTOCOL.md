# Custom Protocol Specification - Are You Ghost?

## Overview

This document defines the custom network protocol for the "Are You Ghost?" multiplayer game. The protocol is designed to work over TCP/UDP sockets with bandwidth control and OSI layer monitoring.

## Protocol Stack

```
┌─────────────────────────────────────┐
│  Layer 7: Application Layer         │
│  - Game Messages                    │
│  - Command/Response Pattern         │
└─────────────────────────────────────┘
┌─────────────────────────────────────┐
│  Layer 6: Presentation Layer        │
│  - Binary Serialization             │
│  - Optional Compression             │
└─────────────────────────────────────┘
┌─────────────────────────────────────┐
│  Layer 5: Session Layer             │
│  - Connection State                 │
│  - Session Management               │
└─────────────────────────────────────┘
┌─────────────────────────────────────┐
│  Layer 4: Transport Layer           │
│  - TCP (Reliable) / UDP (Fast)      │
│  - Bandwidth Throttling             │
└─────────────────────────────────────┘
```

## Packet Format

### Transport Header (Layer 4)

```
 0                   1                   2                   3
 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|    Version    |     Flags     |          Packet Length        |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|                        Sequence Number                        |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|                      Acknowledgment Number                    |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|          Checksum             |           Reserved            |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
```

**Fields:**
- **Version** (1 byte): Protocol version (current: 0x01)
- **Flags** (1 byte): Control flags
  - Bit 0: SYN (Synchronize)
  - Bit 1: ACK (Acknowledgment)
  - Bit 2: FIN (Finish)
  - Bit 3: RST (Reset)
  - Bit 4: COMPRESSED
  - Bits 5-7: Reserved
- **Packet Length** (2 bytes): Total packet size including headers
- **Sequence Number** (4 bytes): Packet sequence for ordering
- **Acknowledgment Number** (4 bytes): Last received sequence
- **Checksum** (2 bytes): CRC16 checksum
- **Reserved** (2 bytes): For future use

### Session Header (Layer 5)

```
 0                   1                   2                   3
 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|                                                               |
+                         Session ID (16 bytes)                 +
|                                                               |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|                          Timestamp                            |
|                          (8 bytes)                            |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
```

**Fields:**
- **Session ID** (16 bytes): UUID v4 for session identification
- **Timestamp** (8 bytes): Unix timestamp in milliseconds

### Presentation Header (Layer 6)

```
 0                   1                   2                   3
 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|  Encoding     | Compression   |       Payload Length          |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
```

**Fields:**
- **Encoding** (1 byte): Serialization format
  - 0x01: Binary (Custom)
  - 0x02: JSON (Debug only)
- **Compression** (1 byte): Compression algorithm
  - 0x00: None
  - 0x01: LZ4
  - 0x02: Zstd
- **Payload Length** (2 bytes): Uncompressed payload size

### Application Payload (Layer 7)

```
 0                   1                   2                   3
 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|  Message Type |                  Reserved                     |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|                                                               |
+                      Message Payload (Variable)               +
|                                                               |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
```

## Message Types

### Authentication Messages (0x01-0x0F)

#### 0x01: LOGIN_REQUEST
```json
{
  "username": "string",
  "password_hash": "string"
}
```

#### 0x02: LOGIN_RESPONSE
```json
{
  "success": bool,
  "user_id": "string",
  "session_token": "string",
  "error": "string?"
}
```

#### 0x03: REGISTER_REQUEST
```json
{
  "username": "string",
  "password_hash": "string"
}
```

#### 0x04: REGISTER_RESPONSE
```json
{
  "success": bool,
  "user_id": "string",
  "error": "string?"
}
```

### Room Messages (0x10-0x2F)

#### 0x10: ROOM_LIST_REQUEST
```json
{}
```

#### 0x11: ROOM_LIST_RESPONSE
```json
{
  "rooms": [
    {
      "room_id": "string",
      "name": "string",
      "players": number,
      "max_players": number,
      "status": "waiting|playing|finished"
    }
  ]
}
```

#### 0x12: CREATE_ROOM_REQUEST
```json
{
  "name": "string",
  "max_players": number,
  "is_public": bool
}
```

#### 0x13: CREATE_ROOM_RESPONSE
```json
{
  "success": bool,
  "room_id": "string",
  "error": "string?"
}
```

#### 0x14: JOIN_ROOM_REQUEST
```json
{
  "room_id": "string"
}
```

#### 0x15: JOIN_ROOM_RESPONSE
```json
{
  "success": bool,
  "game_state": "GameState",
  "error": "string?"
}
```

### Game Messages (0x30-0x4F)

#### 0x30: CHAT_MESSAGE
```json
{
  "sender_id": "string",
  "sender_name": "string",
  "message": "string",
  "timestamp": number
}
```

#### 0x31: CAST_VOTE
```json
{
  "voter_id": "string",
  "target_id": "string"
}
```

#### 0x32: GAME_STATE_UPDATE
```json
{
  "phase": "day|night|vote",
  "participants": [...],
  "timer": number
}
```

#### 0x33: PLAYER_ELIMINATED
```json
{
  "player_id": "string",
  "player_name": "string",
  "role": "string"
}
```

#### 0x34: GAME_END
```json
{
  "winner_team": "villager|ghost",
  "survivors": [...]
}
```

### Control Messages (0x50-0xFF)

#### 0x50: HEARTBEAT
```json
{
  "timestamp": number
}
```

#### 0x51: DISCONNECT
```json
{
  "reason": "string"
}
```

#### 0x52: ERROR
```json
{
  "code": number,
  "message": "string"
}
```

## Connection Flow

### Initial Handshake

```
Client                                Server
  |                                      |
  |--- SYN (Seq=X) ------------------->  |
  |                                      |
  |<-- SYN-ACK (Seq=Y, Ack=X+1) --------|
  |                                      |
  |--- ACK (Seq=X+1, Ack=Y+1) -------->  |
  |                                      |
  |--- LOGIN_REQUEST ------------------>  |
  |                                      |
  |<-- LOGIN_RESPONSE ------------------|
  |                                      |
```

### Game Session

```
Client                                Server
  |                                      |
  |--- JOIN_ROOM_REQUEST -------------->  |
  |                                      |
  |<-- JOIN_ROOM_RESPONSE --------------|
  |                                      |
  |<-- GAME_STATE_UPDATE ---------------|
  |                                      |
  |--- CHAT_MESSAGE ------------------->  |
  |                                      |
  |<-- CHAT_MESSAGE (broadcast) --------|
  |                                      |
  |--- CAST_VOTE ---------------------->  |
  |                                      |
  |<-- GAME_STATE_UPDATE ---------------|
  |                                      |
```

### Graceful Disconnect

```
Client                                Server
  |                                      |
  |--- DISCONNECT --------------------->  |
  |                                      |
  |<-- ACK -----------------------------|
  |                                      |
  |--- FIN (Seq=X) -------------------->  |
  |                                      |
  |<-- FIN-ACK (Seq=Y, Ack=X+1) --------|
  |                                      |
  |--- ACK (Seq=X+1, Ack=Y+1) -------->  |
  |                                      |
```

## Bandwidth Control

### QoS Priority Levels

1. **Critical** (Highest): Authentication, game state updates
2. **High**: Player actions, votes
3. **Medium**: Chat messages
4. **Low**: Statistics, heartbeats

### Rate Limiting

- Default: 1 MB/s per connection
- Configurable via API
- Token bucket algorithm
- Per-message-type throttling

## Error Codes

| Code | Name | Description |
|------|------|-------------|
| 1000 | INVALID_PACKET | Malformed packet structure |
| 1001 | CHECKSUM_FAILED | Packet checksum mismatch |
| 1002 | UNSUPPORTED_VERSION | Protocol version not supported |
| 2000 | AUTH_FAILED | Authentication failed |
| 2001 | SESSION_EXPIRED | Session token expired |
| 3000 | ROOM_FULL | Room at maximum capacity |
| 3001 | ROOM_NOT_FOUND | Room ID does not exist |
| 4000 | INVALID_ACTION | Action not allowed in current state |
| 5000 | RATE_LIMITED | Too many requests |

## Security Considerations

1. **Password Hashing**: Use bcrypt/argon2 before transmission
2. **Session Tokens**: UUID v4 with expiration
3. **Checksum**: CRC16 for packet integrity
4. **Rate Limiting**: Prevent DoS attacks
5. **Input Validation**: Sanitize all user inputs

## Implementation Notes

- All multi-byte integers are in **network byte order** (big-endian)
- Timestamps are **Unix milliseconds** (UTC)
- String encoding is **UTF-8**
- Maximum packet size: **65535 bytes**
- Heartbeat interval: **30 seconds**
- Session timeout: **5 minutes** of inactivity
