defmodule AgentCoordinator.Task do
  @moduledoc """
  Task data structure for agent coordination system.
  """

  @derive {Jason.Encoder,
           only: [
             :id,
             :title,
             :description,
             :status,
             :priority,
             :agent_id,
             :codebase_id,
             :file_paths,
             :dependencies,
             :cross_codebase_dependencies,
             :created_at,
             :updated_at,
             :metadata
           ]}
  defstruct [
    :id,
    :title,
    :description,
    :status,
    :priority,
    :agent_id,
    :codebase_id,
    :file_paths,
    :dependencies,
    :cross_codebase_dependencies,
    :created_at,
    :updated_at,
    :metadata
  ]

  @type status :: :pending | :in_progress | :completed | :failed | :blocked
  @type priority :: :low | :normal | :high | :urgent

  @type t :: %__MODULE__{
          id: String.t(),
          title: String.t(),
          description: String.t(),
          status: status(),
          priority: priority(),
          agent_id: String.t() | nil,
          codebase_id: String.t(),
          file_paths: [String.t()],
          dependencies: [String.t()],
          cross_codebase_dependencies: [%{codebase_id: String.t(), task_id: String.t()}],
          created_at: DateTime.t(),
          updated_at: DateTime.t(),
          metadata: map()
        }

  def new(title, description, opts \\ []) do
    now = DateTime.utc_now()

    # Handle both keyword lists and maps
    get_opt = fn key, default ->
      case opts do
        opts when is_map(opts) -> Map.get(opts, key, default)
        opts when is_list(opts) -> Keyword.get(opts, key, default)
      end
    end

    %__MODULE__{
      id: UUID.uuid4(),
      title: title,
      description: description,
      status: get_opt.(:status, :pending),
      priority: get_opt.(:priority, :normal),
      agent_id: get_opt.(:agent_id, nil),
      codebase_id: get_opt.(:codebase_id, "default"),
      file_paths: get_opt.(:file_paths, []),
      dependencies: get_opt.(:dependencies, []),
      cross_codebase_dependencies: get_opt.(:cross_codebase_dependencies, []),
      created_at: now,
      updated_at: now,
      metadata: get_opt.(:metadata, %{})
    }
  end

  def assign_to_agent(task, agent_id) do
    %{task | agent_id: agent_id, status: :in_progress, updated_at: DateTime.utc_now()}
  end

  def complete(task) do
    %{task | status: :completed, updated_at: DateTime.utc_now()}
  end

  def fail(task, reason \\ nil) do
    metadata = if reason, do: Map.put(task.metadata, :failure_reason, reason), else: task.metadata
    %{task | status: :failed, metadata: metadata, updated_at: DateTime.utc_now()}
  end

  def block(task, reason \\ nil) do
    metadata = if reason, do: Map.put(task.metadata, :block_reason, reason), else: task.metadata
    %{task | status: :blocked, metadata: metadata, updated_at: DateTime.utc_now()}
  end

  def has_file_conflict?(task1, task2) do
    # Only check conflicts within the same codebase
    task1.codebase_id == task2.codebase_id and
      not MapSet.disjoint?(MapSet.new(task1.file_paths), MapSet.new(task2.file_paths))
  end

  def is_cross_codebase?(task) do
    not Enum.empty?(task.cross_codebase_dependencies)
  end

  def add_cross_codebase_dependency(task, codebase_id, task_id) do
    dependency = %{codebase_id: codebase_id, task_id: task_id}
    dependencies = [dependency | task.cross_codebase_dependencies]
    %{task | cross_codebase_dependencies: dependencies, updated_at: DateTime.utc_now()}
  end
end
