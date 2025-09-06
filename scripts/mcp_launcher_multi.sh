#!/bin/bash

# AgentCoordinator Multi-Interface MCP Server Launcher
# This script starts the unified MCP server with support for multiple interface modes:
# - stdio: Traditional MCP over stdio (default for VSCode)
# - http: HTTP REST API for remote clients
# - websocket: WebSocket interface for real-time web clients
# - remote: Both HTTP and WebSocket
# - all: All interface modes

set -e

export PATH="$HOME/.asdf/shims:$PATH"

# Change to the project directory
cd "$(dirname "$0")/.."

# Parse command line arguments
INTERFACE_MODE="${1:-stdio}"
HTTP_PORT="${2:-8080}"
WS_PORT="${3:-8081}"

# Set environment variables
export MIX_ENV="${MIX_ENV:-dev}"
export NATS_HOST="${NATS_HOST:-localhost}"
export NATS_PORT="${NATS_PORT:-4222}"
export MCP_INTERFACE_MODE="$INTERFACE_MODE"
export MCP_HTTP_PORT="$HTTP_PORT"
export MCP_WS_PORT="$WS_PORT"

# Validate interface mode
case "$INTERFACE_MODE" in
    stdio|http|websocket|remote|all)
        ;;
    *)
        echo "Invalid interface mode: $INTERFACE_MODE"
        echo "Valid modes: stdio, http, websocket, remote, all"
        exit 1
        ;;
esac

# Log startup
echo "Starting AgentCoordinator Multi-Interface MCP Server..." >&2
echo "Interface Mode: $INTERFACE_MODE" >&2
echo "Environment: $MIX_ENV" >&2
echo "NATS: $NATS_HOST:$NATS_PORT" >&2

if [[ "$INTERFACE_MODE" != "stdio" ]]; then
    echo "HTTP Port: $HTTP_PORT" >&2
    echo "WebSocket Port: $WS_PORT" >&2
fi

# Install dependencies if needed
if [[ ! -d "deps" ]] || [[ ! -d "_build" ]]; then
    echo "Installing dependencies..." >&2
    mix deps.get
    mix compile
fi

# Start the appropriate interface mode
case "$INTERFACE_MODE" in
    stdio)
        # Traditional stdio mode for VSCode and local clients
        exec mix run --no-halt -e "
# Ensure all applications are started
{:ok, _} = Application.ensure_all_started(:agent_coordinator)

# Configure interface manager for stdio only
Application.put_env(:agent_coordinator, :interfaces, %{
  enabled_interfaces: [:stdio],
  stdio: %{enabled: true, handle_stdio: true},
  http: %{enabled: false},
  websocket: %{enabled: false}
})

# MCPServer and InterfaceManager are started by the application supervisor automatically
IO.puts(:stderr, \"STDIO MCP server ready with tool filtering\")

# Handle MCP JSON-RPC messages through the unified server
defmodule StdioMCPHandler do
  def start do
    spawn_link(fn -> message_loop() end)
    Process.sleep(:infinity)
  end

  defp message_loop do
    case IO.read(:stdio, :line) do
      :eof ->
        IO.puts(:stderr, \"MCP server shutting down\")
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
      # Route through unified MCP server with local context (full tool access)
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

StdioMCPHandler.start()
"
        ;;
        
    http)
        # HTTP-only mode for REST API clients
        exec mix run --no-halt -e "
# Ensure all applications are started
{:ok, _} = Application.ensure_all_started(:agent_coordinator)

# Configure interface manager for HTTP only
Application.put_env(:agent_coordinator, :interfaces, %{
  enabled_interfaces: [:http],
  stdio: %{enabled: false},
  http: %{enabled: true, port: $HTTP_PORT, host: \"0.0.0.0\"},
  websocket: %{enabled: false}
})

IO.puts(:stderr, \"HTTP MCP server ready on port $HTTP_PORT with tool filtering\")
IO.puts(:stderr, \"Available endpoints:\")
IO.puts(:stderr, \"  GET  /health - Health check\")
IO.puts(:stderr, \"  GET  /mcp/capabilities - Server capabilities\")
IO.puts(:stderr, \"  GET  /mcp/tools - Available tools (filtered)\")
IO.puts(:stderr, \"  POST /mcp/tools/:tool_name - Execute tool\")
IO.puts(:stderr, \"  POST /mcp/request - Full MCP request\")
IO.puts(:stderr, \"  GET  /agents - Agent status\")

Process.sleep(:infinity)
"
        ;;
        
    websocket)
        # WebSocket-only mode
        exec mix run --no-halt -e "
# Ensure all applications are started
{:ok, _} = Application.ensure_all_started(:agent_coordinator)

# Configure interface manager for WebSocket only  
Application.put_env(:agent_coordinator, :interfaces, %{
  enabled_interfaces: [:websocket],
  stdio: %{enabled: false},
  http: %{enabled: true, port: $WS_PORT, host: \"0.0.0.0\"},
  websocket: %{enabled: true, port: $WS_PORT}
})

IO.puts(:stderr, \"WebSocket MCP server ready on port $WS_PORT with tool filtering\")
IO.puts(:stderr, \"WebSocket endpoint: ws://localhost:$WS_PORT/mcp/ws\")

Process.sleep(:infinity)
"
        ;;
        
    remote)
        # Both HTTP and WebSocket for remote clients
        exec mix run --no-halt -e "
# Ensure all applications are started
{:ok, _} = Application.ensure_all_started(:agent_coordinator)

# Configure interface manager for remote access
Application.put_env(:agent_coordinator, :interfaces, %{
  enabled_interfaces: [:http, :websocket],
  stdio: %{enabled: false},
  http: %{enabled: true, port: $HTTP_PORT, host: \"0.0.0.0\"},
  websocket: %{enabled: true, port: $HTTP_PORT}
})

IO.puts(:stderr, \"Remote MCP server ready on port $HTTP_PORT with tool filtering\")
IO.puts(:stderr, \"HTTP endpoints available at http://localhost:$HTTP_PORT/\")
IO.puts(:stderr, \"WebSocket endpoint: ws://localhost:$HTTP_PORT/mcp/ws\")

Process.sleep(:infinity)
"
        ;;
        
    all)
        # All interface modes
        exec mix run --no-halt -e "
# Ensure all applications are started
{:ok, _} = Application.ensure_all_started(:agent_coordinator)

# Configure interface manager for all interfaces
Application.put_env(:agent_coordinator, :interfaces, %{
  enabled_interfaces: [:stdio, :http, :websocket],
  stdio: %{enabled: true, handle_stdio: false},  # Don't handle stdio in all mode
  http: %{enabled: true, port: $HTTP_PORT, host: \"0.0.0.0\"},
  websocket: %{enabled: true, port: $HTTP_PORT}
})

IO.puts(:stderr, \"Multi-interface MCP server ready with tool filtering\")
IO.puts(:stderr, \"STDIO: Available for local MCP clients\")
IO.puts(:stderr, \"HTTP: Available at http://localhost:$HTTP_PORT/\")
IO.puts(:stderr, \"WebSocket: Available at ws://localhost:$HTTP_PORT/mcp/ws\")

Process.sleep(:infinity)
"
        ;;
esac