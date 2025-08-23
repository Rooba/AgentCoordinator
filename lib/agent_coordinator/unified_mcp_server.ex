defmodule AgentCoordinator.UnifiedMCPServer do
  @moduledoc """
  Unified MCP Server that aggregates all external MCP servers and Agent Coordinator tools.

  This is the single MCP server that GitHub Copilot sees, which internally manages
  all other MCP servers and provides automatic task tracking for any tool usage.
  """

  use GenServer
  require Logger

  alias AgentCoordinator.{MCPServerManager, TaskRegistry}

  defstruct [
    :agent_sessions,
    :request_id_counter
  ]

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Handle MCP request from GitHub Copilot
  """
  def handle_mcp_request(request) do
    GenServer.call(__MODULE__, {:handle_request, request})
  end

  # Server callbacks

  def init(_opts) do
    state = %__MODULE__{
      agent_sessions: %{},
      request_id_counter: 0
    }

    Logger.info("Unified MCP Server starting...")

    {:ok, state}
  end

  def handle_call({:handle_request, request}, _from, state) do
    response = process_mcp_request(request, state)
    {:reply, response, state}
  end

  def handle_call({:register_agent_session, agent_id, session_info}, _from, state) do
    new_state = %{state | agent_sessions: Map.put(state.agent_sessions, agent_id, session_info)}
    {:reply, :ok, new_state}
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end

  # Private functions

  defp process_mcp_request(request, state) do
    method = Map.get(request, "method")
    id = Map.get(request, "id")

    case method do
      "initialize" ->
        handle_initialize(request, id)

      "tools/list" ->
        handle_tools_list(request, id)

      "tools/call" ->
        handle_tools_call(request, id, state)

      _ ->
        error_response(id, -32601, "Method not found: #{method}")
    end
  end

  defp handle_initialize(_request, id) do
    %{
      "jsonrpc" => "2.0",
      "id" => id,
      "result" => %{
        "protocolVersion" => "2024-11-05",
        "capabilities" => %{
          "tools" => %{},
          "coordination" => %{
            "automatic_task_tracking" => true,
            "agent_management" => true,
            "multi_server_proxy" => true,
            "heartbeat_coverage" => true
          }
        },
        "serverInfo" => %{
          "name" => "agent-coordinator-unified",
          "version" => "0.1.0",
          "description" =>
            "Unified MCP server with automatic task tracking and agent coordination"
        }
      }
    }
  end

  defp handle_tools_list(_request, id) do
    case MCPServerManager.get_unified_tools() do
      tools when is_list(tools) ->
        %{
          "jsonrpc" => "2.0",
          "id" => id,
          "result" => %{
            "tools" => tools
          }
        }

      {:error, reason} ->
        error_response(id, -32603, "Failed to get tools: #{reason}")
    end
  end

  defp handle_tools_call(request, id, state) do
    params = Map.get(request, "params", %{})
    tool_name = Map.get(params, "name")
    arguments = Map.get(params, "arguments", %{})

    # Determine agent context from the request or session
    agent_context = determine_agent_context(request, arguments, state)

    case MCPServerManager.route_tool_call(tool_name, arguments, agent_context) do
      %{"error" => _} = error_result ->
        Map.put(error_result, "id", id)

      result ->
        # Wrap successful results in MCP format
        success_response = %{
          "jsonrpc" => "2.0",
          "id" => id,
          "result" => format_tool_result(result, tool_name, agent_context)
        }

        success_response
    end
  end

  defp determine_agent_context(request, arguments, state) do
    # Try to determine agent from various sources:

    # 1. Explicit agent_id in arguments
    case Map.get(arguments, "agent_id") do
      agent_id when is_binary(agent_id) ->
        %{agent_id: agent_id}

      _ ->
        # 2. Try to extract from request metadata
        case extract_agent_from_request(request) do
          agent_id when is_binary(agent_id) ->
            %{agent_id: agent_id}

          _ ->
            # 3. Use a default session for GitHub Copilot
            default_agent_context(state)
        end
    end
  end

  defp extract_agent_from_request(_request) do
    # Look for agent info in request headers, params, etc.
    # This could be extended to support various ways of identifying the agent
    nil
  end

  defp default_agent_context(state) do
    # Create or use a default agent session for GitHub Copilot
    default_agent_id = "github_copilot_session"

    case Map.get(state.agent_sessions, default_agent_id) do
      nil ->
        # Auto-register GitHub Copilot as an agent
        case TaskRegistry.register_agent("GitHub Copilot", [
               "coding",
               "analysis",
               "review",
               "documentation"
             ]) do
          {:ok, %{agent_id: agent_id}} ->
            session_info = %{
              agent_id: agent_id,
              name: "GitHub Copilot",
              auto_registered: true,
              created_at: DateTime.utc_now()
            }

            GenServer.call(self(), {:register_agent_session, agent_id, session_info})
            %{agent_id: agent_id}

          _ ->
            %{agent_id: default_agent_id}
        end

      session_info ->
        %{agent_id: session_info.agent_id}
    end
  end

  defp format_tool_result(result, tool_name, agent_context) do
    # Format the result according to MCP tool call response format
    base_result =
      case result do
        %{"result" => content} when is_map(content) ->
          # Already properly formatted
          content

        {:ok, content} ->
          # Convert tuple response to content
          %{"content" => [%{"type" => "text", "text" => inspect(content)}]}

        %{} = map_result ->
          # Convert map to text content
          %{"content" => [%{"type" => "text", "text" => Jason.encode!(map_result)}]}

        binary when is_binary(binary) ->
          # Simple text result
          %{"content" => [%{"type" => "text", "text" => binary}]}

        other ->
          # Fallback for any other type
          %{"content" => [%{"type" => "text", "text" => inspect(other)}]}
      end

    # Add metadata about the operation
    metadata = %{
      "tool_name" => tool_name,
      "agent_id" => agent_context.agent_id,
      "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601(),
      "auto_tracked" => true
    }

    Map.put(base_result, "_metadata", metadata)
  end

  defp error_response(id, code, message) do
    %{
      "jsonrpc" => "2.0",
      "id" => id,
      "error" => %{
        "code" => code,
        "message" => message
      }
    }
  end
end
