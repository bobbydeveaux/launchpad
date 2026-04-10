# StackRamp default Rust Dockerfile
# Multi-stage build for production-ready Rust apps

FROM rust:1.77-bookworm AS builder

WORKDIR /app

# Cache dependency build: copy manifests first, build deps, then copy source
COPY Cargo.toml Cargo.lock* ./
RUN mkdir src && echo "fn main() {}" > src/main.rs && cargo build --release && rm -rf src

COPY . .

# Touch main.rs so cargo rebuilds the actual binary (not the dummy)
RUN touch src/main.rs && cargo build --release

# Parse binary name from Cargo.toml [package] name field
RUN BINARY_NAME=$(grep -m1 '^name' Cargo.toml | sed 's/.*= *"//;s/".*//') && \
    cp "/app/target/release/${BINARY_NAME}" /app/server

# Stage 2: Runtime
FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y ca-certificates && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY --from=builder /app/server .

ENV PORT=8080
EXPOSE ${PORT}

CMD ["/app/server"]
