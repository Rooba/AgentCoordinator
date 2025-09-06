defmodule AgentCoordinator.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    # Check if persistence should be enabled (useful for testing)
    enable_persistence = Application.get_env(:agent_coordinator, :enable_persistence, true)

    children = [
      # Registry for agent inboxes
      {Registry, keys: :unique, name: AgentCoordinator.InboxRegistry},

      # PubSub for real-time updates
      {Phoenix.PubSub, name: AgentCoordinator.PubSub},

      # Codebase registry for multi-codebase coordination
      {AgentCoordinator.CodebaseRegistry,
       nats: if(enable_persistence, do: nats_config(), else: nil)},

      # Task registry with NATS integration (conditionally add persistence)
      {AgentCoordinator.TaskRegistry, nats: if(enable_persistence, do: nats_config(), else: nil)},

      # Session manager for MCP session token handling
      AgentCoordinator.SessionManager,

      # Unified MCP server (includes external server management, session tracking, and auto-registration)
      AgentCoordinator.MCPServer,

      # Interface manager for multiple MCP interface modes
      AgentCoordinator.InterfaceManager,

      # Auto-heartbeat manager
      AgentCoordinator.AutoHeartbeat,

      # Dynamic supervisor for agent inboxes
      {DynamicSupervisor, name: AgentCoordinator.InboxSupervisor, strategy: :one_for_one}
    ]

    # Add persistence layer if enabled
    children =
      if enable_persistence do
        [{AgentCoordinator.Persistence, nats: nats_config()} | children]
      else
        children
      end

    opts = [strategy: :one_for_one, name: AgentCoordinator.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp nats_config do
    %{
      host: System.get_env("NATS_HOST", "localhost"),
      port: String.to_integer(System.get_env("NATS_PORT", "4222")),
      connection_settings: %{
        name: :agent_coordinator
      }
    }
  end
end
