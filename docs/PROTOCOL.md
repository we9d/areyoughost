Overview
This document defines the Areyoughost Protocol, a proprietary binary network protocol designed specifically for the "Are You Ghost?" multiplayer game. Operating over raw TCP sockets (Port 8080), it bypasses heavy HTTP/WebSocket overhead to fulfill the strict low-level implementation requirements of the Data Communications and Network course.

Protocol Stack (OSI Mapping)
Plaintext
┌─────────────────────────────────────┐
│  Layer 7: Application Layer         │
│  - Areyoughost Commands (Type 0x01+)│
│  - Game State & Action Payloads     │
└─────────────────────────────────────┘
┌─────────────────────────────────────┐
│  Layer 6: Presentation Layer        │
│  - Binary Serialization             │
│  - Custom Byte Framing              │
└─────────────────────────────────────┘
┌─────────────────────────────────────┐
│  Layer 5: Session Layer             │
│  - Virtual Client Isolation         │
│  - Reconnection Handling            │
└─────────────────────────────────────┘
┌─────────────────────────────────────┐
│  Layer 4: Transport Layer           │
│  - Raw TCP Sockets (Port 8080)      │
│  - OS-level Sequence & Reliability  │
└─────────────────────────────────────┘
Packet Format
The protocol uses a strict custom binary frame. Every transmission consists of a 7-byte header, a variable-length payload, and a 2-byte trailer for integrity verification.

Frame Structure
Plaintext
 0                   1                   2                   3
 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|       Magic Bytes (0xAE 0x80)         |     Type (1 Byte)     |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|                     Payload Length (4 Bytes)                  |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|                                                               |
+                                                               +
|                     Message Payload (Variable)                |
+                                                               +
|                                                               |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|                 CRC16-IBM-SDLC Trailer (2 Bytes)              |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
Fields Definition:

Magic Bytes (2 bytes): 0xAE 0x80. Used to identify valid Areyoughost packets and prevent processing of arbitrary socket connections (e.g., port scanners).

Type (1 byte): The command identifier. Determines how the payload should be deserialized and processed.

Payload Length (4 bytes): Unsigned 32-bit integer (Big-Endian) representing the exact size of the payload. Essential for solving the TCP sticky-packet problem.

Payload (N bytes): The actual serialized data (JSON or Bincode) corresponding to the message Type.

CRC16 Trailer (2 bytes): Cyclic Redundancy Check (CCITT) calculated over the Header + Payload. Ensures Layer 7 data integrity beyond TCP's standard checksum.

Message Types (Type Byte)
Authentication & Meta (0x01-0x0F)
0x01 LOGIN_REQUEST: Client authenticates with the server.

0x0F GET_GAME_DATA: Requests synchronized metadata (e.g., all 16 roles and generic skills) from the server.

Room Management (0x10-0x2F)
0x10 JOIN_ROOM_REQUEST: Player attempts to join a specific lobby.

0x11 ROOM_STATE_UPDATE: Broadcasted to all lobby members when a player joins/leaves.

Game Actions (0x30-0x4F)
0x30 CHAT_MESSAGE: In-game discussion message.

0x31 CAST_VOTE: Player submits a vote during the Day phase.

0x32 NIGHT_ACTION: Prioritized skill execution (Protection → Information → Action).

0x33 GAME_PHASE_CHANGE: Server dictates a transition (e.g., Day to Night).

System & Control (0x50-0xFF)
0x50 HEARTBEAT: Keep-alive ping to prevent socket timeout.

0x52 ERROR: Server responds with failure details (e.g., Invalid CRC, Unauthorized).

Connection & Synchronization Flow
This illustrates the zero-trust client isolation model. The Flutter client never talks to PostgreSQL directly.

Plaintext
Flutter Client (Dart)               Rust Server (Port 8080)              Supabase (Port 5433)
       |                                      |                                   |
       |--- [AE 80][0x0F][Len][...][CRC] ---->|                                   |
       |       (GetGameData Request)          |                                   |
       |                                      |--- SQL: SELECT * FROM roles ----->|
       |                                      |<-- Return 16 Official Roles ------|
       |<-- [AE 80][0x0F][Len][...][CRC] -----|                                   |
       |       (Binary Encoded Roles)         |                                   |
       |                                      |                                   |
Implementation Notes
Byte Order: All multi-byte integers (Length, CRC) MUST be transmitted in Network Byte Order (Big-Endian).

TCP Fragmentation: The server's TcpListener must buffer incoming streams until the accumulated bytes equal 9 + Payload Length.

Port Allocations:

Areyoughost Binary Protocol: TCP 8080

HTTP/Management API (if applicable): TCP 3000

PostgreSQL Database: TCP 5433 (Local Docker)

PgAdmin: TCP 5050