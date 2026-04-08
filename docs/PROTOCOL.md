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
The protocol uses a strict custom binary frame. Every transmission consists of an 8-byte header, a variable-length payload, and a 2-byte trailer for integrity verification.

Frame Structure
Plaintext
 0                   1                   2                   3
 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|       Magic Bytes (0xAE 0x80)         |  Version (1)  | Type  |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|                     Payload Length (4 Bytes)                  |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|                                                               |
+                                                               +
|                     Message Payload (Variable JSON)           |
+                                                               +
|                                                               |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|                 CRC16-IBM-SDLC Trailer (2 Bytes)              |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
Fields Definition:

Magic Bytes (2 bytes): 0xAE 0x80. Used to identify valid Areyoughost packets.

Version (1 byte): Protocol version (currently 1).

Type (1 byte): The command identifier (Opcode).

Payload Length (4 bytes): Unsigned 32-bit integer (Big-Endian) representing the exact size of the payload.

Payload (N bytes): The actual serialized data (**JSON**) corresponding to the message Type.

CRC16 Trailer (2 bytes): Calculated over Header (excluding magic) + Payload. [Version][Type][Length][Payload].

Message Types (Type Byte)
Authentication & Meta (0x01-0x0F)
0x01 LOGIN_REQUEST: Client authenticates with username/password JSON.
0x02 LOGIN_RESPONSE: Server returns session_id and player_id.
0x0F GET_GAME_DATA: Requests synchronized metadata.

Room Management (0x10-0x2F)
0x10 ROOM_LIST_REQUEST: Request available rooms.
0x11 ROOM_LIST_RESPONSE: Server returns list of rooms.
0x12 CREATE_ROOM_REQUEST: Request to create a room.
0x14 JOIN_ROOM_REQUEST: Player attempts to join a specific lobby.
0x15 JOIN_ROOM_RESPONSE: Confirmation of entry or role assignment.
0x17 QUICK_JOIN_REQUEST: Automated matchmaking (requires player_id).
0x18 QUICK_JOIN_RESPONSE: Returns joined room_id and lobby status.
0x19 START_GAME: Host signals game start.
0x20 ROOM_STATE_SYNC: Broadcasted to all lobby members (participants list).

Game Actions (0x30-0x4F)
0x30 CHAT_MESSAGE: In-game discussion message.
0x31 CAST_VOTE: Player submits a vote during the Day phase.
0x32 NIGHT_ACTION: Prioritized skill execution (Protection → Information → Action).
0x33 GAME_PHASE_CHANGE: Server dictates a transition (e.g., Day to Night).
0x34 GAME_EVENT: Broadcasted event (Elimination, Win, etc.).

System & Control (0x50-0xFF)
0x50 HEARTBEAT: Keep-alive ping to prevent socket timeout.
0x70 DISCONNECT: Signals intention to close connection.
0xFF ERROR: Server responds with failure details.

Connection & Synchronization Flow
This illustrates the zero-trust client isolation model. The Flutter client never talks to PostgreSQL directly.

Flutter Client (Dart)               Rust Server (Port 8080)              Supabase (Port 5433)
       |                                      |                                   |
       |--- [AE 80][...][0x0F][Len][...][CRC] ->|                                   |
       |       (GetGameData Request)          |                                   |
       |                                      |--- SQL: SELECT * FROM roles ----->|
       |                                      |<-- Return 16 Official Roles ------|
       |<-- [AE 80][...][0x0F][Len][...][CRC] --|                                   |
       |       (JSON Encoded Roles)           |                                   |
       |                                      |                                   |

Implementation Notes
Byte Order: All multi-byte integers (Length, CRC) MUST be transmitted in Network Byte Order (Big-Endian).

TCP Fragmentation: The server's TcpListener must buffer incoming streams until the accumulated bytes equal 10 + Payload Length. (8 Header bytes + 2 CRC bytes).

Port Allocations:
Areyoughost Binary Protocol: TCP 8080
HTTP/Management API (if applicable): TCP 3000
PostgreSQL Database: TCP 5433 (Local Docker)
PgAdmin: TCP 5050