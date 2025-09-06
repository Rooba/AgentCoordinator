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
             :metadata,
             :current_activity,
             :current_files,
             :activity_history
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
    :metadata,
    :current_activity,
    :current_files,
    :activity_history
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
          metadata: map(),
          current_activity: String.t() | nil,
          current_files: [String.t()],
          activity_history: [map()]
        }

  def new(name, capabilities, opts \\ []) do
    workspace_path = Keyword.get(opts, :workspace_path)
    
    # Use smart codebase identification
    codebase_id = case Keyword.get(opts, :codebase_id) do
      nil when workspace_path ->
        # Auto-detect from workspace
        case AgentCoordinator.CodebaseIdentifier.identify_codebase(workspace_path) do
          %{canonical_id: canonical_id} -> canonical_id
          _ -> Path.basename(workspace_path || "default")
        end
      
      nil ->
        "default"
      
      explicit_id ->
        # Normalize the provided ID  
        AgentCoordinator.CodebaseIdentifier.normalize_codebase_reference(explicit_id, workspace_path)
    end
    
    %__MODULE__{
      id: UUID.uuid4(),
      name: name,
      capabilities: capabilities,
      status: :idle,
      current_task_id: nil,
      codebase_id: codebase_id,
      workspace_path: workspace_path,
      last_heartbeat: DateTime.utc_now(),
      metadata: Keyword.get(opts, :metadata, %{}),
      current_activity: nil,
      current_files: [],
      activity_history: []
    }
  end

  def heartbeat(agent) do
    %{agent | last_heartbeat: DateTime.utc_now()}
  end

  def update_activity(agent, activity, files \\ []) do
    # Add to activity history (keep last 10 activities)
    activity_entry = %{
      activity: activity,
      files: files,
      timestamp: DateTime.utc_now()
    }
    
    new_history = [activity_entry | agent.activity_history]
                  |> Enum.take(10)
    
    %{agent | 
      current_activity: activity,
      current_files: files,
      activity_history: new_history,
      last_heartbeat: DateTime.utc_now()
    }
  end

  def clear_activity(agent) do
    %{agent | 
      current_activity: nil,
      current_files: [],
      last_heartbeat: DateTime.utc_now()
    }
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
