defmodule AgentCoordinator.MCPServer do
  @moduledoc """
  MCP (Model Context Protocol) server for agent coordination.
  Provides tools for agents to interact with the task coordination system.
  """

  use GenServer
  alias AgentCoordinator.{TaskRegistry, Inbox, Agent, Task, CodebaseRegistry}

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
            "items" => %{
              "type" => "string",
              "enum" => ["coding", "testing", "documentation", "analysis", "review"]
            }
          },
          "codebase_id" => %{"type" => "string"},
          "workspace_path" => %{"type" => "string"},
          "cross_codebase_capable" => %{"type" => "boolean"}
        },
        "required" => ["name", "capabilities"]
      }
    },
    %{
      "name" => "register_codebase",
      "description" => "Register a new codebase in the coordination system",
      "inputSchema" => %{
        "type" => "object",
        "properties" => %{
          "id" => %{"type" => "string"},
          "name" => %{"type" => "string"},
          "workspace_path" => %{"type" => "string"},
          "description" => %{"type" => "string"},
          "metadata" => %{"type" => "object"}
        },
        "required" => ["name", "workspace_path"]
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
          "codebase_id" => %{"type" => "string"},
          "file_paths" => %{"type" => "array", "items" => %{"type" => "string"}},
          "required_capabilities" => %{
            "type" => "array",
            "items" => %{"type" => "string"}
          },
          "cross_codebase_dependencies" => %{
            "type" => "array",
            "items" => %{
              "type" => "object",
              "properties" => %{
                "codebase_id" => %{"type" => "string"},
                "task_id" => %{"type" => "string"}
              }
            }
          }
        },
        "required" => ["title", "description"]
      }
    },
    %{
      "name" => "create_cross_codebase_task",
      "description" => "Create a task that spans multiple codebases",
      "inputSchema" => %{
        "type" => "object",
        "properties" => %{
          "title" => %{"type" => "string"},
          "description" => %{"type" => "string"},
          "primary_codebase_id" => %{"type" => "string"},
          "affected_codebases" => %{
            "type" => "array",
            "items" => %{"type" => "string"}
          },
          "coordination_strategy" => %{
            "type" => "string",
            "enum" => ["sequential", "parallel", "leader_follower"]
          }
        },
        "required" => ["title", "description", "primary_codebase_id", "affected_codebases"]
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
        "properties" => %{
          "codebase_id" => %{"type" => "string"}
        }
      }
    },
    %{
      "name" => "get_codebase_status",
      "description" => "Get status and statistics for a specific codebase",
      "inputSchema" => %{
        "type" => "object",
        "properties" => %{
          "codebase_id" => %{"type" => "string"}
        },
        "required" => ["codebase_id"]
      }
    },
    %{
      "name" => "list_codebases",
      "description" => "List all registered codebases",
      "inputSchema" => %{
        "type" => "object",
        "properties" => %{}
      }
    },
    %{
      "name" => "add_codebase_dependency",
      "description" => "Add a dependency relationship between codebases",
      "inputSchema" => %{
        "type" => "object",
        "properties" => %{
          "source_codebase_id" => %{"type" => "string"},
          "target_codebase_id" => %{"type" => "string"},
          "dependency_type" => %{"type" => "string"},
          "metadata" => %{"type" => "object"}
        },
        "required" => ["source_codebase_id", "target_codebase_id", "dependency_type"]
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
    },
    %{
      "name" => "unregister_agent",
      "description" =>
        "Unregister an agent from the coordination system (e.g., when waiting for user input)",
      "inputSchema" => %{
        "type" => "object",
        "properties" => %{
          "agent_id" => %{"type" => "string"},
          "reason" => %{"type" => "string"}
        },
        "required" => ["agent_id"]
      }
    },
    %{
      "name" => "register_task_set",
      "description" =>
        "Register a planned set of tasks for an agent to enable workflow coordination",
      "inputSchema" => %{
        "type" => "object",
        "properties" => %{
          "agent_id" => %{
            "type" => "string",
            "description" => "ID of the agent registering the task set"
          },
          "task_set" => %{
            "type" => "array",
            "description" => "Array of tasks to register for this agent",
            "items" => %{
              "type" => "object",
              "properties" => %{
                "title" => %{"type" => "string", "description" => "Task title"},
                "description" => %{"type" => "string", "description" => "Task description"},
                "priority" => %{
                  "type" => "string",
                  "enum" => ["low", "normal", "high", "urgent"],
                  "default" => "normal"
                },
                "estimated_time" => %{
                  "type" => "string",
                  "description" => "Estimated completion time"
                },
                "file_paths" => %{
                  "type" => "array",
                  "items" => %{"type" => "string"},
                  "description" => "Files this task will work on"
                },
                "required_capabilities" => %{
                  "type" => "array",
                  "items" => %{"type" => "string"},
                  "description" => "Capabilities required for this task"
                }
              },
              "required" => ["title", "description"]
            }
          }
        },
        "required" => ["agent_id", "task_set"]
      }
    },
    %{
      "name" => "create_agent_task",
      "description" =>
        "Create a task specifically for a particular agent (not globally assigned)",
      "inputSchema" => %{
        "type" => "object",
        "properties" => %{
          "agent_id" => %{"type" => "string", "description" => "ID of the agent this task is for"},
          "title" => %{"type" => "string", "description" => "Task title"},
          "description" => %{"type" => "string", "description" => "Detailed task description"},
          "priority" => %{
            "type" => "string",
            "enum" => ["low", "normal", "high", "urgent"],
            "default" => "normal"
          },
          "estimated_time" => %{"type" => "string", "description" => "Estimated completion time"},
          "file_paths" => %{
            "type" => "array",
            "items" => %{"type" => "string"},
            "description" => "Files this task will work on"
          },
          "required_capabilities" => %{
            "type" => "array",
            "items" => %{"type" => "string"},
            "description" => "Capabilities required for this task"
          }
        },
        "required" => ["agent_id", "title", "description"]
      }
    },
    %{
      "name" => "get_detailed_task_board",
      "description" =>
        "Get detailed task information for all agents including completed, current, and planned tasks",
      "inputSchema" => %{
        "type" => "object",
        "properties" => %{
          "codebase_id" => %{
            "type" => "string",
            "description" => "Optional: filter by codebase ID"
          },
          "include_task_details" => %{
            "type" => "boolean",
            "default" => true,
            "description" => "Include full task details"
          }
        }
      }
    },
    %{
      "name" => "get_agent_task_history",
      "description" => "Get detailed task history for a specific agent",
      "inputSchema" => %{
        "type" => "object",
        "properties" => %{
          "agent_id" => %{"type" => "string", "description" => "ID of the agent"},
          "include_planned" => %{
            "type" => "boolean",
            "default" => true,
            "description" => "Include planned/pending tasks"
          },
          "include_completed" => %{
            "type" => "boolean",
            "default" => true,
            "description" => "Include completed tasks"
          },
          "limit" => %{
            "type" => "number",
            "default" => 50,
            "description" => "Maximum number of tasks to return"
          }
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

  defp process_mcp_request(%{"method" => "initialize"} = request) do
    id = Map.get(request, "id", nil)

    %{
      "jsonrpc" => "2.0",
      "id" => id,
      "result" => %{
        "protocolVersion" => "2024-11-05",
        "capabilities" => %{
          "tools" => %{}
        },
        "serverInfo" => %{
          "name" => "agent-coordinator",
          "version" => "0.1.0"
        }
      }
    }
  end

  defp process_mcp_request(%{"method" => "tools/list"} = request) do
    id = Map.get(request, "id", nil)

    %{
      "jsonrpc" => "2.0",
      "id" => id,
      "result" => %{"tools" => @mcp_tools}
    }
  end

  defp process_mcp_request(
         %{
           "method" => "tools/call",
           "params" => %{"name" => tool_name, "arguments" => args}
         } = request
       ) do
    id = Map.get(request, "id", nil)

    result =
      case tool_name do
        "register_agent" -> register_agent(args)
        "register_codebase" -> register_codebase(args)
        "create_task" -> create_task(args)
        "create_cross_codebase_task" -> create_cross_codebase_task(args)
        "get_next_task" -> get_next_task(args)
        "complete_task" -> complete_task(args)
        "get_task_board" -> get_task_board(args)
        "get_codebase_status" -> get_codebase_status(args)
        "list_codebases" -> list_codebases(args)
        "add_codebase_dependency" -> add_codebase_dependency(args)
        "heartbeat" -> heartbeat(args)
        "unregister_agent" -> unregister_agent(args)
        "register_task_set" -> register_task_set(args)
        "create_agent_task" -> create_agent_task(args)
        "get_detailed_task_board" -> get_detailed_task_board(args)
        "get_agent_task_history" -> get_agent_task_history(args)
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

  defp process_mcp_request(request) do
    id = Map.get(request, "id", nil)

    %{
      "jsonrpc" => "2.0",
      "id" => id,
      "error" => %{"code" => -32601, "message" => "Method not found"}
    }
  end

  # Tool implementations

  defp register_agent(%{"name" => name, "capabilities" => capabilities} = args) do
    caps = Enum.map(capabilities, &String.to_atom/1)

    opts = [
      codebase_id: Map.get(args, "codebase_id", "default"),
      workspace_path: Map.get(args, "workspace_path"),
      metadata: %{
        cross_codebase_capable: Map.get(args, "cross_codebase_capable", false)
      }
    ]

    agent = Agent.new(name, caps, opts)

    case TaskRegistry.register_agent(agent) do
      :ok ->
        # Add agent to codebase registry
        CodebaseRegistry.add_agent_to_codebase(agent.codebase_id, agent.id)

        # Start inbox for the agent
        {:ok, _pid} = Inbox.start_link(agent.id)
        {:ok, %{agent_id: agent.id, codebase_id: agent.codebase_id, status: "registered"}}

      {:error, reason} ->
        {:error, "Failed to register agent: #{reason}"}
    end
  end

  defp register_codebase(args) do
    case CodebaseRegistry.register_codebase(args) do
      {:ok, codebase_id} ->
        {:ok, %{codebase_id: codebase_id, status: "registered"}}

      {:error, reason} ->
        {:error, "Failed to register codebase: #{reason}"}
    end
  end

  defp create_task(%{"title" => title, "description" => description} = args) do
    opts = [
      priority: String.to_atom(Map.get(args, "priority", "normal")),
      codebase_id: Map.get(args, "codebase_id", "default"),
      file_paths: Map.get(args, "file_paths", []),
      cross_codebase_dependencies: Map.get(args, "cross_codebase_dependencies", []),
      metadata: %{
        required_capabilities: Map.get(args, "required_capabilities", [])
      }
    ]

    task = Task.new(title, description, opts)

    case TaskRegistry.assign_task(task) do
      {:ok, agent_id} ->
        {:ok,
         %{
           task_id: task.id,
           assigned_to: agent_id,
           codebase_id: task.codebase_id,
           status: "assigned"
         }}

      {:error, :no_available_agents} ->
        # Add to global pending queue
        TaskRegistry.add_to_pending(task)
        {:ok, %{task_id: task.id, codebase_id: task.codebase_id, status: "queued"}}
    end
  end

  defp create_cross_codebase_task(%{"title" => title, "description" => description} = args) do
    primary_codebase = Map.get(args, "primary_codebase_id")
    affected_codebases = Map.get(args, "affected_codebases", [])
    strategy = Map.get(args, "coordination_strategy", "sequential")

    # Create main task in primary codebase
    main_task_opts = [
      codebase_id: primary_codebase,
      metadata: %{
        cross_codebase_task: true,
        coordination_strategy: strategy,
        affected_codebases: affected_codebases
      }
    ]

    main_task = Task.new(title, description, main_task_opts)

    # Create dependent tasks in other codebases
    dependent_tasks =
      Enum.map(affected_codebases, fn codebase_id ->
        if codebase_id != primary_codebase do
          dependent_opts = [
            codebase_id: codebase_id,
            cross_codebase_dependencies: [%{codebase_id: primary_codebase, task_id: main_task.id}],
            metadata: %{
              cross_codebase_task: true,
              primary_task_id: main_task.id,
              coordination_strategy: strategy
            }
          ]

          Task.new(
            "#{title} (#{codebase_id})",
            "Cross-codebase task: #{description}",
            dependent_opts
          )
        end
      end)
      |> Enum.filter(&(&1 != nil))

    # Try to assign all tasks
    all_tasks = [main_task | dependent_tasks]

    results =
      Enum.map(all_tasks, fn task ->
        case TaskRegistry.assign_task(task) do
          {:ok, agent_id} ->
            %{
              task_id: task.id,
              codebase_id: task.codebase_id,
              agent_id: agent_id,
              status: "assigned"
            }

          {:error, :no_available_agents} ->
            TaskRegistry.add_to_pending(task)
            %{task_id: task.id, codebase_id: task.codebase_id, status: "queued"}
        end
      end)

    {:ok,
     %{
       main_task_id: main_task.id,
       primary_codebase: primary_codebase,
       coordination_strategy: strategy,
       tasks: results,
       status: "created"
     }}
  end

  defp get_next_task(%{"agent_id" => agent_id}) do
    case Inbox.get_next_task(agent_id) do
      nil ->
        {:ok, %{message: "No tasks available"}}

      task ->
        {:ok,
         %{
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
        {:ok,
         %{
           task_id: completed_task.id,
           status: "completed",
           completed_at: completed_task.updated_at
         }}
    end
  end

  defp get_task_board(args) do
    codebase_id = Map.get(args, "codebase_id")
    agents = TaskRegistry.list_agents()

    # Filter agents by codebase if specified
    filtered_agents =
      case codebase_id do
        nil -> agents
        id -> Enum.filter(agents, fn agent -> agent.codebase_id == id end)
      end

    board =
      Enum.map(filtered_agents, fn agent ->
        status = Inbox.get_status(agent.id)

        %{
          agent_id: agent.id,
          name: agent.name,
          capabilities: agent.capabilities,
          status: agent.status,
          codebase_id: agent.codebase_id,
          workspace_path: agent.workspace_path,
          online: Agent.is_online?(agent),
          cross_codebase_capable: Agent.can_work_cross_codebase?(agent),
          current_task:
            status.current_task &&
              %{
                id: status.current_task.id,
                title: status.current_task.title,
                codebase_id: status.current_task.codebase_id
              },
          pending_tasks: status.pending_count,
          completed_tasks: status.completed_count
        }
      end)

    {:ok, %{agents: board, codebase_filter: codebase_id}}
  end

  defp get_codebase_status(%{"codebase_id" => codebase_id}) do
    case CodebaseRegistry.get_codebase_stats(codebase_id) do
      {:ok, stats} ->
        {:ok, stats}

      {:error, reason} ->
        {:error, "Failed to get codebase status: #{reason}"}
    end
  end

  defp list_codebases(_args) do
    codebases = CodebaseRegistry.list_codebases()

    codebase_summaries =
      Enum.map(codebases, fn codebase ->
        %{
          id: codebase.id,
          name: codebase.name,
          workspace_path: codebase.workspace_path,
          description: codebase.description,
          agent_count: length(codebase.agents),
          active_task_count: length(codebase.active_tasks),
          created_at: codebase.created_at,
          updated_at: codebase.updated_at
        }
      end)

    {:ok, %{codebases: codebase_summaries}}
  end

  defp add_codebase_dependency(
         %{
           "source_codebase_id" => source,
           "target_codebase_id" => target,
           "dependency_type" => dep_type
         } = args
       ) do
    metadata = Map.get(args, "metadata", %{})

    case CodebaseRegistry.add_cross_codebase_dependency(source, target, dep_type, metadata) do
      :ok ->
        {:ok,
         %{
           source_codebase: source,
           target_codebase: target,
           dependency_type: dep_type,
           status: "added"
         }}

      {:error, reason} ->
        {:error, "Failed to add dependency: #{reason}"}
    end
  end

  defp heartbeat(%{"agent_id" => agent_id}) do
    case TaskRegistry.heartbeat_agent(agent_id) do
      :ok ->
        {:ok, %{status: "heartbeat_received"}}

      {:error, reason} ->
        {:error, "Heartbeat failed: #{reason}"}
    end
  end

  defp unregister_agent(%{"agent_id" => agent_id} = args) do
    reason = Map.get(args, "reason", "Agent unregistered")

    case TaskRegistry.unregister_agent(agent_id, reason) do
      :ok ->
        {:ok, %{status: "agent_unregistered", agent_id: agent_id, reason: reason}}

      {:error, reason} ->
        {:error, "Unregister failed: #{reason}"}
    end
  end

  # NEW: Agent-specific task management functions

  defp register_task_set(%{"agent_id" => agent_id, "task_set" => task_set}) do
    case TaskRegistry.get_agent(agent_id) do
      {:error, :not_found} ->
        {:error, "Agent not found: #{agent_id}"}

      {:ok, _agent} ->
        # Create tasks specifically for this agent
        created_tasks =
          Enum.map(task_set, fn task_data ->
            opts = %{
              priority: String.to_atom(Map.get(task_data, "priority", "normal")),
              # Use agent's codebase
              codebase_id: "default",
              file_paths: Map.get(task_data, "file_paths", []),
              metadata: %{
                agent_created: true,
                estimated_time: Map.get(task_data, "estimated_time"),
                required_capabilities: Map.get(task_data, "required_capabilities", [])
              }
            }

            task = Task.new(task_data["title"], task_data["description"], opts)

            # Add directly to agent's inbox (not global pool)
            case Inbox.add_task(agent_id, task) do
              :ok -> task
              {:error, reason} -> {:error, reason}
            end
          end)

        # Check for any errors
        case Enum.find(created_tasks, fn result -> match?({:error, _}, result) end) do
          nil ->
            task_summaries =
              Enum.map(created_tasks, fn task ->
                %{
                  task_id: task.id,
                  title: task.title,
                  priority: task.priority,
                  estimated_time: task.metadata[:estimated_time]
                }
              end)

            {:ok,
             %{
               agent_id: agent_id,
               registered_tasks: length(created_tasks),
               task_set: task_summaries,
               status: "registered"
             }}

          {:error, reason} ->
            {:error, "Failed to register task set: #{reason}"}
        end
    end
  end

  defp create_agent_task(
         %{"agent_id" => agent_id, "title" => title, "description" => description} = args
       ) do
    case TaskRegistry.get_agent(agent_id) do
      {:error, :not_found} ->
        {:error, "Agent not found: #{agent_id}"}

      {:ok, _agent} ->
        opts = %{
          priority: String.to_atom(Map.get(args, "priority", "normal")),
          # Use agent's codebase
          codebase_id: "default",
          file_paths: Map.get(args, "file_paths", []),
          metadata: %{
            agent_created: true,
            estimated_time: Map.get(args, "estimated_time"),
            required_capabilities: Map.get(args, "required_capabilities", [])
          }
        }

        task = Task.new(title, description, opts)

        # Add directly to agent's inbox
        case Inbox.add_task(agent_id, task) do
          :ok ->
            {:ok,
             %{
               task_id: task.id,
               agent_id: agent_id,
               title: task.title,
               priority: task.priority,
               status: "created_for_agent"
             }}

          {:error, reason} ->
            {:error, "Failed to create agent task: #{reason}"}
        end
    end
  end

  defp get_detailed_task_board(args) do
    codebase_id = Map.get(args, "codebase_id")
    include_details = Map.get(args, "include_task_details", true)
    agents = TaskRegistry.list_agents()

    # Filter agents by codebase if specified
    filtered_agents =
      case codebase_id do
        nil -> agents
        id -> Enum.filter(agents, fn agent -> agent.codebase_id == id end)
      end

    detailed_board =
      Enum.map(filtered_agents, fn agent ->
        # Get detailed task information
        task_info =
          case Inbox.list_tasks(agent.id) do
            {:error, _} ->
              %{pending: [], in_progress: nil, completed: []}

            tasks ->
              if include_details do
                tasks
              else
                # Just counts like before
                %{
                  pending_count: length(tasks.pending),
                  in_progress: if(tasks.in_progress, do: 1, else: 0),
                  completed_count: length(tasks.completed)
                }
              end
          end

        %{
          agent_id: agent.id,
          name: agent.name,
          capabilities: agent.capabilities,
          status: agent.status,
          codebase_id: agent.codebase_id,
          workspace_path: agent.workspace_path,
          online: Agent.is_online?(agent),
          cross_codebase_capable: Agent.can_work_cross_codebase?(agent),
          last_heartbeat: agent.last_heartbeat,
          tasks: task_info
        }
      end)

    {:ok,
     %{
       agents: detailed_board,
       codebase_filter: codebase_id,
       timestamp: DateTime.utc_now()
     }}
  end

  defp get_agent_task_history(%{"agent_id" => agent_id} = args) do
    include_planned = Map.get(args, "include_planned", true)
    include_completed = Map.get(args, "include_completed", true)
    limit = Map.get(args, "limit", 50)

    case TaskRegistry.get_agent(agent_id) do
      {:error, :not_found} ->
        {:error, "Agent not found: #{agent_id}"}

      {:ok, agent} ->
        case Inbox.list_tasks(agent_id) do
          {:error, reason} ->
            {:error, "Failed to get task history: #{reason}"}

          task_data ->
            history = %{}

            # Add planned tasks if requested
            history =
              if include_planned do
                Map.put(history, :planned_tasks, Enum.take(task_data.pending, limit))
              else
                history
              end

            # Add current task
            history =
              if task_data.in_progress do
                Map.put(history, :current_task, task_data.in_progress)
              else
                history
              end

            # Add completed tasks if requested
            history =
              if include_completed do
                Map.put(history, :completed_tasks, Enum.take(task_data.completed, limit))
              else
                history
              end

            {:ok,
             %{
               agent_id: agent_id,
               agent_name: agent.name,
               history: history,
               total_planned: length(task_data.pending),
               total_completed: length(task_data.completed),
               timestamp: DateTime.utc_now()
             }}
        end
    end
  end
end
