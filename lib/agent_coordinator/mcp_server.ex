defmodule AgentCoordinator.MCPServer do
  @moduledoc """
  MCP (Model Context Protocol) server for agent coordination.
  Provides tools for agents to interact with the task coordination system.
  """
  
  use GenServer
  alias AgentCoordinator.{TaskRegistry, Inbox, Agent, Task}

  @mcp_tools [
    %{
      "name" => "register_agent",
      "description" => "Register a new agent with the coordination system",
      "inputSchema" => %{
        "type" => "object",
        "properties" => %{
          "name" => %{"type" => "string"},
          "capabilities" => %{
            "type" => "array",
            "items" => %{"type" => "string", "enum" => ["coding", "testing", "documentation", "analysis", "review"]}
          }
        },
        "required" => ["name", "capabilities"]
      }
    },
    %{
      "name" => "create_task",
      "description" => "Create a new task in the coordination system",
      "inputSchema" => %{
        "type" => "object",
        "properties" => %{
          "title" => %{"type" => "string"},
          "description" => %{"type" => "string"},
          "priority" => %{"type" => "string", "enum" => ["low", "normal", "high", "urgent"]},
          "file_paths" => %{"type" => "array", "items" => %{"type" => "string"}},
          "required_capabilities" => %{
            "type" => "array", 
            "items" => %{"type" => "string"}
          }
        },
        "required" => ["title", "description"]
      }
    },
    %{
      "name" => "get_next_task",
      "description" => "Get the next task for an agent",
      "inputSchema" => %{
        "type" => "object",
        "properties" => %{
          "agent_id" => %{"type" => "string"}
        },
        "required" => ["agent_id"]
      }
    },
    %{
      "name" => "complete_task",
      "description" => "Mark current task as completed",
      "inputSchema" => %{
        "type" => "object",
        "properties" => %{
          "agent_id" => %{"type" => "string"}
        },
        "required" => ["agent_id"]
      }
    },
    %{
      "name" => "get_task_board",
      "description" => "Get overview of all agents and their current tasks",
      "inputSchema" => %{
        "type" => "object",
        "properties" => %{}
      }
    },
    %{
      "name" => "heartbeat",
      "description" => "Send heartbeat to maintain agent status",
      "inputSchema" => %{
        "type" => "object",
        "properties" => %{
          "agent_id" => %{"type" => "string"}
        },
        "required" => ["agent_id"]
      }
    }
  ]

  # Client API
  
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def handle_mcp_request(request) do
    GenServer.call(__MODULE__, {:mcp_request, request})
  end

  def get_tools do
    @mcp_tools
  end

  # Server callbacks

  def init(_opts) do
    {:ok, %{}}
  end

  def handle_call({:mcp_request, request}, _from, state) do
    response = process_mcp_request(request)
    {:reply, response, state}
  end

  # MCP request processing

  defp process_mcp_request(%{"method" => "tools/list"}) do
    %{
      "jsonrpc" => "2.0",
      "result" => %{"tools" => @mcp_tools}
    }
  end

  defp process_mcp_request(%{
    "method" => "tools/call", 
    "params" => %{"name" => tool_name, "arguments" => args}
  } = request) do
    id = Map.get(request, "id", nil)
    
    result = case tool_name do
      "register_agent" -> register_agent(args)
      "create_task" -> create_task(args)
      "get_next_task" -> get_next_task(args)
      "complete_task" -> complete_task(args)
      "get_task_board" -> get_task_board(args)
      "heartbeat" -> heartbeat(args)
      _ -> {:error, "Unknown tool: #{tool_name}"}
    end

    case result do
      {:ok, data} ->
        %{
          "jsonrpc" => "2.0",
          "id" => id,
          "result" => %{"content" => [%{"type" => "text", "text" => Jason.encode!(data)}]}
        }
      
      {:error, reason} ->
        %{
          "jsonrpc" => "2.0",
          "id" => id,
          "error" => %{"code" => -1, "message" => reason}
        }
    end
  end

  defp process_mcp_request(_request) do
    %{
      "jsonrpc" => "2.0",
      "error" => %{"code" => -32601, "message" => "Method not found"}
    }
  end

  # Tool implementations

  defp register_agent(%{"name" => name, "capabilities" => capabilities}) do
    caps = Enum.map(capabilities, &String.to_existing_atom/1)
    agent = Agent.new(name, caps)
    
    case TaskRegistry.register_agent(agent) do
      :ok ->
        # Start inbox for the agent
        {:ok, _pid} = Inbox.start_link(agent.id)
        {:ok, %{agent_id: agent.id, status: "registered"}}
      
      {:error, reason} ->
        {:error, "Failed to register agent: #{reason}"}
    end
  end

  defp create_task(%{"title" => title, "description" => description} = args) do
    opts = [
      priority: String.to_existing_atom(Map.get(args, "priority", "normal")),
      file_paths: Map.get(args, "file_paths", []),
      metadata: %{
        required_capabilities: Map.get(args, "required_capabilities", [])
      }
    ]
    
    task = Task.new(title, description, opts)
    
    case TaskRegistry.assign_task(task) do
      {:ok, agent_id} ->
        {:ok, %{task_id: task.id, assigned_to: agent_id, status: "assigned"}}
      
      {:error, :no_available_agents} ->
        # Add to global pending queue
        TaskRegistry.add_to_pending(task)
        {:ok, %{task_id: task.id, status: "queued"}}
    end
  end

  defp get_next_task(%{"agent_id" => agent_id}) do
    case Inbox.get_next_task(agent_id) do
      nil ->
        {:ok, %{message: "No tasks available"}}
      
      task ->
        {:ok, %{
          task_id: task.id,
          title: task.title,
          description: task.description,
          file_paths: task.file_paths,
          priority: task.priority
        }}
    end
  end

  defp complete_task(%{"agent_id" => agent_id}) do
    case Inbox.complete_current_task(agent_id) do
      {:error, reason} ->
        {:error, "Failed to complete task: #{reason}"}
      
      completed_task ->
        {:ok, %{
          task_id: completed_task.id,
          status: "completed",
          completed_at: completed_task.updated_at
        }}
    end
  end

  defp get_task_board(_args) do
    agents = TaskRegistry.list_agents()
    
    board = Enum.map(agents, fn agent ->
      status = Inbox.get_status(agent.id)
      
      %{
        agent_id: agent.id,
        name: agent.name,
        capabilities: agent.capabilities,
        status: agent.status,
        online: Agent.is_online?(agent),
        current_task: status.current_task && %{
          id: status.current_task.id,
          title: status.current_task.title
        },
        pending_tasks: status.pending_count,
        completed_tasks: status.completed_count
      }
    end)
    
    {:ok, %{agents: board}}
  end

  defp heartbeat(%{"agent_id" => agent_id}) do
    case TaskRegistry.heartbeat_agent(agent_id) do
      :ok ->
        {:ok, %{status: "heartbeat_received"}}
      
      {:error, reason} ->
        {:error, "Heartbeat failed: #{reason}"}
    end
  end
end