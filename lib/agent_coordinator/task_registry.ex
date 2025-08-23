defmodule AgentCoordinator.TaskRegistry do
  @moduledoc """
  Central registry for agents and task assignment with NATS integration.
  Enhanced to support multi-codebase coordination and cross-codebase task management.
  """

  use GenServer
  require Logger
  alias AgentCoordinator.{Agent, Task, Inbox}

  defstruct [
    :agents,
    :pending_tasks,
    :file_locks,
    :codebase_file_locks,
    :cross_codebase_tasks,
    :nats_conn
  ]

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def register_agent(agent) do
    GenServer.call(__MODULE__, {:register_agent, agent})
  end

  def assign_task(task) do
    GenServer.call(__MODULE__, {:assign_task, task})
  end

  def add_to_pending(task) do
    GenServer.call(__MODULE__, {:add_to_pending, task})
  end

  def list_agents do
    GenServer.call(__MODULE__, :list_agents)
  end

  def heartbeat_agent(agent_id) do
    GenServer.call(__MODULE__, {:heartbeat_agent, agent_id})
  end

  def unregister_agent(agent_id, reason \\ "Agent requested unregistration") do
    GenServer.call(__MODULE__, {:unregister_agent, agent_id, reason})
  end

  def get_file_locks do
    GenServer.call(__MODULE__, :get_file_locks)
  end

  def get_agent_current_task(agent_id) do
    GenServer.call(__MODULE__, {:get_agent_current_task, agent_id})
  end

  def update_task_activity(task_id, tool_name, arguments) do
    GenServer.call(__MODULE__, {:update_task_activity, task_id, tool_name, arguments})
  end

  def create_task(title, description, opts \\ %{}) do
    GenServer.call(__MODULE__, {:create_task, title, description, opts})
  end

  def get_next_task(agent_id) do
    GenServer.call(__MODULE__, {:get_next_task, agent_id})
  end

  def complete_task(agent_id) do
    GenServer.call(__MODULE__, {:complete_task, agent_id})
  end

  def get_task_board do
    GenServer.call(__MODULE__, :get_task_board)
  end

  def register_agent(name, capabilities) do
    agent = Agent.new(name, capabilities)
    GenServer.call(__MODULE__, {:register_agent, agent})
  end

  # Server callbacks

  def init(opts) do
    # Connect to NATS if config provided
    nats_config = Keyword.get(opts, :nats, [])

    nats_conn =
      case nats_config do
        [] ->
          nil

        config ->
          case Gnat.start_link(config) do
            {:ok, conn} ->
              # Subscribe to task events
              Gnat.sub(conn, self(), "agent.task.*")
              Gnat.sub(conn, self(), "agent.heartbeat.*")
              Gnat.sub(conn, self(), "codebase.>")
              Gnat.sub(conn, self(), "cross-codebase.>")
              conn

            {:error, _reason} ->
              nil
          end
      end

    state = %__MODULE__{
      agents: %{},
      pending_tasks: [],
      file_locks: %{},
      codebase_file_locks: %{},
      cross_codebase_tasks: %{},
      nats_conn: nats_conn
    }

    {:ok, state}
  end

  def handle_call({:register_agent, agent}, _from, state) do
    # Check for duplicate names
    case Enum.find(state.agents, fn {_id, a} -> a.name == agent.name end) do
      nil ->
        new_agents = Map.put(state.agents, agent.id, agent)
        new_state = %{state | agents: new_agents}

        # Create inbox for the agent
        case DynamicSupervisor.start_child(
               AgentCoordinator.InboxSupervisor,
               {Inbox, agent.id}
             ) do
          {:ok, _pid} ->
            Logger.info("Created inbox for agent #{agent.id}")

          {:error, {:already_started, _pid}} ->
            Logger.info("Inbox already exists for agent #{agent.id}")

          {:error, reason} ->
            Logger.warning("Failed to create inbox for agent #{agent.id}: #{inspect(reason)}")
        end

        # Publish agent registration with codebase info
        if state.nats_conn do
          publish_event(state.nats_conn, "agent.registered.#{agent.codebase_id}", %{agent: agent})
        end

        # Try to assign pending tasks
        {_assigned_tasks, remaining_pending} = assign_pending_tasks(new_state)
        final_state = %{new_state | pending_tasks: remaining_pending}

        {:reply, :ok, final_state}

      _ ->
        {:reply, {:error, "Agent name already exists"}, state}
    end
  end

  def handle_call({:assign_task, task}, _from, state) do
    case find_available_agent(state, task) do
      nil ->
        {:reply, {:error, :no_available_agents}, state}

      agent ->
        # Check for file conflicts within the same codebase
        case check_file_conflicts(state, task) do
          [] ->
            # No conflicts, assign task
            assign_task_to_agent(state, task, agent.id)

          conflicts ->
            # Block task due to conflicts
            blocked_task = Task.block(task, "File conflicts: #{inspect(conflicts)}")
            new_pending = [blocked_task | state.pending_tasks]

            if state.nats_conn do
              publish_event(state.nats_conn, "task.blocked.#{task.codebase_id}", %{
                task: blocked_task,
                conflicts: conflicts
              })
            end

            {:reply, {:error, :file_conflicts}, %{state | pending_tasks: new_pending}}
        end
    end
  end

  def handle_call({:add_to_pending, task}, _from, state) do
    new_pending = [task | state.pending_tasks]

    if state.nats_conn do
      publish_event(state.nats_conn, "task.queued.#{task.codebase_id}", %{task: task})
    end

    {:reply, :ok, %{state | pending_tasks: new_pending}}
  end

  def handle_call(:list_agents, _from, state) do
    agents = Map.values(state.agents)
    {:reply, agents, state}
  end

  def handle_call({:heartbeat_agent, agent_id}, _from, state) do
    case Map.get(state.agents, agent_id) do
      nil ->
        {:reply, {:error, :agent_not_found}, state}

      agent ->
        updated_agent = Agent.heartbeat(agent)
        new_agents = Map.put(state.agents, agent_id, updated_agent)
        new_state = %{state | agents: new_agents}

        if state.nats_conn do
          publish_event(state.nats_conn, "agent.heartbeat.#{agent_id}", %{
            agent_id: agent_id,
            codebase_id: updated_agent.codebase_id
          })
        end

        {:reply, :ok, new_state}
    end
  end

  def handle_call({:unregister_agent, agent_id, reason}, _from, state) do
    case Map.get(state.agents, agent_id) do
      nil ->
        {:reply, {:error, :agent_not_found}, state}

      agent ->
        # Check if agent has current tasks
        case agent.current_task_id do
          nil ->
            # Agent is idle, safe to unregister
            unregister_agent_safely(state, agent_id, agent, reason)

          task_id ->
            # Agent has active task, handle accordingly
            case Map.get(state, :allow_force_unregister, false) do
              true ->
                # Force unregister, reassign task to pending
                unregister_agent_with_task_reassignment(state, agent_id, agent, task_id, reason)

              false ->
                {:reply,
                 {:error,
                  "Agent has active task #{task_id}. Complete task first or use force unregister."},
                 state}
            end
        end
    end
  end

  def handle_call(:get_file_locks, _from, state) do
    {:reply, state.codebase_file_locks || %{}, state}
  end

  def handle_call({:get_agent_current_task, agent_id}, _from, state) do
    case Map.get(state.agents, agent_id) do
      nil ->
        {:reply, nil, state}

      agent ->
        case agent.current_task_id do
          nil ->
            {:reply, nil, state}

          task_id ->
            # Get task details from inbox or pending tasks
            task = find_task_by_id(state, task_id)
            {:reply, task, state}
        end
    end
  end

  def handle_call({:update_task_activity, task_id, tool_name, arguments}, _from, state) do
    # Update task with latest activity
    # This could store activity logs or update task metadata
    if state.nats_conn do
      publish_event(state.nats_conn, "task.activity_updated", %{
        task_id: task_id,
        tool_name: tool_name,
        arguments: arguments,
        timestamp: DateTime.utc_now()
      })
    end

    {:reply, :ok, state}
  end

  def handle_call({:create_task, title, description, opts}, _from, state) do
    task = Task.new(title, description, opts)

    # Add to pending tasks
    new_pending = [task | state.pending_tasks]
    new_state = %{state | pending_tasks: new_pending}

    # Try to assign immediately
    case find_available_agent(new_state, task) do
      nil ->
        if state.nats_conn do
          publish_event(state.nats_conn, "task.created", %{task: task})
        end

        {:reply, {:ok, task}, new_state}

      agent ->
        case check_file_conflicts(new_state, task) do
          [] ->
            # Assign immediately
            case assign_task_to_agent(new_state, task, agent.id) do
              {:reply, {:ok, _agent_id}, final_state} ->
                # Remove from pending since it was assigned
                final_state = %{final_state | pending_tasks: state.pending_tasks}
                {:reply, {:ok, task}, final_state}

              error ->
                error
            end

          _conflicts ->
            # Keep in pending due to conflicts
            {:reply, {:ok, task}, new_state}
        end
    end
  end

  def handle_call({:get_next_task, agent_id}, _from, state) do
    case Map.get(state.agents, agent_id) do
      nil ->
        {:reply, {:error, :agent_not_found}, state}

      agent ->
        # First ensure the agent's inbox exists
        case ensure_inbox_started(agent_id) do
          :ok ->
            case Inbox.get_next_task(agent_id) do
              nil ->
                {:reply, {:error, :no_tasks}, state}

              task ->
                # Update agent status
                updated_agent = Agent.assign_task(agent, task.id)
                new_agents = Map.put(state.agents, agent_id, updated_agent)
                new_state = %{state | agents: new_agents}

                if state.nats_conn do
                  publish_event(state.nats_conn, "task.started", %{
                    task: task,
                    agent_id: agent_id
                  })
                end

                {:reply, {:ok, task}, new_state}
            end

          {:error, reason} ->
            {:reply, {:error, reason}, state}
        end
    end
  end

  def handle_call({:complete_task, agent_id}, _from, state) do
    case Map.get(state.agents, agent_id) do
      nil ->
        {:reply, {:error, :agent_not_found}, state}

      agent ->
        case agent.current_task_id do
          nil ->
            {:reply, {:error, :no_current_task}, state}

          task_id ->
            # Mark task as completed in inbox
            case Inbox.complete_current_task(agent_id) do
              task when is_map(task) ->
                # Update agent status back to idle
                updated_agent = Agent.complete_task(agent)
                new_agents = Map.put(state.agents, agent_id, updated_agent)
                new_state = %{state | agents: new_agents}

                if state.nats_conn do
                  publish_event(state.nats_conn, "task.completed", %{
                    task_id: task_id,
                    agent_id: agent_id
                  })
                end

                # Try to assign pending tasks
                {_assigned, remaining_pending} = assign_pending_tasks(new_state)
                final_state = %{new_state | pending_tasks: remaining_pending}

                {:reply, :ok, final_state}

              {:error, reason} ->
                {:reply, {:error, reason}, state}
            end
        end
    end
  end

  def handle_call(:get_task_board, _from, state) do
    agents_info =
      Enum.map(state.agents, fn {_id, agent} ->
        current_task =
          case agent.current_task_id do
            nil -> nil
            task_id -> find_task_by_id(state, task_id)
          end

        %{
          agent_id: agent.id,
          name: agent.name,
          status: agent.status,
          capabilities: agent.capabilities,
          current_task: current_task,
          last_heartbeat: agent.last_heartbeat,
          online: Agent.is_online?(agent)
        }
      end)

    task_board = %{
      agents: agents_info,
      pending_tasks: state.pending_tasks,
      total_agents: map_size(state.agents),
      active_tasks: Enum.count(state.agents, fn {_id, agent} -> agent.current_task_id != nil end),
      pending_count: length(state.pending_tasks)
    }

    {:reply, task_board, state}
  end

  # Handle NATS messages
  def handle_info({:msg, %{topic: "agent.task.started", body: body}}, state) do
    %{"task" => task_data, "codebase_id" => codebase_id} = Jason.decode!(body)

    # Update codebase-specific file locks
    codebase_file_locks =
      add_file_locks(
        state.codebase_file_locks,
        codebase_id,
        task_data["id"],
        task_data["file_paths"]
      )

    {:noreply, %{state | codebase_file_locks: codebase_file_locks}}
  end

  def handle_info({:msg, %{topic: "agent.task.completed", body: body}}, state) do
    %{"task" => task_data, "codebase_id" => codebase_id} = Jason.decode!(body)

    # Remove codebase-specific file locks
    codebase_file_locks =
      remove_file_locks(
        state.codebase_file_locks,
        codebase_id,
        task_data["id"]
      )

    # Try to assign pending tasks that might now be unblocked
    {_assigned, remaining_pending} =
      assign_pending_tasks(%{state | codebase_file_locks: codebase_file_locks})

    {:noreply,
     %{state | codebase_file_locks: codebase_file_locks, pending_tasks: remaining_pending}}
  end

  def handle_info({:msg, %{topic: "cross-codebase.task.created", body: body}}, state) do
    %{"main_task_id" => main_task_id, "dependent_tasks" => dependent_tasks} = Jason.decode!(body)

    # Track cross-codebase task relationship
    cross_codebase_tasks = Map.put(state.cross_codebase_tasks, main_task_id, dependent_tasks)

    {:noreply, %{state | cross_codebase_tasks: cross_codebase_tasks}}
  end

  def handle_info({:msg, %{topic: "codebase.agent.registered", body: body}}, state) do
    # Handle cross-codebase agent registration notifications
    %{"agent" => _agent_data} = Jason.decode!(body)
    # Could trigger reassignment of pending cross-codebase tasks
    {:noreply, state}
  end

  def handle_info({:msg, %{topic: topic}}, state)
      when topic != "agent.task.started" and
             topic != "agent.task.completed" and
             topic != "cross-codebase.task.created" and
             topic != "codebase.agent.registered" do
    # Ignore other messages for now
    {:noreply, state}
  end

  # Private helpers

  defp ensure_inbox_started(agent_id) do
    case Registry.lookup(AgentCoordinator.InboxRegistry, agent_id) do
      [{_pid, _}] ->
        :ok

      [] ->
        # Start the inbox for this agent
        case DynamicSupervisor.start_child(
               AgentCoordinator.InboxSupervisor,
               {Inbox, agent_id}
             ) do
          {:ok, _pid} -> :ok
          {:error, {:already_started, _pid}} -> :ok
          {:error, reason} -> {:error, reason}
        end
    end
  end

  defp find_available_agent(state, task) do
    state.agents
    |> Map.values()
    |> Enum.filter(fn agent ->
      agent.codebase_id == task.codebase_id and
        agent.status == :idle and
        Agent.is_online?(agent) and
        Agent.can_handle?(agent, task)
    end)
    |> Enum.sort_by(fn agent ->
      # Prefer agents with fewer pending tasks and same codebase
      codebase_match = if agent.codebase_id == task.codebase_id, do: 0, else: 1

      pending_count =
        case Registry.lookup(AgentCoordinator.InboxRegistry, agent.id) do
          [{_pid, _}] ->
            try do
              case Inbox.get_status(agent.id) do
                %{pending_count: count} -> count
                _ -> 0
              end
            catch
              :exit, _ -> 0
            end
          [] ->
            # No inbox process exists, treat as 0 pending tasks
            0
        end

      {codebase_match, pending_count}
    end)
    |> List.first()
  end

  defp check_file_conflicts(state, task) do
    # Get codebase-specific file locks
    codebase_locks = Map.get(state.codebase_file_locks, task.codebase_id, %{})

    task.file_paths
    |> Enum.filter(fn file_path ->
      Map.has_key?(codebase_locks, file_path)
    end)
  end

  defp assign_task_to_agent(state, task, agent_id) do
    # Ensure inbox exists for the agent
    ensure_inbox_exists(agent_id)

    # Add to agent's inbox
    Inbox.add_task(agent_id, task)

    # Update agent status
    agent = Map.get(state.agents, agent_id)
    updated_agent = Agent.assign_task(agent, task.id)
    new_agents = Map.put(state.agents, agent_id, updated_agent)

    # Publish assignment with codebase context
    if state.nats_conn do
      publish_event(state.nats_conn, "task.assigned.#{task.codebase_id}", %{
        task: task,
        agent_id: agent_id
      })
    end

    {:reply, {:ok, agent_id}, %{state | agents: new_agents}}
  end

  defp assign_pending_tasks(state) do
    {assigned, remaining} =
      Enum.reduce(state.pending_tasks, {[], []}, fn task, {assigned, pending} ->
        case find_available_agent(state, task) do
          nil ->
            {assigned, [task | pending]}

          agent ->
            case check_file_conflicts(state, task) do
              [] ->
                # Ensure inbox exists for the agent
                ensure_inbox_exists(agent.id)
                Inbox.add_task(agent.id, task)
                {[{task, agent.id} | assigned], pending}

              _conflicts ->
                {assigned, [task | pending]}
            end
        end
      end)

    {assigned, Enum.reverse(remaining)}
  end

  defp add_file_locks(codebase_file_locks, codebase_id, task_id, file_paths) do
    codebase_locks = Map.get(codebase_file_locks, codebase_id, %{})

    updated_locks =
      Enum.reduce(file_paths, codebase_locks, fn path, locks ->
        Map.put(locks, path, task_id)
      end)

    Map.put(codebase_file_locks, codebase_id, updated_locks)
  end

  defp remove_file_locks(codebase_file_locks, codebase_id, task_id) do
    case Map.get(codebase_file_locks, codebase_id) do
      nil ->
        codebase_file_locks

      codebase_locks ->
        updated_locks =
          Enum.reject(codebase_locks, fn {_path, locked_task_id} ->
            locked_task_id == task_id
          end)
          |> Map.new()

        Map.put(codebase_file_locks, codebase_id, updated_locks)
    end
  end

  defp find_task_by_id(state, task_id) do
    # Look for task in pending tasks first
    case Enum.find(state.pending_tasks, fn task -> task.id == task_id end) do
      nil ->
        # Try to find in agent inboxes - for now return nil
        # TODO: Implement proper task lookup in Inbox module
        nil

      task ->
        task
    end
  end

  defp publish_event(conn, topic, data) do
    if conn do
      message = Jason.encode!(data)
      Gnat.pub(conn, topic, message)
    end
  end

  # Agent unregistration helpers

  defp unregister_agent_safely(state, agent_id, agent, reason) do
    # Remove agent from registry
    new_agents = Map.delete(state.agents, agent_id)
    new_state = %{state | agents: new_agents}

    # Stop the agent's inbox if it exists
    case Inbox.stop(agent_id) do
      :ok -> :ok
      # Inbox already stopped
      {:error, :not_found} -> :ok
      # Continue regardless
      _ -> :ok
    end

    # Publish unregistration event
    if state.nats_conn do
      publish_event(state.nats_conn, "agent.unregistered", %{
        agent_id: agent_id,
        agent_name: agent.name,
        codebase_id: agent.codebase_id,
        reason: reason,
        timestamp: DateTime.utc_now()
      })
    end

    {:reply, :ok, new_state}
  end

  defp unregister_agent_with_task_reassignment(state, agent_id, agent, task_id, reason) do
    # Get the current task from inbox
    case Inbox.get_current_task(agent_id) do
      nil ->
        # No actual task, treat as safe unregister
        unregister_agent_safely(state, agent_id, agent, reason)

      task ->
        # Reassign task to pending queue
        new_pending = [task | state.pending_tasks]

        # Remove agent
        new_agents = Map.delete(state.agents, agent_id)
        new_state = %{state | agents: new_agents, pending_tasks: new_pending}

        # Stop the agent's inbox
        Inbox.stop(agent_id)

        # Publish events
        if state.nats_conn do
          publish_event(state.nats_conn, "agent.unregistered.with_reassignment", %{
            agent_id: agent_id,
            agent_name: agent.name,
            codebase_id: agent.codebase_id,
            reason: reason,
            reassigned_task_id: task_id,
            timestamp: DateTime.utc_now()
          })

          publish_event(state.nats_conn, "task.reassigned", %{
            task_id: task_id,
            from_agent_id: agent_id,
            to_queue: "pending",
            reason: "Agent unregistered: #{reason}"
          })
        end

        {:reply, :ok, new_state}
    end
  end

  # Helper function to ensure an inbox exists for an agent
  defp ensure_inbox_exists(agent_id) do
    case Registry.lookup(AgentCoordinator.InboxRegistry, agent_id) do
      [] ->
        # No inbox exists, create one
        case DynamicSupervisor.start_child(
               AgentCoordinator.InboxSupervisor,
               {Inbox, agent_id}
             ) do
          {:ok, _pid} ->
            Logger.info("Created inbox for agent #{agent_id}")
            :ok

          {:error, {:already_started, _pid}} ->
            Logger.info("Inbox already exists for agent #{agent_id}")
            :ok

          {:error, reason} ->
            Logger.warning("Failed to create inbox for agent #{agent_id}: #{inspect(reason)}")
            {:error, reason}
        end

      [{_pid, _}] ->
        # Inbox already exists
        :ok
    end
  end
end
