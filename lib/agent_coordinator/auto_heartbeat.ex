defmodule AgentCoordinator.AutoHeartbeat do
  @moduledoc """
  Automatic heartbeat management for agents.

  This module provides:
  1. Automatic heartbeat sending with every MCP action
  2. Background heartbeat timer for idle periods
  3. Heartbeat wrapper functions for all operations
  """

  use GenServer
  alias AgentCoordinator.{MCPServer, TaskRegistry}

  # Heartbeat every 10 seconds when idle
  @heartbeat_interval 10_000

  # Store active agent contexts
  defstruct [
    :timers,
    :agent_contexts
  ]

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Register an agent with automatic heartbeat management
  """
  def register_agent_with_heartbeat(name, capabilities, agent_context \\ %{}) do
    # Convert capabilities to strings if they're atoms
    string_capabilities =
      Enum.map(capabilities, fn
        cap when is_atom(cap) -> Atom.to_string(cap)
        cap when is_binary(cap) -> cap
      end)

    # First register the agent normally
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
            # Start automatic heartbeat for this agent
            GenServer.call(__MODULE__, {:start_heartbeat, agent_id, agent_context})
            {:ok, agent_id}

          {:error, reason} ->
            {:error, reason}
        end

      %{"error" => %{"message" => message}} ->
        {:error, message}

      _ ->
        {:error, "Unexpected response format"}
    end
  end

  @doc """
  Wrapper for any MCP action that automatically sends heartbeat
  """
  def mcp_action_with_heartbeat(agent_id, action_request) do
    # Send heartbeat before action
    heartbeat_result = send_heartbeat(agent_id)

    # Perform the actual action
    action_result = MCPServer.handle_mcp_request(action_request)

    # Send heartbeat after action (to update last activity)
    post_heartbeat_result = send_heartbeat(agent_id)

    # Reset the timer for this agent
    GenServer.cast(__MODULE__, {:reset_timer, agent_id})

    # Return the action result along with heartbeat status
    case action_result do
      %{"result" => _} = success ->
        Map.put(success, "_heartbeat_status", %{
          pre: heartbeat_result,
          post: post_heartbeat_result
        })

      error_result ->
        error_result
    end
  end

  @doc """
  Convenience functions for common operations with automatic heartbeats
  """
  def create_task_with_heartbeat(agent_id, title, description, opts \\ %{}) do
    request = %{
      "method" => "tools/call",
      "params" => %{
        "name" => "create_task",
        "arguments" =>
          Map.merge(
            %{
              "title" => title,
              "description" => description
            },
            opts
          )
      }
    }

    mcp_action_with_heartbeat(agent_id, request)
  end

  def get_next_task_with_heartbeat(agent_id) do
    request = %{
      "method" => "tools/call",
      "params" => %{
        "name" => "get_next_task",
        "arguments" => %{"agent_id" => agent_id}
      }
    }

    mcp_action_with_heartbeat(agent_id, request)
  end

  def complete_task_with_heartbeat(agent_id) do
    request = %{
      "method" => "tools/call",
      "params" => %{
        "name" => "complete_task",
        "arguments" => %{"agent_id" => agent_id}
      }
    }

    mcp_action_with_heartbeat(agent_id, request)
  end

  def get_task_board_with_heartbeat(agent_id) do
    request = %{
      "method" => "tools/call",
      "params" => %{
        "name" => "get_task_board",
        "arguments" => %{}
      }
    }

    mcp_action_with_heartbeat(agent_id, request)
  end

  @doc """
  Stop heartbeat management for an agent (when they disconnect)
  """
  def stop_heartbeat(agent_id) do
    GenServer.call(__MODULE__, {:stop_heartbeat, agent_id})
  end

  # Server callbacks

  def init(_opts) do
    state = %__MODULE__{
      timers: %{},
      agent_contexts: %{}
    }

    {:ok, state}
  end

  def handle_call({:start_heartbeat, agent_id, context}, _from, state) do
    # Cancel existing timer if any
    if Map.has_key?(state.timers, agent_id) do
      Process.cancel_timer(state.timers[agent_id])
    end

    # Start new timer
    timer_ref = Process.send_after(self(), {:heartbeat_timer, agent_id}, @heartbeat_interval)

    new_state = %{
      state
      | timers: Map.put(state.timers, agent_id, timer_ref),
        agent_contexts: Map.put(state.agent_contexts, agent_id, context)
    }

    {:reply, :ok, new_state}
  end

  def handle_call({:stop_heartbeat, agent_id}, _from, state) do
    # Cancel timer
    if Map.has_key?(state.timers, agent_id) do
      Process.cancel_timer(state.timers[agent_id])
    end

    new_state = %{
      state
      | timers: Map.delete(state.timers, agent_id),
        agent_contexts: Map.delete(state.agent_contexts, agent_id)
    }

    {:reply, :ok, new_state}
  end

  def handle_cast({:reset_timer, agent_id}, state) do
    # Cancel existing timer
    if Map.has_key?(state.timers, agent_id) do
      Process.cancel_timer(state.timers[agent_id])
    end

    # Start new timer
    timer_ref = Process.send_after(self(), {:heartbeat_timer, agent_id}, @heartbeat_interval)

    new_state = %{state | timers: Map.put(state.timers, agent_id, timer_ref)}

    {:noreply, new_state}
  end

  def handle_info({:heartbeat_timer, agent_id}, state) do
    # Send heartbeat
    send_heartbeat(agent_id)

    # Schedule next heartbeat
    timer_ref = Process.send_after(self(), {:heartbeat_timer, agent_id}, @heartbeat_interval)
    new_state = %{state | timers: Map.put(state.timers, agent_id, timer_ref)}

    {:noreply, new_state}
  end

  # Private helpers

  defp send_heartbeat(agent_id) do
    case TaskRegistry.heartbeat_agent(agent_id) do
      :ok -> :ok
      {:error, reason} -> {:error, reason}
    end
  end
end
