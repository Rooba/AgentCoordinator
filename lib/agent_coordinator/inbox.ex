defmodule AgentCoordinator.Inbox do
  @moduledoc """
  Agent inbox management using GenServer for each agent's task queue.
  """

  use GenServer
  alias AgentCoordinator.Task

  defstruct [
    :agent_id,
    :pending_tasks,
    :in_progress_task,
    :completed_tasks,
    :max_history
  ]

  @type t :: %__MODULE__{
          agent_id: String.t(),
          pending_tasks: [Task.t()],
          in_progress_task: Task.t() | nil,
          completed_tasks: [Task.t()],
          max_history: non_neg_integer()
        }

  # Client API

  def start_link(agent_id, opts \\ []) do
    GenServer.start_link(__MODULE__, {agent_id, opts}, name: via_tuple(agent_id))
  end

  def add_task(agent_id, task) do
    GenServer.call(via_tuple(agent_id), {:add_task, task}, 30_000)
  end

  def get_next_task(agent_id) do
    GenServer.call(via_tuple(agent_id), :get_next_task, 15_000)
  end

  def complete_current_task(agent_id) do
    GenServer.call(via_tuple(agent_id), :complete_current_task, 30_000)
  end

  def get_status(agent_id) do
    GenServer.call(via_tuple(agent_id), :get_status, 15_000)
  end

  def list_tasks(agent_id) do
    GenServer.call(via_tuple(agent_id), :list_tasks, 15_000)
  end

  def get_current_task(agent_id) do
    GenServer.call(via_tuple(agent_id), :get_current_task, 15_000)
  end

  def stop(agent_id) do
    case Registry.lookup(AgentCoordinator.InboxRegistry, agent_id) do
      [{pid, _}] ->
        GenServer.stop(pid, :normal)
        :ok

      [] ->
        {:error, :not_found}
    end
  end

  # Server callbacks

  def init({agent_id, opts}) do
    state = %__MODULE__{
      agent_id: agent_id,
      pending_tasks: [],
      in_progress_task: nil,
      completed_tasks: [],
      max_history: Keyword.get(opts, :max_history, 100)
    }

    {:ok, state}
  end

  def handle_call({:add_task, task}, _from, state) do
    # Insert task based on priority
    pending_tasks = insert_by_priority(state.pending_tasks, task)
    new_state = %{state | pending_tasks: pending_tasks}

    # Broadcast task added
    Phoenix.PubSub.broadcast(
      AgentCoordinator.PubSub,
      "agent:#{state.agent_id}",
      {:task_added, task}
    )

    {:reply, :ok, new_state}
  end

  def handle_call(:get_next_task, _from, state) do
    case state.pending_tasks do
      [] ->
        {:reply, nil, state}

      [next_task | remaining_tasks] ->
        updated_task = Task.assign_to_agent(next_task, state.agent_id)
        new_state = %{state | pending_tasks: remaining_tasks, in_progress_task: updated_task}

        # Broadcast task started
        Phoenix.PubSub.broadcast(AgentCoordinator.PubSub, "global", {:task_started, updated_task})

        {:reply, updated_task, new_state}
    end
  end

  def handle_call(:complete_current_task, _from, state) do
    case state.in_progress_task do
      nil ->
        {:reply, {:error, :no_task_in_progress}, state}

      task ->
        completed_task = Task.complete(task)

        # Add to completed tasks with history limit
        completed_tasks =
          [completed_task | state.completed_tasks]
          |> Enum.take(state.max_history)

        new_state = %{state | in_progress_task: nil, completed_tasks: completed_tasks}

        # Broadcast task completed
        Phoenix.PubSub.broadcast(
          AgentCoordinator.PubSub,
          "global",
          {:task_completed, completed_task}
        )

        {:reply, completed_task, new_state}
    end
  end

  def handle_call(:get_status, _from, state) do
    status = %{
      agent_id: state.agent_id,
      pending_count: length(state.pending_tasks),
      current_task: state.in_progress_task,
      completed_count: length(state.completed_tasks)
    }

    {:reply, status, state}
  end

  def handle_call(:list_tasks, _from, state) do
    tasks = %{
      pending: state.pending_tasks,
      in_progress: state.in_progress_task,
      # Recent 10
      completed: Enum.take(state.completed_tasks, 10)
    }

    {:reply, tasks, state}
  end

  def handle_call(:get_current_task, _from, state) do
    {:reply, state.in_progress_task, state}
  end

  # Private helpers

  defp via_tuple(agent_id) do
    {:via, Registry, {AgentCoordinator.InboxRegistry, agent_id}}
  end

  defp insert_by_priority(tasks, new_task) do
    priority_order = %{urgent: 0, high: 1, normal: 2, low: 3}
    new_priority = Map.get(priority_order, new_task.priority, 2)

    {before, after_tasks} =
      Enum.split_while(tasks, fn task ->
        task_priority = Map.get(priority_order, task.priority, 2)
        task_priority <= new_priority
      end)

    before ++ [new_task] ++ after_tasks
  end
end
