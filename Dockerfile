# Recourse backend image (indexer + read API). Testnet only (R7).
# Build context is the repo root so the runtime can bundle deployments/arc-testnet.json,
# from which contract addresses are read at runtime (R3, never hardcoded).

# ---- Build stage ----
FROM rust:1-bookworm AS builder
WORKDIR /app/backend

# Pre-build dependencies against a stub main so this layer is cached across source edits
# (alloy is a large dependency tree; recompiling it every deploy is the slow part).
COPY backend/Cargo.toml backend/Cargo.lock ./
RUN mkdir src \
    && echo "fn main() {}" > src/main.rs \
    && cargo build --release \
    && rm -rf src

# Build the real binary. sqlx::migrate! embeds ./migrations into the binary at compile time.
COPY backend/migrations ./migrations
COPY backend/src ./src
RUN cargo build --release --locked

# ---- Runtime stage ----
FROM debian:bookworm-slim
RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY --from=builder /app/backend/target/release/recourse-backend /usr/local/bin/recourse-backend
# Contract addresses are read at runtime from the deployment file (R3).
COPY deployments ./deployments
ENV DEPLOYMENTS_PATH=/app/deployments/arc-testnet.json \
    EVIDENCE_DIR=/data/evidence-store \
    PORT=8080
EXPOSE 8080
CMD ["recourse-backend"]
