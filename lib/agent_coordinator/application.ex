defmodule AgentCoordinator.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # Registry for agent inboxes
      {Registry, keys: :unique, name: AgentCoordinator.InboxRegistry},
      
      # PubSub for real-time updates
      {Phoenix.PubSub, name: AgentCoordinator.PubSub},
      
      # Persistence layer
      {AgentCoordinator.Persistence, nats: nats_config()},
      
      # Task registry with NATS integration
      {AgentCoordinator.TaskRegistry, nats: nats_config()},
      
      # MCP server
      AgentCoordinator.MCPServer,
      
      # Dynamic supervisor for agent inboxes
      {DynamicSupervisor, name: AgentCoordinator.InboxSupervisor, strategy: :one_for_one}
    ]

    opts = [strategy: :one_for_one, name: AgentCoordinator.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp nats_config do
    [
      host: System.get_env("NATS_HOST", "localhost"),
      port: String.to_integer(System.get_env("NATS_PORT", "4222")),
      connection_settings: [
        name: :agent_coordinator
      ]
    ]
  end
end
