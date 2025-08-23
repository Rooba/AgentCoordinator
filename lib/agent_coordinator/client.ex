defmodule AgentCoordinator.Client do
  @moduledoc """
  Client wrapper for agents to interact with the coordination system.

  This module provides a high-level API that automatically handles:
  - Heartbeat management
  - Session tracking
  - Error handling and retries
  - Collision detection

  Usage:
  ```elixir
  # Start a client session
  {:ok, client} = AgentCoordinator.Client.start_session("MyAgent", [:coding, :analysis])

  # All operations automatically include heartbeats
  {:ok, task} = AgentCoordinator.Client.get_next_task(client)
  {:ok, result} = AgentCoordinator.Client.complete_task(client)
  ```
  """

  use GenServer
  alias AgentCoordinator.{EnhancedMCPServer, AutoHeartbeat}

  defstruct [
    :agent_id,
    :agent_name,
    :capabilities,
    :session_pid,
    :heartbeat_interval,
    :last_heartbeat,
    :auto_heartbeat_enabled
  ]

  # Client API

  @doc """
  Start a new agent session with automatic heartbeat management
  """
  def start_session(agent_name, capabilities, opts \\ []) do
    heartbeat_interval = Keyword.get(opts, :heartbeat_interval, 10_000)
    auto_heartbeat = Keyword.get(opts, :auto_heartbeat, true)

    GenServer.start_link(__MODULE__, %{
      agent_name: agent_name,
      capabilities: capabilities,
      heartbeat_interval: heartbeat_interval,
      auto_heartbeat_enabled: auto_heartbeat
    })
  end

  @doc """
  Get the next task for this agent (with automatic heartbeat)
  """
  def get_next_task(client_pid) do
    GenServer.call(client_pid, :get_next_task)
  end

  @doc """
  Create a task (with automatic heartbeat)
  """
  def create_task(client_pid, title, description, opts \\ %{}) do
    GenServer.call(client_pid, {:create_task, title, description, opts})
  end

  @doc """
  Complete the current task (with automatic heartbeat)
  """
  def complete_task(client_pid) do
    GenServer.call(client_pid, :complete_task)
  end

  @doc """
  Get task board with enhanced information (with automatic heartbeat)
  """
  def get_task_board(client_pid) do
    GenServer.call(client_pid, :get_task_board)
  end

  @doc """
  Send manual heartbeat
  """
  def heartbeat(client_pid) do
    GenServer.call(client_pid, :manual_heartbeat)
  end

  @doc """
  Get client session information
  """
  def get_session_info(client_pid) do
    GenServer.call(client_pid, :get_session_info)
  end

  @doc """
  Stop the client session (cleanly disconnects the agent)
  """
  def stop_session(client_pid) do
    GenServer.call(client_pid, :stop_session)
  end

  @doc """
  Unregister the agent (e.g., when waiting for user input)
  """
  def unregister_agent(client_pid, reason \\ "Waiting for user input") do
    GenServer.call(client_pid, {:unregister_agent, reason})
  end

  # Server callbacks

  def init(config) do
    # Register with enhanced MCP server
    case EnhancedMCPServer.register_agent_with_session(
      config.agent_name,
      config.capabilities,
      self()
    ) do
      {:ok, agent_id} ->
        state = %__MODULE__{
          agent_id: agent_id,
          agent_name: config.agent_name,
          capabilities: config.capabilities,
          session_pid: self(),
          heartbeat_interval: config.heartbeat_interval,
          last_heartbeat: DateTime.utc_now(),
          auto_heartbeat_enabled: config.auto_heartbeat_enabled
        }

        # Start automatic heartbeat timer if enabled
        if config.auto_heartbeat_enabled do
          schedule_heartbeat(state.heartbeat_interval)
        end

        {:ok, state}

      {:error, reason} ->
        {:stop, {:registration_failed, reason}}
    end
  end

  def handle_call(:get_next_task, _from, state) do
    request = %{
      "method" => "tools/call",
      "params" => %{
        "name" => "get_next_task",
        "arguments" => %{"agent_id" => state.agent_id}
      }
    }

    result = enhanced_mcp_call(request, state)
    {:reply, result, update_last_heartbeat(state)}
  end

  def handle_call({:create_task, title, description, opts}, _from, state) do
    arguments = Map.merge(%{
      "title" => title,
      "description" => description
    }, opts)

    request = %{
      "method" => "tools/call",
      "params" => %{
        "name" => "create_task",
        "arguments" => arguments
      }
    }

    result = enhanced_mcp_call(request, state)
    {:reply, result, update_last_heartbeat(state)}
  end

  def handle_call(:complete_task, _from, state) do
    request = %{
      "method" => "tools/call",
      "params" => %{
        "name" => "complete_task",
        "arguments" => %{"agent_id" => state.agent_id}
      }
    }

    result = enhanced_mcp_call(request, state)
    {:reply, result, update_last_heartbeat(state)}
  end

  def handle_call(:get_task_board, _from, state) do
    case EnhancedMCPServer.get_enhanced_task_board() do
      {:ok, board} ->
        {:reply, {:ok, board}, update_last_heartbeat(state)}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call(:manual_heartbeat, _from, state) do
    result = send_heartbeat(state.agent_id)
    {:reply, result, update_last_heartbeat(state)}
  end

  def handle_call(:get_session_info, _from, state) do
    info = %{
      agent_id: state.agent_id,
      agent_name: state.agent_name,
      capabilities: state.capabilities,
      last_heartbeat: state.last_heartbeat,
      heartbeat_interval: state.heartbeat_interval,
      auto_heartbeat_enabled: state.auto_heartbeat_enabled,
      session_duration: DateTime.diff(DateTime.utc_now(), state.last_heartbeat, :second)
    }

    {:reply, {:ok, info}, state}
  end

  def handle_call({:unregister_agent, reason}, _from, state) do
    request = %{
      "method" => "tools/call",
      "params" => %{
        "name" => "unregister_agent",
        "arguments" => %{"agent_id" => state.agent_id, "reason" => reason}
      }
    }

    result = enhanced_mcp_call(request, state)

    case result do
      {:ok, _data} ->
        # Successfully unregistered, stop heartbeats but keep session alive
        updated_state = %{state | auto_heartbeat_enabled: false}
        {:reply, result, updated_state}

      {:error, _reason} ->
        # Failed to unregister, keep current state
        {:reply, result, state}
    end
  end

  def handle_call(:stop_session, _from, state) do
    # Clean shutdown - could include task cleanup here
    {:stop, :normal, :ok, state}
  end

  # Handle automatic heartbeat timer
  def handle_info(:heartbeat_timer, state) do
    if state.auto_heartbeat_enabled do
      send_heartbeat(state.agent_id)
      schedule_heartbeat(state.heartbeat_interval)
    end

    {:noreply, update_last_heartbeat(state)}
  end

  # Handle unexpected messages
  def handle_info(_msg, state) do
    {:noreply, state}
  end

  # Cleanup on termination
  def terminate(_reason, state) do
    # Stop heartbeat management
    if state.agent_id do
      AutoHeartbeat.stop_heartbeat(state.agent_id)
    end

    :ok
  end

  # Private helpers

  defp enhanced_mcp_call(request, state) do
    session_info = %{
      agent_id: state.agent_id,
      session_pid: state.session_pid
    }

    case EnhancedMCPServer.handle_enhanced_mcp_request(request, session_info) do
      %{"result" => %{"content" => [%{"text" => response_json}]}} = response ->
        case Jason.decode(response_json) do
          {:ok, data} ->
            # Include heartbeat metadata if present
            metadata = Map.get(response, "_heartbeat_metadata", %{})
            {:ok, Map.put(data, "_heartbeat_metadata", metadata)}

          {:error, reason} ->
            {:error, {:json_decode_error, reason}}
        end

      %{"error" => %{"message" => message}} ->
        {:error, message}

      unexpected ->
        {:error, {:unexpected_response, unexpected}}
    end
  end

  defp send_heartbeat(agent_id) do
    request = %{
      "method" => "tools/call",
      "params" => %{
        "name" => "heartbeat",
        "arguments" => %{"agent_id" => agent_id}
      }
    }

    case EnhancedMCPServer.handle_enhanced_mcp_request(request) do
      %{"result" => _} -> :ok
      %{"error" => %{"message" => message}} -> {:error, message}
      _ -> {:error, :unknown_heartbeat_error}
    end
  end

  defp schedule_heartbeat(interval) do
    Process.send_after(self(), :heartbeat_timer, interval)
  end

  defp update_last_heartbeat(state) do
    %{state | last_heartbeat: DateTime.utc_now()}
  end
end
