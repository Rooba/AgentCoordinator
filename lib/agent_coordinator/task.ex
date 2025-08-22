defmodule AgentCoordinator.Task do
  @moduledoc """
  Task data structure for agent coordination system.
  """
  
  defstruct [
    :id,
    :title,
    :description,
    :status,
    :priority,
    :agent_id,
    :file_paths,
    :dependencies,
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
    file_paths: [String.t()],
    dependencies: [String.t()],
    created_at: DateTime.t(),
    updated_at: DateTime.t(),
    metadata: map()
  }

  def new(title, description, opts \\ []) do
    now = DateTime.utc_now()
    
    %__MODULE__{
      id: UUID.uuid4(),
      title: title,
      description: description,
      status: Keyword.get(opts, :status, :pending),
      priority: Keyword.get(opts, :priority, :normal),
      agent_id: Keyword.get(opts, :agent_id),
      file_paths: Keyword.get(opts, :file_paths, []),
      dependencies: Keyword.get(opts, :dependencies, []),
      created_at: now,
      updated_at: now,
      metadata: Keyword.get(opts, :metadata, %{})
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
    not MapSet.disjoint?(MapSet.new(task1.file_paths), MapSet.new(task2.file_paths))
  end
end