# Recourse backend image (indexer + read API). Testnet only (R7).
# Build context is the repo root so the runtime can bundle deployments/arc-testnet.json,
# from which contract addresses are read at runtime (R3, never hardcoded).
#
# railway.json names only the builder, not this path: it is shared by every service in
# the repo, so a dockerfilePath there would build the same image for all of them. Each
# service names its own through the RAILWAY_DOCKERFILE_PATH variable instead.

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
# Cargo decides freshness by mtime. The sources arrive with the timestamps they were
# last edited at, which can be older than the dummy build a few seconds above, and then
# cargo keeps the dummy binary: an empty main that exits at once, prints nothing, and
# fails every healthcheck with no log to explain why. Touching them forces the rebuild.
RUN find src -type f -exec touch {} + && cargo build --release --locked

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
    ORDERS_DIR=/data/order-store \
    PORT=8080
EXPOSE 8080
CMD ["recourse-backend"]
