defmodule AgentCoordinator.Agent do
  @moduledoc """
  Agent data structure for the coordination system.
  """
  
  defstruct [
    :id,
    :name,
    :capabilities,
    :status,
    :current_task_id,
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
    # Simple capability matching - can be enhanced
    required_capabilities = Map.get(task.metadata, :required_capabilities, [])
    
    case required_capabilities do
      [] -> true
      caps -> Enum.any?(caps, fn cap -> cap in agent.capabilities end)
    end
  end
end