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

# Handle MCP JSON-RPC messages through the unified server
defmodule UnifiedMCPStdio do
  def start do
    spawn_link(fn -> message_loop() end)
    Process.sleep(:infinity)
  end

  defp message_loop do
    case IO.read(:stdio, :line) do
      :eof ->
        IO.puts(:stderr, \"Unified MCP server shutting down\")
        System.halt(0)
      {:error, reason} ->
        IO.puts(:stderr, \"IO Error: #{inspect(reason)}\")
        System.halt(1)
      line ->
        handle_message(String.trim(line))
        message_loop()
    end
  end

  defp handle_message(\"\"), do: :ok
  defp handle_message(json_line) do
    try do
      request = Jason.decode!(json_line)

      # Route through unified MCP server for automatic task tracking
      response = AgentCoordinator.MCPServer.handle_mcp_request(request)
      IO.puts(Jason.encode!(response))
    rescue
      e in Jason.DecodeError ->
        error_response = %{
          \"jsonrpc\" => \"2.0\",
          \"id\" => nil,
          \"error\" => %{
            \"code\" => -32700,
            \"message\" => \"Parse error: #{Exception.message(e)}\"
          }
        }
        IO.puts(Jason.encode!(error_response))
      e ->
        # Try to get the ID from the malformed request
        id = try do
          partial = Jason.decode!(json_line)
          Map.get(partial, \"id\")
        rescue
          _ -> nil
        end

        error_response = %{
          \"jsonrpc\" => \"2.0\",
          \"id\" => id,
          \"error\" => %{
            \"code\" => -32603,
            \"message\" => \"Internal error: #{Exception.message(e)}\"
          }
        }
        IO.puts(Jason.encode!(error_response))
    end
  end
end

UnifiedMCPStdio.start()
"