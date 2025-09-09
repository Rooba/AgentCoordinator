# Agent Coordinator - Multi-stage Docker Build
# Creates a production-ready container for the MCP server without requiring local Elixir/OTP installation

# Build stage - Use official Elixir image with OTP
FROM elixir:1.18 AS builder


# Set environment variables
RUN apt-get update && apt-get install -y \
    git \
    curl \
    bash \
    unzip \
    zlib1g

# Set build environment
ENV MIX_ENV=prod

# Create app directory
WORKDIR /app

# Copy mix files
COPY lib lib
COPY mcp_servers.json \
    mix.exs \
    mix.lock \
    docker-entrypoint.sh ./
COPY scripts ./scripts/


# Install mix dependencies
RUN mix deps.get
RUN mix deps.compile
RUN mix compile
RUN mix release
RUN chmod +x ./docker-entrypoint.sh ./scripts/mcp_launcher.sh
RUN curl -fsSL https://bun.sh/install | bash
RUN ln -s /root/.bun/bin/* /usr/local/bin/

ENV NATS_HOST=localhost
ENV NATS_PORT=4222
ENV SHELL=/bin/bash

EXPOSE 4000

ENTRYPOINT ["/app/docker-entrypoint.sh"]

CMD ["/app/scripts/mcp_launcher.sh"]
