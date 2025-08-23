defmodule AgentCoordinator.CodebaseRegistry do
  @moduledoc """
  Registry for managing multiple codebases and their metadata.
  Tracks codebase state, dependencies, and cross-codebase coordination.
  """

  use GenServer

  defstruct [
    :codebases,
    :cross_codebase_dependencies,
    :nats_conn
  ]

  @type codebase :: %{
          id: String.t(),
          name: String.t(),
          workspace_path: String.t(),
          description: String.t() | nil,
          agents: [String.t()],
          active_tasks: [String.t()],
          metadata: map(),
          created_at: DateTime.t(),
          updated_at: DateTime.t()
        }

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def register_codebase(codebase_data) do
    GenServer.call(__MODULE__, {:register_codebase, codebase_data})
  end

  def update_codebase(codebase_id, updates) do
    GenServer.call(__MODULE__, {:update_codebase, codebase_id, updates})
  end

  def get_codebase(codebase_id) do
    GenServer.call(__MODULE__, {:get_codebase, codebase_id})
  end

  def list_codebases do
    GenServer.call(__MODULE__, :list_codebases)
  end

  def add_agent_to_codebase(codebase_id, agent_id) do
    GenServer.call(__MODULE__, {:add_agent_to_codebase, codebase_id, agent_id})
  end

  def remove_agent_from_codebase(codebase_id, agent_id) do
    GenServer.call(__MODULE__, {:remove_agent_from_codebase, codebase_id, agent_id})
  end

  def add_cross_codebase_dependency(
        source_codebase,
        target_codebase,
        dependency_type,
        metadata \\ %{}
      ) do
    GenServer.call(
      __MODULE__,
      {:add_cross_dependency, source_codebase, target_codebase, dependency_type, metadata}
    )
  end

  def get_codebase_dependencies(codebase_id) do
    GenServer.call(__MODULE__, {:get_dependencies, codebase_id})
  end

  def get_codebase_stats(codebase_id) do
    GenServer.call(__MODULE__, {:get_stats, codebase_id})
  end

  def can_execute_cross_codebase_task?(source_codebase, target_codebase) do
    GenServer.call(__MODULE__, {:can_execute_cross_task, source_codebase, target_codebase})
  end

  # Server callbacks

  def init(opts) do
    nats_config = Keyword.get(opts, :nats, [])

    nats_conn =
      case nats_config do
        [] ->
          nil

        config ->
          case Gnat.start_link(config) do
            {:ok, conn} ->
              # Subscribe to codebase events
              Gnat.sub(conn, self(), "codebase.>")
              conn

            {:error, _reason} ->
              nil
          end
      end

    # Register default codebase
    default_codebase = create_default_codebase()

    state = %__MODULE__{
      codebases: %{"default" => default_codebase},
      cross_codebase_dependencies: %{},
      nats_conn: nats_conn
    }

    {:ok, state}
  end

  def handle_call({:register_codebase, codebase_data}, _from, state) do
    codebase_id = Map.get(codebase_data, "id") || Map.get(codebase_data, :id) || UUID.uuid4()

    codebase = %{
      id: codebase_id,
      name: Map.get(codebase_data, "name") || Map.get(codebase_data, :name, "Unnamed Codebase"),
      workspace_path:
        Map.get(codebase_data, "workspace_path") || Map.get(codebase_data, :workspace_path),
      description: Map.get(codebase_data, "description") || Map.get(codebase_data, :description),
      agents: [],
      active_tasks: [],
      metadata: Map.get(codebase_data, "metadata") || Map.get(codebase_data, :metadata, %{}),
      created_at: DateTime.utc_now(),
      updated_at: DateTime.utc_now()
    }

    case Map.has_key?(state.codebases, codebase_id) do
      true ->
        {:reply, {:error, "Codebase already exists"}, state}

      false ->
        new_codebases = Map.put(state.codebases, codebase_id, codebase)
        new_state = %{state | codebases: new_codebases}

        # Publish codebase registration event
        if state.nats_conn do
          publish_event(state.nats_conn, "codebase.registered", %{codebase: codebase})
        end

        {:reply, {:ok, codebase_id}, new_state}
    end
  end

  def handle_call({:update_codebase, codebase_id, updates}, _from, state) do
    case Map.get(state.codebases, codebase_id) do
      nil ->
        {:reply, {:error, "Codebase not found"}, state}

      codebase ->
        updated_codebase =
          Map.merge(codebase, updates)
          |> Map.put(:updated_at, DateTime.utc_now())

        new_codebases = Map.put(state.codebases, codebase_id, updated_codebase)
        new_state = %{state | codebases: new_codebases}

        # Publish update event
        if state.nats_conn do
          publish_event(state.nats_conn, "codebase.updated", %{
            codebase_id: codebase_id,
            updates: updates
          })
        end

        {:reply, {:ok, updated_codebase}, new_state}
    end
  end

  def handle_call({:get_codebase, codebase_id}, _from, state) do
    codebase = Map.get(state.codebases, codebase_id)
    {:reply, codebase, state}
  end

  def handle_call(:list_codebases, _from, state) do
    codebases = Map.values(state.codebases)
    {:reply, codebases, state}
  end

  def handle_call({:add_agent_to_codebase, codebase_id, agent_id}, _from, state) do
    case Map.get(state.codebases, codebase_id) do
      nil ->
        {:reply, {:error, "Codebase not found"}, state}

      codebase ->
        updated_agents = Enum.uniq([agent_id | codebase.agents])
        updated_codebase = %{codebase | agents: updated_agents, updated_at: DateTime.utc_now()}
        new_codebases = Map.put(state.codebases, codebase_id, updated_codebase)

        {:reply, :ok, %{state | codebases: new_codebases}}
    end
  end

  def handle_call({:remove_agent_from_codebase, codebase_id, agent_id}, _from, state) do
    case Map.get(state.codebases, codebase_id) do
      nil ->
        {:reply, {:error, "Codebase not found"}, state}

      codebase ->
        updated_agents = Enum.reject(codebase.agents, &(&1 == agent_id))
        updated_codebase = %{codebase | agents: updated_agents, updated_at: DateTime.utc_now()}
        new_codebases = Map.put(state.codebases, codebase_id, updated_codebase)

        {:reply, :ok, %{state | codebases: new_codebases}}
    end
  end

  def handle_call({:add_cross_dependency, source_id, target_id, dep_type, metadata}, _from, state) do
    dependency = %{
      source: source_id,
      target: target_id,
      type: dep_type,
      metadata: metadata,
      created_at: DateTime.utc_now()
    }

    key = "#{source_id}->#{target_id}"
    new_dependencies = Map.put(state.cross_codebase_dependencies, key, dependency)

    # Publish cross-codebase dependency event
    if state.nats_conn do
      publish_event(state.nats_conn, "codebase.dependency.added", %{
        dependency: dependency
      })
    end

    {:reply, :ok, %{state | cross_codebase_dependencies: new_dependencies}}
  end

  def handle_call({:get_dependencies, codebase_id}, _from, state) do
    dependencies =
      state.cross_codebase_dependencies
      |> Map.values()
      |> Enum.filter(fn dep -> dep.source == codebase_id or dep.target == codebase_id end)

    {:reply, dependencies, state}
  end

  def handle_call({:get_stats, codebase_id}, _from, state) do
    case Map.get(state.codebases, codebase_id) do
      nil ->
        {:reply, {:error, "Codebase not found"}, state}

      codebase ->
        stats = %{
          id: codebase.id,
          name: codebase.name,
          agent_count: length(codebase.agents),
          active_task_count: length(codebase.active_tasks),
          dependencies: get_dependency_stats(state, codebase_id),
          last_updated: codebase.updated_at
        }

        {:reply, {:ok, stats}, state}
    end
  end

  def handle_call({:can_execute_cross_task, source_id, target_id}, _from, state) do
    # Check if both codebases exist
    source_exists = Map.has_key?(state.codebases, source_id)
    target_exists = Map.has_key?(state.codebases, target_id)

    can_execute =
      source_exists and target_exists and
        (source_id == target_id or has_cross_dependency?(state, source_id, target_id))

    {:reply, can_execute, state}
  end

  # Handle NATS messages
  def handle_info({:msg, %{topic: "codebase.task.started", body: body}}, state) do
    %{"codebase_id" => codebase_id, "task_id" => task_id} = Jason.decode!(body)

    case Map.get(state.codebases, codebase_id) do
      nil ->
        {:noreply, state}

      codebase ->
        updated_tasks = Enum.uniq([task_id | codebase.active_tasks])
        updated_codebase = %{codebase | active_tasks: updated_tasks}
        new_codebases = Map.put(state.codebases, codebase_id, updated_codebase)

        {:noreply, %{state | codebases: new_codebases}}
    end
  end

  def handle_info({:msg, %{topic: "codebase.task.completed", body: body}}, state) do
    %{"codebase_id" => codebase_id, "task_id" => task_id} = Jason.decode!(body)

    case Map.get(state.codebases, codebase_id) do
      nil ->
        {:noreply, state}

      codebase ->
        updated_tasks = Enum.reject(codebase.active_tasks, &(&1 == task_id))
        updated_codebase = %{codebase | active_tasks: updated_tasks}
        new_codebases = Map.put(state.codebases, codebase_id, updated_codebase)

        {:noreply, %{state | codebases: new_codebases}}
    end
  end

  def handle_info({:msg, _msg}, state) do
    # Ignore other messages
    {:noreply, state}
  end

  # Private helpers

  defp create_default_codebase do
    %{
      id: "default",
      name: "Default Codebase",
      workspace_path: nil,
      description: "Default codebase for agents without specific codebase assignment",
      agents: [],
      active_tasks: [],
      metadata: %{},
      created_at: DateTime.utc_now(),
      updated_at: DateTime.utc_now()
    }
  end

  defp has_cross_dependency?(state, source_id, target_id) do
    key = "#{source_id}->#{target_id}"
    Map.has_key?(state.cross_codebase_dependencies, key)
  end

  defp get_dependency_stats(state, codebase_id) do
    incoming =
      state.cross_codebase_dependencies
      |> Map.values()
      |> Enum.filter(fn dep -> dep.target == codebase_id end)
      |> length()

    outgoing =
      state.cross_codebase_dependencies
      |> Map.values()
      |> Enum.filter(fn dep -> dep.source == codebase_id end)
      |> length()

    %{incoming: incoming, outgoing: outgoing}
  end

  defp publish_event(conn, topic, data) do
    if conn do
      message = Jason.encode!(data)
      Gnat.pub(conn, topic, message)
    end
  end
end
