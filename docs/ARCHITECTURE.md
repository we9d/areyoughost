# Architecture Overview

## System Architecture

**Are You Ghost** is a multiplayer social deduction game built with a strict **Zero-Trust Client Isolation** model and a **Dual-Port Server Architecture**, specifically designed to demonstrate low-level networking concepts over TCP.

## High-Level Architecture

```mermaid
graph TB
    subgraph "Client Side (Zero-Trust)"
        Flutter[Flutter Desktop App]
        FFI[FFI Bridge]
        LocalCore[Core Library - Local]
    end
    
    subgraph "Server Side (Authoritative)"
        TCP[Tokio TCP Server :8080]
        HTTP[Axum HTTP Server :3000]
        ServerCore[Core Library - Server]
        DB[(PostgreSQL Database :5433)]
    end
    
    Flutter -->|Native Calls| FFI
    FFI -->|Rust FFI| LocalCore
    Flutter -->|Raw TCP Socket| TCP
    TCP --> ServerCore
    HTTP --> ServerCore
    ServerCore -->|sqlx| DB
    
    style Flutter fill:#4FC3F7,color:#000
    style TCP fill:#E53935,color:#fff
    style DB fill:#FFA726,color:#000
```

## Data Flow (Binary Protocol)
Instead of traditional HTTP/REST, the game state is synchronized using the **Areyoughost Binary Protocol** over raw TCP.

```mermaid
sequenceDiagram
    participant Client as Flutter (dart:io)
    participant Server as Rust (tokio::net)
    participant Core as Game Engine (Arc)
    participant DB as PostgreSQL
    
    Client->>Server: Connect to Port 8080
    Server-->>Client: TCP Handshake Completed
    
    Note over Client,Server: Custom Binary Framing: [Magic][Type][Len][Payload][CRC]
    
    Client->>Server: Send [0x01 LOGIN_REQUEST] frame
    Server->>DB: Validate Credentials
    DB-->>Server: User Data
    Server-->>Client: Send [0x02 LOGIN_RESPONSE] frame
    
    Client->>Server: Send [0x31 CAST_VOTE] frame
    Server->>Core: Update Game State Machine
    Core->>DB: Persist Action
    Core-->>Server: Generate Broadcast
    Server-->>Client: Send [0x32 GAME_STATE_UPDATE] frame
```

## Technology Decision Rationale

### Why Custom TCP instead of WebSockets?
To fulfill the requirements of the **Data Communications and Network** course, we bypassed Layer 7 frameworks (HTTP/WS) to manually handle Layer 4-6 operations. This includes binary serialization, framing (solving sticky packets via Length headers), and data integrity verification (CRC16).

### Why Arc-based State Management?
The game engine uses `Arc<RwLock<GameState>>` to allow multiple Tokio threads (representing up to 16 concurrent TCP player connections) to read and modify the game state safely without memory corruption or race conditions.

### Why Zero-Trust Client?
The Flutter frontend contains **no database credentials**. It only knows how to serialize user actions into binary frames and send them to Port 8080. The Rust server acts as the absolute authority, protecting against client-manipulation and ensuring database security.
