#!/bin/bash

# AgentCoordinator Unified MCP Server Launcher
# This script starts the unified MCP server that manages all external MCP servers
# and provides automatic task tracking with heartbeat coverage

set -e

export PATH="$HOME/.asdf/shims:$PATH"

# Change to the project directory
cd "$(dirname "$0")/.."

# Set environment
export MIX_ENV="${MIX_ENV:-dev}"
export NATS_HOST="${NATS_HOST:-localhost}"
export NATS_PORT="${NATS_PORT:-4222}"

# Log startup
echo "Starting AgentCoordinator Unified MCP Server..." >&2
echo "Environment: $MIX_ENV" >&2
echo "NATS: $NATS_HOST:$NATS_PORT" >&2

# Start the Elixir application with unified MCP server
exec mix run --no-halt -e "
# Ensure all applications are started
{:ok, _} = Application.ensure_all_started(:agent_coordinator)

# MCPServerManager is now started by the application supervisor automatically

case AgentCoordinator.MCPServer.start_link() do
  {:ok, _} -> :ok
  {:error, {:already_started, _}} -> :ok
  {:error, reason} -> raise \"Failed to start MCPServer: #{inspect(reason)}\"
end

# Log that we're ready
IO.puts(:stderr, \"Unified MCP server ready with automatic task tracking\")

# STDIO handling is now managed by InterfaceManager, not here
# Just keep the process alive
Process.sleep(:infinity)
"
