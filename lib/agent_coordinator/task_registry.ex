defmodule AgentCoordinator.TaskRegistry do
  @moduledoc """
  Central registry for agents and task assignment with NATS integration.
  """
  
  use GenServer
  alias AgentCoordinator.{Agent, Task, Inbox}

  defstruct [
    :agents,
    :pending_tasks,
    :file_locks,
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

  def get_file_locks do
    GenServer.call(__MODULE__, :get_file_locks)
  end

  # Server callbacks

  def init(opts) do
    # Connect to NATS
    nats_config = Keyword.get(opts, :nats, [])
    {:ok, nats_conn} = Gnat.start_link(nats_config)
    
    # Subscribe to task events
    Gnat.sub(nats_conn, self(), "agent.task.*")
    Gnat.sub(nats_conn, self(), "agent.heartbeat.*")
    
    state = %__MODULE__{
      agents: %{},
      pending_tasks: [],
      file_locks: %{},
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
        
        # Publish agent registration
        publish_event(state.nats_conn, "agent.registered", %{agent: agent})
        
        # Try to assign pending tasks
        {assigned_tasks, remaining_pending} = assign_pending_tasks(new_state)
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
        # Check for file conflicts
        case check_file_conflicts(state, task) do
          [] ->
            # No conflicts, assign task
            assign_task_to_agent(state, task, agent.id)
          
          conflicts ->
            # Block task due to conflicts
            blocked_task = Task.block(task, "File conflicts: #{inspect(conflicts)}")
            new_pending = [blocked_task | state.pending_tasks]
            
            publish_event(state.nats_conn, "task.blocked", %{
              task: blocked_task, 
              conflicts: conflicts
            })
            
            {:reply, {:error, :file_conflicts}, %{state | pending_tasks: new_pending}}
        end
    end
  end

  def handle_call({:add_to_pending, task}, _from, state) do
    new_pending = [task | state.pending_tasks]
    publish_event(state.nats_conn, "task.queued", %{task: task})
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
        
        publish_event(state.nats_conn, "agent.heartbeat", %{agent_id: agent_id})
        
        {:reply, :ok, new_state}
    end
  end

  def handle_call(:get_file_locks, _from, state) do
    {:reply, state.file_locks, state}
  end

  # Handle NATS messages
  def handle_info({:msg, %{topic: "agent.task.started", body: body}}, state) do
    %{"task" => task_data} = Jason.decode!(body)
    
    # Update file locks
    file_locks = add_file_locks(state.file_locks, task_data["id"], task_data["file_paths"])
    
    {:noreply, %{state | file_locks: file_locks}}
  end

  def handle_info({:msg, %{topic: "agent.task.completed", body: body}}, state) do
    %{"task" => task_data} = Jason.decode!(body)
    
    # Remove file locks
    file_locks = remove_file_locks(state.file_locks, task_data["id"])
    
    # Try to assign pending tasks that might now be unblocked
    {_assigned, remaining_pending} = assign_pending_tasks(%{state | file_locks: file_locks})
    
    {:noreply, %{state | file_locks: file_locks, pending_tasks: remaining_pending}}
  end

  def handle_info({:msg, %{topic: topic}}, state) when topic != "agent.task.started" and topic != "agent.task.completed" do
    # Ignore other messages for now
    {:noreply, state}
  end

  # Private helpers

  defp find_available_agent(state, task) do
    state.agents
    |> Map.values()
    |> Enum.filter(fn agent -> 
      agent.status == :idle and 
      Agent.is_online?(agent) and
      Agent.can_handle?(agent, task)
    end)
    |> Enum.sort_by(fn agent -> 
      # Prefer agents with fewer pending tasks
      case Inbox.get_status(agent.id) do
        %{pending_count: count} -> count
        _ -> 999
      end
    end)
    |> List.first()
  end

  defp check_file_conflicts(state, task) do
    task.file_paths
    |> Enum.filter(fn file_path ->
      Map.has_key?(state.file_locks, file_path)
    end)
  end

  defp assign_task_to_agent(state, task, agent_id) do
    # Add to agent's inbox
    Inbox.add_task(agent_id, task)
    
    # Update agent status
    agent = Map.get(state.agents, agent_id)
    updated_agent = Agent.assign_task(agent, task.id)
    new_agents = Map.put(state.agents, agent_id, updated_agent)
    
    # Publish assignment
    publish_event(state.nats_conn, "task.assigned", %{
      task: task, 
      agent_id: agent_id
    })
    
    {:reply, {:ok, agent_id}, %{state | agents: new_agents}}
  end

  defp assign_pending_tasks(state) do
    {assigned, remaining} = Enum.reduce(state.pending_tasks, {[], []}, fn task, {assigned, pending} ->
      case find_available_agent(state, task) do
        nil -> 
          {assigned, [task | pending]}
        
        agent ->
          case check_file_conflicts(state, task) do
            [] ->
              Inbox.add_task(agent.id, task)
              {[{task, agent.id} | assigned], pending}
            
            _conflicts ->
              {assigned, [task | pending]}
          end
      end
    end)
    
    {assigned, Enum.reverse(remaining)}
  end

  defp add_file_locks(file_locks, task_id, file_paths) do
    Enum.reduce(file_paths, file_locks, fn path, locks ->
      Map.put(locks, path, task_id)
    end)
  end

  defp remove_file_locks(file_locks, task_id) do
    Enum.reject(file_locks, fn {_path, locked_task_id} -> 
      locked_task_id == task_id 
    end)
    |> Map.new()
  end

  defp publish_event(conn, topic, data) do
    message = Jason.encode!(data)
    Gnat.pub(conn, topic, message)
  end
end