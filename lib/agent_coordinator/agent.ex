defmodule AgentCoordinator.Agent do
  @moduledoc """
  Agent data structure for the coordination system.
  """

  @derive {Jason.Encoder,
           only: [
             :id,
             :name,
             :capabilities,
             :status,
             :current_task_id,
             :codebase_id,
             :workspace_path,
             :last_heartbeat,
             :metadata
           ]}
  defstruct [
    :id,
    :name,
    :capabilities,
    :status,
    :current_task_id,
    :codebase_id,
    :workspace_path,
    :last_heartbeat,
    :metadata
  ]

  @type status :: :idle | :busy | :offline | :error
  @type capability :: :coding | :testing | :documentation | :analysis | :review

  @type t :: %__MODULE__{
          id: String.t(),
          name: String.t(),
          capabilities: [capability()],
          status: status(),
          current_task_id: String.t() | nil,
          codebase_id: String.t(),
          workspace_path: String.t() | nil,
          last_heartbeat: DateTime.t(),
          metadata: map()
        }

  def new(name, capabilities, opts \\ []) do
    %__MODULE__{
      id: UUID.uuid4(),
      name: name,
      capabilities: capabilities,
      status: :idle,
      current_task_id: nil,
      codebase_id: Keyword.get(opts, :codebase_id, "default"),
      workspace_path: Keyword.get(opts, :workspace_path),
      last_heartbeat: DateTime.utc_now(),
      metadata: Keyword.get(opts, :metadata, %{})
    }
  end

  def heartbeat(agent) do
    %{agent | last_heartbeat: DateTime.utc_now()}
  end

  def assign_task(agent, task_id) do
    %{agent | status: :busy, current_task_id: task_id}
  end

  def complete_task(agent) do
    %{agent | status: :idle, current_task_id: nil}
  end

  def is_online?(agent) do
    DateTime.diff(DateTime.utc_now(), agent.last_heartbeat, :second) < 30
  end

  def can_handle?(agent, task) do
    # Check if agent is in the same codebase or can handle cross-codebase tasks
    codebase_compatible =
      agent.codebase_id == task.codebase_id or
        Map.get(agent.metadata, :cross_codebase_capable, false)

    # Simple capability matching - can be enhanced
    required_capabilities = Map.get(task.metadata, :required_capabilities, [])

    capability_match =
      case required_capabilities do
        [] -> true
        caps -> Enum.any?(caps, fn cap -> cap in agent.capabilities end)
      end

    codebase_compatible and capability_match
  end

  def can_work_cross_codebase?(agent) do
    Map.get(agent.metadata, :cross_codebase_capable, false)
  end
end
