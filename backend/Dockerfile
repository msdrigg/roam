FROM lukemathwalker/cargo-chef:latest-rust-1 AS chef
WORKDIR /app

FROM chef AS planner
COPY backend/. .
RUN cargo chef prepare --recipe-path recipe.json

FROM chef AS builder
COPY --from=planner /app/recipe.json recipe.json
# Build dependencies - this is the caching Docker layer!
RUN cargo chef cook --release --recipe-path recipe.json
# Build application
COPY backend/. .
RUN cargo build --release --bin roam-backend

# We do not need the Rust toolchain to run the binary!
FROM debian:bookworm-slim AS runtime
WORKDIR /app
RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl tar \
    && arch="$(dpkg --print-architecture)" \
    && case "$arch" in \
        amd64) ipsw_arch="x86_64" ;; \
        arm64) ipsw_arch="arm64" ;; \
        *) echo "Unsupported architecture for ipsw: $arch" >&2; exit 1 ;; \
    esac \
    && ipsw_version="$(curl -fsSL https://api.github.com/repos/blacktop/ipsw/releases/latest | sed -n 's/.*"tag_name": "v\([^"]*\)".*/\1/p' | head -n 1)" \
    && curl -fsSL "https://github.com/blacktop/ipsw/releases/latest/download/ipsw_${ipsw_version}_linux_${ipsw_arch}.tar.gz" -o /tmp/ipsw.tar.gz \
    && tar -xzf /tmp/ipsw.tar.gz -C /usr/local/bin ipsw \
    && chmod +x /usr/local/bin/ipsw \
    && rm -rf /var/lib/apt/lists/* /tmp/ipsw.tar.gz
COPY --from=builder /app/target/release/roam-backend /usr/local/bin
COPY docs/src/pages /app/docs/pages
ENV AI_RESPONDER_DOCS_DIR=/app/docs/pages
ENTRYPOINT ["/usr/local/bin/roam-backend"]
