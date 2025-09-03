defmodule AgentCoordinator do
  @moduledoc """
  Agent Coordinator - A Model Context Protocol (MCP) server for multi-agent coordination.

  Agent Coordinator enables multiple AI agents to work together seamlessly across codebases
  without conflicts. It provides intelligent task distribution, real-time communication,
  and cross-codebase coordination through a unified MCP interface.

  ## Key Features

  - **Multi-Agent Coordination**: Register multiple AI agents with different capabilities
  - **Intelligent Task Distribution**: Automatically assigns tasks based on agent capabilities
  - **Cross-Codebase Support**: Coordinate work across multiple repositories
  - **Unified MCP Interface**: Single server providing access to multiple external MCP servers
  - **Automatic Task Tracking**: Every tool usage becomes a tracked task
  - **Real-Time Communication**: Heartbeat system for agent liveness and coordination

  ## Quick Start

  To start the Agent Coordinator:

      # Start the MCP server
      ./scripts/mcp_launcher.sh

      # Or in development mode
      iex -S mix

  ## Main Components

  - `AgentCoordinator.MCPServer` - Core MCP protocol implementation
  - `AgentCoordinator.TaskRegistry` - Task management and agent coordination
  - `AgentCoordinator.UnifiedMCPServer` - Unified interface to external MCP servers
  - `AgentCoordinator.CodebaseRegistry` - Multi-repository support
  - `AgentCoordinator.VSCodeToolProvider` - VS Code integration tools

  ## MCP Tools Available

  ### Agent Coordination
  - `register_agent` - Register an agent with capabilities
  - `create_task` - Create tasks with requirements
  - `get_next_task` - Get assigned tasks
  - `complete_task` - Mark tasks complete
  - `get_task_board` - View all agent status
  - `heartbeat` - Maintain agent liveness

  ### Codebase Management
  - `register_codebase` - Register repositories
  - `create_cross_codebase_task` - Tasks spanning multiple repos
  - `add_codebase_dependency` - Define repository relationships

  ### External Tool Access
  All tools from external MCP servers are automatically available through
  the unified interface, including filesystem, context7, memory, and other servers.

  ## Usage Example

      # Register an agent
      AgentCoordinator.MCPServer.handle_mcp_request(%{
        "method" => "tools/call",
        "params" => %{
          "name" => "register_agent",
          "arguments" => %{
            "name" => "MyAgent",
            "capabilities" => ["coding", "testing"]
          }
        }
      })

  See the documentation in `docs/` for detailed implementation guides.
  """

  alias AgentCoordinator.MCPServer

  @doc """
  Get the version of Agent Coordinator.

  ## Examples

      iex> AgentCoordinator.version()
      "0.1.0"

  """
  def version do
    Application.spec(:agent_coordinator, :vsn) |> to_string()
  end

  @doc """
  Get the current status of the Agent Coordinator system.

  Returns information about active agents, tasks, and external MCP servers.

  ## Examples

      iex> AgentCoordinator.status()
      %{
        agents: 2,
        active_tasks: 1,
        external_servers: 3,
        uptime: 12345
      }

  """
  def status do
    with {:ok, board} <- get_task_board(),
         {:ok, server_status} <- get_server_status() do
      %{
        agents: length(board[:agents] || []),
        active_tasks: count_active_tasks(board),
        external_servers: count_active_servers(server_status),
        uptime: get_uptime()
      }
    else
      _ -> %{status: :error, message: "Unable to retrieve system status"}
    end
  end

  @doc """
  Get the current task board showing all agents and their status.

  Returns information about all registered agents, their current tasks,
  and overall system status.

  ## Examples

      iex> {:ok, board} = AgentCoordinator.get_task_board()
      iex> is_map(board)
      true

  """
  def get_task_board do
    request = %{
      "method" => "tools/call",
      "params" => %{"name" => "get_task_board", "arguments" => %{}},
      "jsonrpc" => "2.0",
      "id" => System.unique_integer()
    }

    case MCPServer.handle_mcp_request(request) do
      %{"result" => %{"content" => [%{"text" => text}]}} ->
        {:ok, Jason.decode!(text)}

      %{"error" => error} ->
        {:error, error}

      _ ->
        {:error, "Unexpected response format"}
    end
  end

  @doc """
  Register a new agent with the coordination system.

  ## Parameters

  - `name` - Agent name (string)
  - `capabilities` - List of capabilities (["coding", "testing", ...])
  - `opts` - Optional parameters (codebase_id, workspace_path, etc.)

  ## Examples

      iex> {:ok, result} = AgentCoordinator.register_agent("TestAgent", ["coding"])
      iex> is_map(result)
      true

  """
  def register_agent(name, capabilities, opts \\ []) do
    args =
      %{
        "name" => name,
        "capabilities" => capabilities
      }
      |> add_optional_arg("codebase_id", opts[:codebase_id])
      |> add_optional_arg("workspace_path", opts[:workspace_path])
      |> add_optional_arg("cross_codebase_capable", opts[:cross_codebase_capable])

    request = %{
      "method" => "tools/call",
      "params" => %{"name" => "register_agent", "arguments" => args},
      "jsonrpc" => "2.0",
      "id" => System.unique_integer()
    }

    case MCPServer.handle_mcp_request(request) do
      %{"result" => %{"content" => [%{"text" => text}]}} ->
        {:ok, Jason.decode!(text)}

      %{"error" => error} ->
        {:error, error}

      _ ->
        {:error, "Unexpected response format"}
    end
  end

  @doc """
  Create a new task in the coordination system.

  ## Parameters

  - `title` - Task title (string)
  - `description` - Task description (string)
  - `opts` - Optional parameters (priority, codebase_id, file_paths, etc.)

  ## Examples

      iex> {:ok, result} = AgentCoordinator.create_task("Test Task", "Test description")
      iex> is_map(result)
      true

  """
  def create_task(title, description, opts \\ []) do
    args =
      %{
        "title" => title,
        "description" => description
      }
      |> add_optional_arg("priority", opts[:priority])
      |> add_optional_arg("codebase_id", opts[:codebase_id])
      |> add_optional_arg("file_paths", opts[:file_paths])
      |> add_optional_arg("required_capabilities", opts[:required_capabilities])

    request = %{
      "method" => "tools/call",
      "params" => %{"name" => "create_task", "arguments" => args},
      "jsonrpc" => "2.0",
      "id" => System.unique_integer()
    }

    case MCPServer.handle_mcp_request(request) do
      %{"result" => %{"content" => [%{"text" => text}]}} ->
        {:ok, Jason.decode!(text)}

      %{"error" => error} ->
        {:error, error}

      _ ->
        {:error, "Unexpected response format"}
    end
  end

  # Private helpers

  defp add_optional_arg(args, _key, nil), do: args
  defp add_optional_arg(args, key, value), do: Map.put(args, key, value)

  defp count_active_tasks(%{agents: agents}) do
    Enum.count(agents, fn agent ->
      Map.get(agent, "current_task") != nil
    end)
  end

  defp count_active_tasks(_), do: 0

  defp count_active_servers(server_status) when is_map(server_status) do
    Map.get(server_status, :active_servers, 0)
  end

  defp count_active_servers(_), do: 0

  defp get_server_status do
    # This would call UnifiedMCPServer to get external server status
    # For now, return a placeholder
    {:ok, %{active_servers: 3}}
  end

  defp get_uptime do
    # Get system uptime in seconds
    {uptime_ms, _} = :erlang.statistics(:wall_clock)
    div(uptime_ms, 1000)
  end
end
