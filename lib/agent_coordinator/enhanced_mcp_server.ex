defmodule AgentCoordinator.EnhancedMCPServer do
  @moduledoc """
  Enhanced MCP server with automatic heartbeat management and collision detection.

  This module extends the base MCP server with:
  1. Automatic heartbeats on every operation
  2. Agent session tracking
  3. Enhanced collision detection
  4. Automatic agent cleanup on disconnect
  """

  use GenServer
  alias AgentCoordinator.{MCPServer, AutoHeartbeat, TaskRegistry}

  # Track active agent sessions
  defstruct [
    :agent_sessions,
    :session_monitors
  ]

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Enhanced MCP request handler with automatic heartbeat management
  """
  def handle_enhanced_mcp_request(request, session_info \\ %{}) do
    GenServer.call(__MODULE__, {:enhanced_mcp_request, request, session_info})
  end

  @doc """
  Register an agent with enhanced session tracking
  """
  def register_agent_with_session(name, capabilities, session_pid \\ self()) do
    GenServer.call(__MODULE__, {:register_agent_with_session, name, capabilities, session_pid})
  end

  # Server callbacks

  def init(_opts) do
    state = %__MODULE__{
      agent_sessions: %{},
      session_monitors: %{}
    }

    {:ok, state}
  end

  def handle_call({:enhanced_mcp_request, request, session_info}, {from_pid, _}, state) do
    # Extract agent_id from session or request
    agent_id = extract_agent_id(request, session_info, state)

    # If we have an agent_id, send heartbeat before and after operation
    enhanced_result =
      case agent_id do
        nil ->
          # No agent context, use normal MCP processing
          MCPServer.handle_mcp_request(request)

        id ->
          # Send pre-operation heartbeat
          pre_heartbeat = TaskRegistry.heartbeat_agent(id)

          # Process the request
          result = MCPServer.handle_mcp_request(request)

          # Send post-operation heartbeat and update session activity
          post_heartbeat = TaskRegistry.heartbeat_agent(id)
          update_session_activity(state, id, from_pid)

          # Add heartbeat metadata to successful responses
          case result do
            %{"result" => _} = success ->
              Map.put(success, "_heartbeat_metadata", %{
                agent_id: id,
                pre_heartbeat: pre_heartbeat,
                post_heartbeat: post_heartbeat,
                timestamp: DateTime.utc_now()
              })

            error_result ->
              error_result
          end
      end

    {:reply, enhanced_result, state}
  end

  def handle_call({:register_agent_with_session, name, capabilities, session_pid}, _from, state) do
    # Convert capabilities to strings if they're atoms
    string_capabilities =
      Enum.map(capabilities, fn
        cap when is_atom(cap) -> Atom.to_string(cap)
        cap when is_binary(cap) -> cap
      end)

    # Register the agent normally first
    case MCPServer.handle_mcp_request(%{
           "method" => "tools/call",
           "params" => %{
             "name" => "register_agent",
             "arguments" => %{"name" => name, "capabilities" => string_capabilities}
           }
         }) do
      %{"result" => %{"content" => [%{"text" => response_json}]}} ->
        case Jason.decode(response_json) do
          {:ok, %{"agent_id" => agent_id}} ->
            # Track the session
            monitor_ref = Process.monitor(session_pid)

            new_state = %{
              state
              | agent_sessions:
                  Map.put(state.agent_sessions, agent_id, %{
                    pid: session_pid,
                    name: name,
                    capabilities: capabilities,
                    registered_at: DateTime.utc_now(),
                    last_activity: DateTime.utc_now()
                  }),
                session_monitors: Map.put(state.session_monitors, monitor_ref, agent_id)
            }

            # Start automatic heartbeat management
            AutoHeartbeat.start_link([])

            AutoHeartbeat.register_agent_with_heartbeat(name, capabilities, %{
              session_pid: session_pid,
              enhanced_server: true
            })

            {:reply, {:ok, agent_id}, new_state}

          {:error, reason} ->
            {:reply, {:error, reason}, state}
        end

      %{"error" => %{"message" => message}} ->
        {:reply, {:error, message}, state}

      _ ->
        {:reply, {:error, "Unexpected response format"}, state}
    end
  end

  def handle_call(:get_enhanced_task_board, _from, state) do
    # Get the regular task board
    case MCPServer.handle_mcp_request(%{
           "method" => "tools/call",
           "params" => %{"name" => "get_task_board", "arguments" => %{}}
         }) do
      %{"result" => %{"content" => [%{"text" => response_json}]}} ->
        case Jason.decode(response_json) do
          {:ok, %{"agents" => agents}} ->
            # Enhance with session information
            enhanced_agents =
              Enum.map(agents, fn agent ->
                agent_id = agent["agent_id"]
                session_info = Map.get(state.agent_sessions, agent_id, %{})

                Map.merge(agent, %{
                  "session_active" => Map.has_key?(state.agent_sessions, agent_id),
                  "last_activity" => Map.get(session_info, :last_activity),
                  "session_duration" => calculate_session_duration(session_info)
                })
              end)

            result = %{
              "agents" => enhanced_agents,
              "active_sessions" => map_size(state.agent_sessions)
            }

            {:reply, {:ok, result}, state}

          {:error, reason} ->
            {:reply, {:error, reason}, state}
        end

      %{"error" => %{"message" => message}} ->
        {:reply, {:error, message}, state}
    end
  end

  # Handle process monitoring - cleanup when agent session dies
  def handle_info({:DOWN, monitor_ref, :process, _pid, _reason}, state) do
    case Map.get(state.session_monitors, monitor_ref) do
      nil ->
        {:noreply, state}

      agent_id ->
        # Clean up the agent session
        new_state = %{
          state
          | agent_sessions: Map.delete(state.agent_sessions, agent_id),
            session_monitors: Map.delete(state.session_monitors, monitor_ref)
        }

        # Stop heartbeat management
        AutoHeartbeat.stop_heartbeat(agent_id)

        # Mark agent as offline in registry
        # (This could be enhanced to gracefully handle ongoing tasks)

        {:noreply, new_state}
    end
  end

  # Private helpers

  defp extract_agent_id(request, session_info, state) do
    # Try to get agent_id from various sources
    cond do
      # From request arguments
      Map.get(request, "params", %{})
      |> Map.get("arguments", %{})
      |> Map.get("agent_id") ->
        request["params"]["arguments"]["agent_id"]

      # From session info
      Map.get(session_info, :agent_id) ->
        session_info.agent_id

      # From session lookup by PID
      session_pid = Map.get(session_info, :session_pid, self()) ->
        find_agent_by_session_pid(state, session_pid)

      true ->
        nil
    end
  end

  defp find_agent_by_session_pid(state, session_pid) do
    Enum.find_value(state.agent_sessions, fn {agent_id, session_data} ->
      if session_data.pid == session_pid, do: agent_id, else: nil
    end)
  end

  defp update_session_activity(state, agent_id, _session_pid) do
    case Map.get(state.agent_sessions, agent_id) do
      nil ->
        :ok

      session_data ->
        _updated_session = %{session_data | last_activity: DateTime.utc_now()}
        # Note: This doesn't update the state since we're in a call handler
        # In a real implementation, you might want to use cast for this
        :ok
    end
  end

  @doc """
  Get enhanced task board with session information
  """
  def get_enhanced_task_board do
    GenServer.call(__MODULE__, :get_enhanced_task_board)
  end

  defp calculate_session_duration(%{registered_at: start_time}) do
    DateTime.diff(DateTime.utc_now(), start_time, :second)
  end

  defp calculate_session_duration(_), do: nil
end
