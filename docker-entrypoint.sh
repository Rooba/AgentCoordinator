#!/bin/bash

# Docker entrypoint script for Agent Coordinator MCP Server
# Handles initialization, configuration, and graceful shutdown

set -e

# Default environment variables
export MIX_ENV="${MIX_ENV:-prod}"
export NATS_HOST="${NATS_HOST:-localhost}"
export NATS_PORT="${NATS_PORT:-4222}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1" >&2
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1" >&2
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1" >&2
}

# Cleanup function for graceful shutdown
cleanup() {
    log_info "Received shutdown signal, cleaning up..."

    # Send termination signals to child processes
    if [ ! -z "$MAIN_PID" ]; then
        log_info "Stopping main process (PID: $MAIN_PID)..."
        kill -TERM "$MAIN_PID" 2>/dev/null || true
        wait "$MAIN_PID" 2>/dev/null || true
    fi

    log_success "Cleanup completed"
    exit 0
}

# Set up signal handlers for graceful shutdown
trap cleanup SIGTERM SIGINT SIGQUIT

# Function to wait for NATS (if configured)
wait_for_nats() {
    if [ "$NATS_HOST" != "localhost" ] || [ "$NATS_PORT" != "4222" ]; then
        log_info "Waiting for NATS at $NATS_HOST:$NATS_PORT..."

        local timeout=30
        local count=0

        while [ $count -lt $timeout ]; do
            if nc -z "$NATS_HOST" "$NATS_PORT" 2>/dev/null; then
                log_success "NATS is available"
                return 0
            fi

            log_info "NATS not yet available, waiting... ($((count + 1))/$timeout)"
            sleep 1
            count=$((count + 1))
        done

        log_error "Timeout waiting for NATS at $NATS_HOST:$NATS_PORT"
        exit 1
    else
        log_info "Using default NATS configuration (localhost:4222)"
    fi
}

# Validate configuration
validate_config() {
    log_info "Validating configuration..."

    # Check if mcp_servers.json exists
    if [ ! -f "/app/mcp_servers.json" ]; then
        log_error "mcp_servers.json not found"
        exit 1
    fi

    # Validate JSON
    if ! cat /app/mcp_servers.json | bun run -e "JSON.parse(require('fs').readFileSync(0, 'utf8'))" >/dev/null 2>&1; then
        log_error "Invalid JSON in mcp_servers.json"
        exit 1
    fi

    log_success "Configuration validation passed"
}

# Pre-install external MCP server dependencies
preinstall_dependencies() {
    log_info "Pre-installing external MCP server dependencies..."

    # Check if bun is available
    if ! command -v bun >/dev/null 2>&1; then
        log_error "bun is not available - external MCP servers may not work"
        return 1
    fi

    # Pre-cache common MCP packages to speed up startup
    local packages=(
        "@modelcontextprotocol/server-filesystem"
        "@modelcontextprotocol/server-memory"
        "@modelcontextprotocol/server-sequential-thinking"
        "@upstash/context7-mcp"
    )

    for package in "${packages[@]}"; do
        log_info "Caching package: $package"
        bun add --global --silent "$package" || log_warn "Failed to cache $package"
    done

    log_success "Dependencies pre-installed"
}

# Main execution
main() {
    log_info "Starting Agent Coordinator MCP Server"
    log_info "Environment: $MIX_ENV"
    log_info "NATS: $NATS_HOST:$NATS_PORT"

    # Validate configuration
    validate_config

    # Wait for external services if needed
    wait_for_nats

    # Pre-install dependencies
    preinstall_dependencies

    # Change to app directory
    cd /app

    # Start the main application
    log_info "Starting main application..."

    if [ "$#" -eq 0 ] || [ "$1" = "/app/scripts/mcp_launcher.sh" ]; then
        # Default: start the MCP server
        log_info "Starting MCP server via launcher script..."
        exec "/app/scripts/mcp_launcher.sh" &
        MAIN_PID=$!
    elif [ "$1" = "bash" ] || [ "$1" = "sh" ]; then
        # Interactive shell mode
        log_info "Starting interactive shell..."
        exec "$@"
    elif [ "$1" = "release" ]; then
        # Direct release mode
        log_info "Starting via Elixir release..."
        exec "/app/bin/agent_coordinator" "start" &
        MAIN_PID=$!
    else
        # Custom command
        log_info "Starting custom command: $*"
        exec "$@" &
        MAIN_PID=$!
    fi

    # Wait for the main process if it's running in background
    if [ ! -z "$MAIN_PID" ]; then
        log_success "Main process started (PID: $MAIN_PID)"
        wait "$MAIN_PID"
    fi
}

# Execute main function with all arguments
main "$@"
