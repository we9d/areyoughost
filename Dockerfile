# --- STAGE 1: Chef Recipe Creation ---
FROM lukemathwalker/cargo-chef:latest-rust-1.77-slim-bookworm AS chef
WORKDIR /app

FROM chef AS planner
COPY . .
RUN cargo chef prepare --recipe-path recipe.json

# --- STAGE 2: Chef Builder ---
FROM chef AS builder
COPY --from=planner /app/recipe.json recipe.json
# Install build dependencies
RUN apt-get update && apt-get install -y \
    pkg-config \
    libssl-dev \
    && rm -rf /var/lib/apt/lists/*

# Build dependencies - this is the caching layer
RUN cargo chef cook --release --recipe-path recipe.json

# Build application
COPY . .
RUN cargo build --release -p areyoughost_server

# --- STAGE 3: Runtime ---
FROM debian:bookworm-slim AS runtime
WORKDIR /app

# Install runtime dependencies
RUN apt-get update && apt-get install -y \
    ca-certificates \
    libssl3 \
    && rm -rf /var/lib/apt/lists/*

# Copy the binary from the builder
COPY --from=builder /app/target/release/server /app/server

# Expose ports
# 3000 - HTTP Management
# 8888 - Binary TCP
# 8889 - Binary UDP
EXPOSE 3000 8888 8889/udp

# Set environment defaults (can be overridden by compose)
ENV RUST_LOG=info

# Run the server
CMD ["/app/server"]
