# Agent Coordinator - Multi-stage Docker Build
# Creates a production-ready container for the MCP server without requiring local Elixir/OTP installation

# Build stage - Use official Elixir image with OTP
FROM elixir:1.16-otp-26-alpine AS builder

# Install build dependencies
RUN apk add --no-cache \
    build-base \
    git \
    curl \
    bash

# Install Node.js and npm for MCP external servers (bunx dependency)
RUN apk add --no-cache nodejs npm
RUN npm install -g bun

# Set build environment
ENV MIX_ENV=prod

# Create app directory
WORKDIR /app

# Copy mix files
COPY mix.exs mix.lock ./

# Install mix dependencies
RUN mix local.hex --force && \
    mix local.rebar --force && \
    mix deps.get --only $MIX_ENV && \
    mix deps.compile

# Copy source code
COPY lib lib
COPY config config

# Compile the release
RUN mix compile

# Prepare release
RUN mix release

# Runtime stage - Use smaller Alpine image
FROM alpine:3.18 AS runtime

# Install runtime dependencies
RUN apk add --no-cache \
    bash \
    openssl \
    ncurses-libs \
    libstdc++ \
    nodejs \
    npm

# Install Node.js packages for external MCP servers
RUN npm install -g bun

# Create non-root user for security
RUN addgroup -g 1000 appuser && \
    adduser -u 1000 -G appuser -s /bin/bash -D appuser

# Create app directory and set permissions
WORKDIR /app
RUN chown -R appuser:appuser /app

# Copy the release from builder stage
COPY --from=builder --chown=appuser:appuser /app/_build/prod/rel/agent_coordinator ./

# Copy configuration files
COPY --chown=appuser:appuser mcp_servers.json ./
COPY --chown=appuser:appuser scripts/mcp_launcher.sh ./scripts/

# Make scripts executable
RUN chmod +x ./scripts/mcp_launcher.sh

# Copy Docker entrypoint script
COPY --chown=appuser:appuser docker-entrypoint.sh ./
RUN chmod +x ./docker-entrypoint.sh

# Switch to non-root user
USER appuser

# Set environment variables
ENV MIX_ENV=prod
ENV NATS_HOST=localhost
ENV NATS_PORT=4222
ENV SHELL=/bin/bash

# Expose the default port (if needed for HTTP endpoints)
EXPOSE 4000

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD /app/bin/agent_coordinator ping || exit 1

# Set the entrypoint
ENTRYPOINT ["/app/docker-entrypoint.sh"]

# Default command
CMD ["/app/scripts/mcp_launcher.sh"]