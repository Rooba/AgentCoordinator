defmodule AgentCoordinator.WebSocketHandler do
  @moduledoc """
  WebSocket handler for real-time MCP communication.

  Provides:
  - Real-time MCP JSON-RPC over WebSocket
  - Tool filtering based on client context
  - Session management
  - Heartbeat and connection monitoring
  """

  @behaviour WebSock
  require Logger
  alias AgentCoordinator.{MCPServer, ToolFilter}

  defstruct [
    :client_context,
    :session_id,
    :last_heartbeat,
    :agent_id,
    :connection_info
  ]

  @heartbeat_interval 30_000  # 30 seconds

  @impl WebSock
  def init(opts) do
    session_id = "ws_" <> UUID.uuid4()

    # Initialize connection state
    state = %__MODULE__{
      session_id: session_id,
      last_heartbeat: DateTime.utc_now(),
      connection_info: opts
    }

    # Start heartbeat timer
    Process.send_after(self(), :heartbeat, @heartbeat_interval)

    IO.puts(:stderr, "WebSocket connection established: #{session_id}")

    {:ok, state}
  end

  @impl WebSock
  def handle_in({text, [opcode: :text]}, state) do
    case Jason.decode(text) do
      {:ok, message} ->
        handle_mcp_message(message, state)

      {:error, %Jason.DecodeError{} = error} ->
        error_response = %{
          "jsonrpc" => "2.0",
          "id" => nil,
          "error" => %{
            "code" => -32700,
            "message" => "Parse error: #{Exception.message(error)}"
          }
        }

        {:reply, {:text, Jason.encode!(error_response)}, state}
    end
  end

  @impl WebSock
  def handle_in({_binary, [opcode: :binary]}, state) do
    IO.puts(:stderr, "Received unexpected binary data on WebSocket")
    {:ok, state}
  end

  @impl WebSock
  def handle_info(:heartbeat, state) do
    # Send heartbeat if we have an agent registered
    if state.agent_id do
      heartbeat_request = %{
        "jsonrpc" => "2.0",
        "id" => generate_request_id(),
        "method" => "tools/call",
        "params" => %{
          "name" => "heartbeat",
          "arguments" => %{"agent_id" => state.agent_id}
        }
      }

      # Send heartbeat to MCP server
      MCPServer.handle_mcp_request(heartbeat_request)
    end

    # Schedule next heartbeat
    Process.send_after(self(), :heartbeat, @heartbeat_interval)

    updated_state = %{state | last_heartbeat: DateTime.utc_now()}
    {:ok, updated_state}
  end

  @impl WebSock
  def handle_info(message, state) do
    IO.puts(:stderr, "Received unexpected message: #{inspect(message)}")
    {:ok, state}
  end

  @impl WebSock
  def terminate(:remote, state) do
    IO.puts(:stderr, "WebSocket connection closed by client: #{state.session_id}")
    cleanup_session(state)
    :ok
  end

  @impl WebSock
  def terminate(reason, state) do
    IO.puts(:stderr, "WebSocket connection terminated: #{state.session_id}, reason: #{inspect(reason)}")
    cleanup_session(state)
    :ok
  end

  # Private helper functions

  defp handle_mcp_message(message, state) do
    method = Map.get(message, "method")

    case method do
      "initialize" ->
        handle_initialize(message, state)

      "tools/list" ->
        handle_tools_list(message, state)

      "tools/call" ->
        handle_tool_call(message, state)

      "notifications/initialized" ->
        handle_initialized_notification(message, state)

      _ ->
        # Forward other methods to MCP server
        forward_to_mcp_server(message, state)
    end
  end

  defp handle_initialize(message, state) do
    # Extract client info from initialize message
    params = Map.get(message, "params", %{})
    client_info = Map.get(params, "clientInfo", %{})

    # Detect client context
    connection_info = %{
      transport: :websocket,
      client_info: client_info,
      session_id: state.session_id,
      capabilities: Map.get(params, "capabilities", [])
    }

    client_context = ToolFilter.detect_client_context(connection_info)

    # Send initialize response
    response = %{
      "jsonrpc" => "2.0",
      "id" => Map.get(message, "id"),
      "result" => %{
        "protocolVersion" => "2024-11-05",
        "capabilities" => %{
          "tools" => %{},
          "coordination" => %{
            "automatic_task_tracking" => true,
            "agent_management" => true,
            "multi_server_proxy" => true,
            "heartbeat_coverage" => true,
            "session_tracking" => true,
            "tool_filtering" => true,
            "websocket_realtime" => true
          }
        },
        "serverInfo" => %{
          "name" => "agent-coordinator-websocket",
          "version" => AgentCoordinator.version(),
          "description" => "Agent Coordinator WebSocket interface with tool filtering"
        },
        "_meta" => %{
          "session_id" => state.session_id,
          "connection_type" => client_context.connection_type,
          "security_level" => client_context.security_level
        }
      }
    }

    updated_state = %{state |
      client_context: client_context,
      connection_info: connection_info
    }

    {:reply, {:text, Jason.encode!(response)}, updated_state}
  end

  defp handle_tools_list(message, state) do
    if state.client_context do
      # Get filtered tools based on client context
      all_tools = MCPServer.get_tools()
      filtered_tools = ToolFilter.filter_tools(all_tools, state.client_context)

      response = %{
        "jsonrpc" => "2.0",
        "id" => Map.get(message, "id"),
        "result" => %{
          "tools" => filtered_tools,
          "_meta" => %{
            "filtered_for" => state.client_context.connection_type,
            "original_count" => length(all_tools),
            "filtered_count" => length(filtered_tools),
            "session_id" => state.session_id
          }
        }
      }

      {:reply, {:text, Jason.encode!(response)}, state}
    else
      # Client hasn't initialized yet
      error_response = %{
        "jsonrpc" => "2.0",
        "id" => Map.get(message, "id"),
        "error" => %{
          "code" => -32002,
          "message" => "Client must initialize first"
        }
      }

      {:reply, {:text, Jason.encode!(error_response)}, state}
    end
  end

  defp handle_tool_call(message, state) do
    if state.client_context do
      tool_name = get_in(message, ["params", "name"])

      # Check if tool is allowed for this client context
      if tool_allowed_for_context?(tool_name, state.client_context) do
        # Enhance message with session info
        enhanced_message = add_websocket_session_info(message, state)

        # Track agent ID if this is a register_agent call
        updated_state = maybe_track_agent_id(message, state)

        # Forward to MCP server
        case MCPServer.handle_mcp_request(enhanced_message) do
          response when is_map(response) ->
            {:reply, {:text, Jason.encode!(response)}, updated_state}

          unexpected ->
            IO.puts(:stderr, "Unexpected MCP response: #{inspect(unexpected)}")
            error_response = %{
              "jsonrpc" => "2.0",
              "id" => Map.get(message, "id"),
              "error" => %{
                "code" => -32603,
                "message" => "Internal server error"
              }
            }

            {:reply, {:text, Jason.encode!(error_response)}, updated_state}
        end
      else
        # Tool not allowed for this client
        error_response = %{
          "jsonrpc" => "2.0",
          "id" => Map.get(message, "id"),
          "error" => %{
            "code" => -32601,
            "message" => "Tool not available for #{state.client_context.connection_type} clients: #{tool_name}"
          }
        }

        {:reply, {:text, Jason.encode!(error_response)}, state}
      end
    else
      # Client hasn't initialized yet
      error_response = %{
        "jsonrpc" => "2.0",
        "id" => Map.get(message, "id"),
        "error" => %{
          "code" => -32002,
          "message" => "Client must initialize first"
        }
      }

      {:reply, {:text, Jason.encode!(error_response)}, state}
    end
  end

  defp handle_initialized_notification(_message, state) do
    # Client is ready to receive notifications
    IO.puts(:stderr, "WebSocket client initialized: #{state.session_id}")
    {:ok, state}
  end

  defp forward_to_mcp_server(message, state) do
    if state.client_context do
      enhanced_message = add_websocket_session_info(message, state)

      case MCPServer.handle_mcp_request(enhanced_message) do
        response when is_map(response) ->
          {:reply, {:text, Jason.encode!(response)}, state}

        nil ->
          # Some notifications don't return responses
          {:ok, state}

        unexpected ->
          IO.puts(:stderr, "Unexpected MCP response: #{inspect(unexpected)}")
          {:ok, state}
      end
    else
      error_response = %{
        "jsonrpc" => "2.0",
        "id" => Map.get(message, "id"),
        "error" => %{
          "code" => -32002,
          "message" => "Client must initialize first"
        }
      }

      {:reply, {:text, Jason.encode!(error_response)}, state}
    end
  end

  defp add_websocket_session_info(message, state) do
    # Add session tracking info to the message
    params = Map.get(message, "params", %{})

    enhanced_params = params
    |> Map.put("_session_id", state.session_id)
    |> Map.put("_transport", "websocket")
    |> Map.put("_client_context", %{
      connection_type: state.client_context.connection_type,
      security_level: state.client_context.security_level,
      session_id: state.session_id
    })

    Map.put(message, "params", enhanced_params)
  end

  defp tool_allowed_for_context?(tool_name, client_context) do
    all_tools = MCPServer.get_tools()
    filtered_tools = ToolFilter.filter_tools(all_tools, client_context)

    Enum.any?(filtered_tools, fn tool ->
      Map.get(tool, "name") == tool_name
    end)
  end

  defp maybe_track_agent_id(message, state) do
    case get_in(message, ["params", "name"]) do
      "register_agent" ->
        # We'll get the agent_id from the response, but for now mark that we expect one
        %{state | agent_id: :pending}

      _ ->
        state
    end
  end

  defp cleanup_session(state) do
    # Unregister agent if one was registered through this session
    if state.agent_id && state.agent_id != :pending do
      unregister_request = %{
        "jsonrpc" => "2.0",
        "id" => generate_request_id(),
        "method" => "tools/call",
        "params" => %{
          "name" => "unregister_agent",
          "arguments" => %{
            "agent_id" => state.agent_id,
            "reason" => "WebSocket connection closed"
          }
        }
      }

      MCPServer.handle_mcp_request(unregister_request)
    end
  end

  defp generate_request_id do
    "ws_req_" <> (:crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower))
  end
end
