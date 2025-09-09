defmodule AgentCoordinator.MCPServer do
  @moduledoc """
  Unified MCP (Model Context Protocol) server for agent coordination.

  This server provides:
  - Agent coordination tools for task management and communication
  - External MCP server management and unified tool access
  - Automatic heartbeat management and session tracking
  - Cross-codebase coordination capabilities
  """

  use GenServer
  require Logger
  alias AgentCoordinator.{TaskRegistry, Inbox, Agent, Task, CodebaseRegistry, VSCodeToolProvider, ToolFilter, SessionManager, ActivityTracker}

  # State for tracking external servers and agent sessions
  defstruct [
    :external_servers,
    :server_processes,
    :tool_registry,
    :agent_sessions,
    :session_monitors,
    :server_config
  ]

  @mcp_tools [
    %{
      "name" => "register_agent",
      "description" => "Register a new agent with the coordination system. Each agent must choose a unique identifier (e.g., 'Green Platypus', 'Blue Koala') and include their agent_id in all subsequent tool calls to identify themselves.",
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
          "codebase_id" => %{"type" => "string", "description" => "If the project is found locally on the machine, use the name of the directory in which you are currently at (.). If it is remote, use the git registered codebase ID, if it is a multicodebase project, and there is no apparently folder to base as the rootmost -- ask."},
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
          "agent_id" => %{"type" => "string"},
          "id" => %{"type" => "string"},
          "name" => %{"type" => "string"},
          "workspace_path" => %{"type" => "string"},
          "description" => %{"type" => "string"},
          "metadata" => %{"type" => "object"}
        },
        "required" => ["agent_id", "name", "workspace_path"]
      }
    },
    %{
      "name" => "create_task",
      "description" => "Create a new task in the coordination system",
      "inputSchema" => %{
        "type" => "object",
        "properties" => %{
          "agent_id" => %{"type" => "string"},
          "title" => %{"type" => "string"},
          "description" => %{"type" => "string"},
          "priority" => %{"type" => "string", "enum" => ["low", "normal", "high", "urgent"]},
          "codebase_id" => %{"type" => "string", "description" => "If the project is found locally on the machine, use the name of the directory in which you are currently at (.). If it is remote, use the git registered codebase ID, if it is a multicodebase project, and there is no apparently folder to base as the rootmost -- ask."},
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
        "required" => ["agent_id", "title", "description"]
      }
    },
    %{
      "name" => "create_cross_codebase_task",
      "description" => "Create a task that spans multiple codebases",
      "inputSchema" => %{
        "type" => "object",
        "properties" => %{
          "agent_id" => %{"type" => "string"},
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
        "required" => ["agent_id", "title", "description", "primary_codebase_id", "affected_codebases"]
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
          "agent_id" => %{"type" => "string"},
          "codebase_id" => %{"type" => "string"}
        },
        "required" => ["agent_id"]
      }
    },
    %{
      "name" => "get_codebase_status",
      "description" => "Get status and statistics for a specific codebase",
      "inputSchema" => %{
        "type" => "object",
        "properties" => %{
          "agent_id" => %{"type" => "string"},
          "codebase_id" => %{"type" => "string"}
        },
        "required" => ["agent_id", "codebase_id"]
      }
    },
    %{
      "name" => "list_codebases",
      "description" => "List all registered codebases",
      "inputSchema" => %{
        "type" => "object",
        "properties" => %{
          "agent_id" => %{"type" => "string"}
        },
        "required" => ["agent_id"]
      }
    },
    %{
      "name" => "add_codebase_dependency",
      "description" => "Add a dependency relationship between codebases",
      "inputSchema" => %{
        "type" => "object",
        "properties" => %{
          "agent_id" => %{"type" => "string"},
          "source_codebase_id" => %{"type" => "string"},
          "target_codebase_id" => %{"type" => "string"},
          "dependency_type" => %{"type" => "string"},
          "metadata" => %{"type" => "object"}
        },
        "required" => ["agent_id", "source_codebase_id", "target_codebase_id", "dependency_type"]
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
          "agent_id" => %{"type" => "string"},
          "codebase_id" => %{
            "type" => "string",
            "description" => "Optional: filter by codebase ID"
          },
          "include_task_details" => %{
            "type" => "boolean",
            "default" => true,
            "description" => "Include full task details"
          }
        },
        "required" => ["agent_id"]
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
    },
    %{
      "name" => "discover_codebase_info",
      "description" => "Intelligently discover codebase information from workspace path, including git repository details, canonical ID generation, and project identification.",
      "inputSchema" => %{
        "type" => "object",
        "properties" => %{
          "agent_id" => %{"type" => "string"},
          "workspace_path" => %{
            "type" => "string",
            "description" => "Path to the workspace/project directory"
          },
          "custom_id" => %{
            "type" => "string",
            "description" => "Optional: Override automatic codebase ID detection"
          }
        },
        "required" => ["agent_id", "workspace_path"]
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

  def get_tools(client_context \\ nil) do
    case GenServer.call(__MODULE__, {:get_all_tools, client_context}, 5000) do
      tools when is_list(tools) -> tools
      _ -> @mcp_tools
    end
  end

  # Server callbacks

  def init(_opts) do
    state = %__MODULE__{
      external_servers: %{},
      server_processes: %{},
      tool_registry: %{},
      agent_sessions: %{},
      session_monitors: %{},
      server_config: load_server_config()
    }

    # Start external MCP servers
    {:ok, state, {:continue, :start_external_servers}}
  end

  def handle_continue(:start_external_servers, state) do
    IO.puts(:stderr, "Starting external MCP servers...")

    new_state =
      Enum.reduce(state.server_config.servers, state, fn {name, config}, acc ->
        case start_external_server(name, config) do
          {:ok, server_info} ->
            IO.puts(:stderr, "Started MCP server: #{name}")

            %{
              acc
              | external_servers: Map.put(acc.external_servers, name, server_info),
                server_processes: Map.put(acc.server_processes, name, server_info.pid)
            }

          {:error, reason} ->
            IO.puts(:stderr, "Failed to start MCP server #{name}: #{reason}")
            acc
        end
      end)

    # Build initial tool registry
    updated_state = refresh_external_tool_registry(new_state)

    {:noreply, updated_state}
  end

  def handle_call({:mcp_request, request}, from, state) do
    # Extract agent context for automatic heartbeat management
    case extract_agent_context(request, from, state) do
      {:error, error_message} ->
        # Return error if agent context extraction fails (unless this is an allowed system call)
        method = Map.get(request, "method")
        tool_name = Map.get(request, "params", %{}) |> Map.get("name")

        # Allow certain MCP system calls and register_agent to proceed without agent_id
        allowed_without_agent = method in ["initialize", "tools/list", "notifications/initialized"] or
          (method == "tools/call" and tool_name == "register_agent")

        IO.puts(:stderr, "#{method} #{inspect(request)} #{tool_name}")

        if allowed_without_agent do
          # Allow system calls and register_agent to proceed without agent_id
          response = process_mcp_request(request, state)
          {:reply, response, state}
        else
          # Log the rejected call for debugging
          IO.puts(:stderr, "Rejected call without agent_id: method=#{method}, tool=#{tool_name}")
          error_response = %{
            "jsonrpc" => "2.0",
            "id" => Map.get(request, "id"),
            "error" => %{
              "code" => -32602,
              "message" => error_message
            }
          }
          {:reply, error_response, state}
        end

      %{agent_id: nil} ->
        # System call without agent context
        response = process_mcp_request(request, state)
        {:reply, response, state}

      agent_context ->
        # Send pre-operation heartbeat if we have agent context
        if agent_context[:agent_id] do
          TaskRegistry.heartbeat_agent(agent_context[:agent_id])
          update_session_activity(agent_context[:agent_id])
        end

        # Process the request
        response = process_mcp_request(request, state)

        # Send post-operation heartbeat and update session activity
        if agent_context[:agent_id] do
          TaskRegistry.heartbeat_agent(agent_context[:agent_id])
          update_session_activity(agent_context[:agent_id])

          # Add heartbeat metadata to successful responses
          enhanced_response = case response do
            %{"result" => _} = success ->
              Map.put(success, "_heartbeat_metadata", %{
                agent_id: agent_context[:agent_id],
                timestamp: DateTime.utc_now()
              })
            error_result ->
              error_result
          end

          {:reply, enhanced_response, state}
        else
          {:reply, response, state}
        end
    end
  end

  def handle_call({:get_all_tools, client_context}, _from, state) do
    all_tools = get_all_unified_tools_from_state(state)

    # Apply tool filtering if client context is provided
    filtered_tools = case client_context do
      nil -> all_tools  # No filtering for nil context (backward compatibility)
      context -> ToolFilter.filter_tools(all_tools, context)
    end

    {:reply, filtered_tools, state}
  end

  def handle_call(:get_all_tools, _from, state) do
    # Backward compatibility - no filtering
    all_tools = get_all_unified_tools_from_state(state)
    {:reply, all_tools, state}
  end

  # MCP request processing

  defp process_mcp_request(%{"method" => "initialize"} = request, _state) do
    id = Map.get(request, "id", nil)

    %{
      "jsonrpc" => "2.0",
      "id" => id,
      "result" => %{
        "protocolVersion" => "2024-11-05",
        "capabilities" => %{
          "tools" => %{},
          "coordination" => %{
            "automatic_task_tracking" => true,
            "agent_management" => true,
            "multi_server_proxy" => true,
            "heartbeat_coverage" => true,
            "session_tracking" => true
          }
        },
        "serverInfo" => %{
          "name" => "agent-coordinator-unified",
          "version" => "0.1.0",
          "description" =>
            "Unified MCP server with automatic task tracking and agent coordination"
        }
      }
    }
  end

  defp process_mcp_request(%{"method" => "tools/list"} = request, state) do
    id = Map.get(request, "id", nil)

    # Get both coordinator tools and external server tools
    all_tools = get_all_unified_tools_from_state(state)

    %{
      "jsonrpc" => "2.0",
      "id" => id,
      "result" => %{"tools" => all_tools}
    }
  end

  defp process_mcp_request(%{"method" => "notifications/initialized"} = request, _state) do
    # Handle the initialized notification - this is sent by clients after initialization
    id = Map.get(request, "id", nil)

    IO.puts(:stderr, "Client initialization notification received")

    # For notifications, we typically don't send a response, but if there's an ID, respond
    if id do
      %{
        "jsonrpc" => "2.0",
        "id" => id,
        "result" => %{"status" => "acknowledged"}
      }
    else
      # For notifications without ID, no response is expected
      nil
    end
  end

  defp process_mcp_request(
         %{
           "method" => "tools/call",
           "params" => %{"name" => tool_name, "arguments" => args}
         } = request,
         state
       ) do
    id = Map.get(request, "id", nil)

    # Determine if this is a coordinator tool or external tool
    result = route_tool_call(tool_name, args, state)

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

  defp process_mcp_request(request, _state) do
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

        # Start inbox for the agent (handle already started case)
        case Inbox.start_link(agent.id) do
          {:ok, _pid} -> :ok
          {:error, {:already_started, _pid}} -> :ok
          {:error, reason} ->
            IO.puts(:stderr, "Failed to start inbox for agent #{agent.id}: #{inspect(reason)}")
            :ok
        end

        # Generate session token for the agent
        session_metadata = %{
          name: name,
          capabilities: capabilities,
          codebase_id: agent.codebase_id,
          workspace_path: opts[:workspace_path],
          registered_at: DateTime.utc_now()
        }

        case SessionManager.create_session(agent.id, session_metadata) do
          {:ok, session_token} ->
            # Track the session if we have caller info
            track_agent_session(agent.id, name, capabilities)

            {:ok, %{
              agent_id: agent.id,
              codebase_id: agent.codebase_id,
              status: "registered",
              session_token: session_token,
              expires_at: DateTime.add(DateTime.utc_now(), 60, :minute) |> DateTime.to_iso8601()
            }}

          {:error, reason} ->
            IO.puts(:stderr, "Failed to create session for agent #{agent.id}: #{inspect(reason)}")
            # Still return success but without session token for backward compatibility
            {:ok, %{agent_id: agent.id, codebase_id: agent.codebase_id, status: "registered"}}
        end

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
          current_activity: agent.current_activity,
          current_files: agent.current_files || [],
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
          current_activity: agent.current_activity,
          current_files: agent.current_files || [],
          activity_history: agent.activity_history || [],
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

  # NEW: Codebase discovery function

  defp discover_codebase_info(%{"agent_id" => agent_id, "workspace_path" => workspace_path} = args) do
    custom_id = Map.get(args, "custom_id")

    # Use the CodebaseIdentifier to analyze the workspace
    opts = if custom_id, do: [custom_id: custom_id], else: []

    case AgentCoordinator.CodebaseIdentifier.identify_codebase(workspace_path, opts) do
      codebase_info ->
        # Also check if this codebase is already registered
        existing_codebase = case CodebaseRegistry.get_codebase(codebase_info.canonical_id) do
          {:ok, codebase} -> codebase
          {:error, :not_found} -> nil
        end

        # Check for other agents working on same codebase
        agents = TaskRegistry.list_agents()
        related_agents = Enum.filter(agents, fn agent ->
          agent.codebase_id == codebase_info.canonical_id and agent.id != agent_id
        end)

        response = %{
          codebase_info: codebase_info,
          already_registered: existing_codebase != nil,
          existing_codebase: existing_codebase,
          related_agents: Enum.map(related_agents, fn agent ->
            %{
              agent_id: agent.id,
              name: agent.name,
              capabilities: agent.capabilities,
              status: agent.status,
              workspace_path: agent.workspace_path,
              online: Agent.is_online?(agent)
            }
          end),
          recommendations: generate_codebase_recommendations(codebase_info, existing_codebase, related_agents)
        }

        {:ok, response}
    end
  end

  defp generate_codebase_recommendations(codebase_info, existing_codebase, related_agents) do
    recommendations = []

    # Recommend registration if not already registered
    recommendations = if existing_codebase == nil do
      ["Consider registering this codebase with register_codebase for better coordination" | recommendations]
    else
      recommendations
    end

    # Recommend coordination if other agents are working on same codebase
    recommendations = if length(related_agents) > 0 do
      agent_names = Enum.map(related_agents, & &1.name) |> Enum.join(", ")
      ["Other agents working on this codebase: #{agent_names}. Consider coordination." | recommendations]
    else
      recommendations
    end

    # Recommend git setup if local folder without git
    recommendations = if codebase_info.identification_method == :folder_name do
      ["Consider initializing git repository for better distributed coordination" | recommendations]
    else
      recommendations
    end

    Enum.reverse(recommendations)
  end

  # External MCP server management functions

  defp start_external_server(name, %{type: :stdio} = config) do
    case start_stdio_external_server(name, config) do
      {:ok, os_pid, port, pid_file_path} ->
        # Monitor the port (not the OS PID)
        port_ref = Port.monitor(port)

        server_info = %{
          name: name,
          type: :stdio,
          # Use port as the "pid" for process tracking
          pid: port,
          os_pid: os_pid,
          port: port,
          pid_file_path: pid_file_path,
          port_ref: port_ref,
          started_at: DateTime.utc_now(),
          tools: []
        }

        # Initialize the server and get tools with shorter timeout
        case initialize_external_server(server_info) do
          {:ok, tools} ->
            {:ok, %{server_info | tools: tools}}

          {:error, reason} ->
            # Log error but don't fail - continue with empty tools
            IO.puts(:stderr, "Failed to initialize #{name}: #{reason}")
            {:ok, %{server_info | tools: []}}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp start_external_server(name, %{type: :http} = config) do
    # For HTTP servers, we don't spawn processes - just store connection info
    server_info = %{
      name: name,
      type: :http,
      url: Map.get(config, :url),
      # No process to track for HTTP
      pid: nil,
      os_pid: nil,
      port: nil,
      pid_file_path: nil,
      config: config
    }

    IO.puts(:stderr, "Registering HTTP server: #{name} at #{Map.get(config, :url)}")
    {:ok, server_info}
  end

  defp start_external_server(name, config) do
    IO.puts(:stderr, "Unsupported server type for #{name}: #{inspect(config)}")
    {:error, "Unsupported server type"}
  end

  defp start_stdio_external_server(name, config) do
    command = Map.get(config, :command, "npx")
    args = Map.get(config, :args, [])
    env = Map.get(config, :env, %{})

    # Convert env map to list format expected by Port.open
    env_list =
      Enum.map(env, fn {key, value} -> {String.to_charlist(key), String.to_charlist(value)} end)

    # Use pipe communication but allow stdin/stdout for MCP protocol
    # Remove :nouse_stdio since MCP servers need stdin/stdout to communicate
    port_options = [
      :binary,
      :stream,
      {:env, env_list},
      :exit_status,
      :hide
    ]

    try do
      port =
        Port.open(
          {:spawn_executable, System.find_executable(command)},
          [{:args, args} | port_options]
        )

      # Get the OS PID of the spawned process
      {:os_pid, os_pid} = Port.info(port, :os_pid)

      # Create PID file for cleanup
      pid_file_path = create_external_pid_file(name, os_pid)

      IO.puts(:stderr, "Started MCP server #{name} with OS PID #{os_pid}")

      {:ok, os_pid, port, pid_file_path}
    rescue
      e ->
        IO.puts(:stderr, "Failed to start stdio server #{name}: #{Exception.message(e)}")
        {:error, Exception.message(e)}
    end
  end

  defp initialize_external_server(server_info) do
    # Send initialize request
    init_request = %{
      "jsonrpc" => "2.0",
      "id" => 1,
      "method" => "initialize",
      "params" => %{
        "protocolVersion" => "2024-11-05",
        "capabilities" => %{},
        "clientInfo" => %{
          "name" => "agent-coordinator",
          "version" => "0.1.0"
        }
      }
    }

    with {:ok, _init_response} <- send_external_server_request(server_info, init_request),
         {:ok, tools_response} <- get_external_server_tools(server_info) do
      {:ok, tools_response}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp get_external_server_tools(server_info) do
    tools_request = %{
      "jsonrpc" => "2.0",
      "id" => 2,
      "method" => "tools/list"
    }

    case send_external_server_request(server_info, tools_request) do
      {:ok, %{"result" => %{"tools" => tools}}} ->
        {:ok, tools}

      {:ok, unexpected} ->
        IO.puts(:stderr, "Unexpected tools response from #{server_info.name}: #{inspect(unexpected)}")
        {:ok, []}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp send_external_server_request(server_info, request) do
    request_json = Jason.encode!(request) <> "\n"

    Port.command(server_info.port, request_json)

    # Collect full response by reading multiple lines if needed
    response_data = collect_external_response(server_info.port, "", 5_000)

    cond do
      response_data == "" ->
        {:error, "No response received from server #{server_info.name}"}

      true ->
        case Jason.decode(response_data) do
          {:ok, response} ->
            {:ok, response}

          {:error, %Jason.DecodeError{} = error} ->
            IO.puts(:stderr, "JSON decode error for server #{server_info.name}: #{Exception.message(error)}")
            {:error, "JSON decode error: #{Exception.message(error)}"}
        end
    end
  end

  defp collect_external_response(port, acc, timeout) do
    receive do
      {^port, {:data, data}} ->
        new_acc = acc <> data
        case extract_json_from_data(new_acc) do
          {json_message, _remaining} when json_message != nil ->
            json_message
          {nil, remaining} ->
            collect_external_response(port, remaining, timeout)
        end

      {^port, {:exit_status, status}} ->
        IO.puts(:stderr, "External server exited with status: #{status}")
        acc
    after
      timeout ->
        IO.puts(:stderr, "External server request timeout after #{timeout}ms")
        acc
    end
  end

  defp extract_json_from_data(data) do
    lines = String.split(data, "\n", trim: false)
    {json_lines, _remaining_data} = extract_json_lines(lines, [])

    case json_lines do
      [] ->
        last_line = List.last(lines) || ""
        if String.trim(last_line) != "" and not String.ends_with?(data, "\n") do
          {nil, last_line}
        else
          {nil, ""}
        end

      _ ->
        json_data = Enum.join(json_lines, "\n")
        case Jason.decode(json_data) do
          {:ok, _} -> {json_data, ""}
          {:error, _} -> {nil, data}
        end
    end
  end

  defp extract_json_lines([], acc), do: {Enum.reverse(acc), ""}

  defp extract_json_lines([line | rest], acc) do
    trimmed = String.trim(line)

    cond do
      trimmed == "" ->
        extract_json_lines(rest, acc)

      # Skip log messages
      Regex.match?(~r/^\d{4}-\d{2}-\d{2}\s+\d{2}:\d{2}:\d{2}/, trimmed) ->
        extract_json_lines(rest, acc)

      String.starts_with?(trimmed, ["{"]) ->
        extract_json_lines(rest, [line | acc])

      true ->
        extract_json_lines(rest, acc)
    end
  end

  defp refresh_external_tool_registry(state) do
    new_registry =
      Enum.reduce(state.external_servers, %{}, fn {name, server_info}, acc ->
        tools = Map.get(server_info, :tools, [])
        # Transform each tool to include agent_id in the schema
        transformed_tools = Enum.map(tools, &transform_external_tool_schema/1)
        Map.put(acc, name, transformed_tools)
      end)

    %{state | tool_registry: new_registry}
  end

  defp transform_external_tool_schema(tool) when is_map(tool) do
    try do
      # Get the existing input schema
      input_schema = Map.get(tool, "inputSchema", %{})

      # Get existing properties and required fields
      properties = Map.get(input_schema, "properties", %{})
      required = Map.get(input_schema, "required", [])

      # Add agent_id to properties if not already present
      updated_properties = Map.put_new(properties, "agent_id", %{
        "type" => "string",
        "description" => "ID of the agent making the tool call"
      })

      # Add agent_id to required fields if not already present
      updated_required = if "agent_id" in required do
        required
      else
        ["agent_id" | required]
      end

      # Update the input schema
      updated_schema = Map.merge(input_schema, %{
        "properties" => updated_properties,
        "required" => updated_required
      })

      # Return the tool with updated schema
      Map.put(tool, "inputSchema", updated_schema)
    rescue
      error ->
        IO.puts(:stderr, "Failed to transform tool schema for #{inspect(tool)}: #{inspect(error)}")
        tool  # Return original tool if transformation fails
    end
  end

  defp transform_external_tool_schema(tool) do
    IO.puts(:stderr, "Received non-map tool: #{inspect(tool)}")
    tool  # Return as-is if not a map
  end

  defp create_external_pid_file(server_name, os_pid) do
    pid_dir = Path.join(System.tmp_dir(), "mcp_servers")
    File.mkdir_p!(pid_dir)

    pid_file_path = Path.join(pid_dir, "#{server_name}.pid")
    File.write!(pid_file_path, to_string(os_pid))

    pid_file_path
  end

  defp get_all_unified_tools_from_state(state) do
    # Combine coordinator tools with external server tools from state
    coordinator_tools = @mcp_tools

    # Get external tools from GenServer state
    external_tools = Map.values(state.tool_registry) |> List.flatten()

    # Get VS Code tools only if VS Code functionality is available
    vscode_tools =
      try do
        if Code.ensure_loaded?(VSCodeToolProvider) do
          VSCodeToolProvider.get_tools()
        else
          IO.puts(:stderr, "VS Code tools not available - module not loaded")
          []
        end
      rescue
        error ->
          IO.puts(:stderr, "VS Code tools not available - error loading: #{inspect(error)}")
          []
      end

    coordinator_tools ++ external_tools ++ vscode_tools
  end

  defp route_tool_call(tool_name, args, state) do
    # Extract agent_id for activity tracking
    agent_id = Map.get(args, "agent_id")

    # Update agent activity before processing the tool call
    if agent_id do
      ActivityTracker.update_agent_activity(agent_id, tool_name, args)
    end

    # Check if it's a coordinator tool first
    coordinator_tool_names = Enum.map(@mcp_tools, & &1["name"])

    result = cond do
      tool_name in coordinator_tool_names ->
        handle_coordinator_tool(tool_name, args)

      # Check if it's a VS Code tool
      String.starts_with?(tool_name, "vscode_") ->
        # Route to VS Code Tool Provider with agent context
        context = if agent_id, do: %{agent_id: agent_id}, else: %{}
        VSCodeToolProvider.handle_tool_call(tool_name, args, context)

      true ->
        # Try to route to external server
        route_to_external_server(tool_name, args, state)
    end

    # Clear agent activity after tool call completes (optional - could keep until next call)
    # if agent_id do
    #   ActivityTracker.clear_agent_activity(agent_id)
    # end

    result
  end

  defp handle_coordinator_tool(tool_name, args) do
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
      "discover_codebase_info" -> discover_codebase_info(args)
      _ -> {:error, "Unknown coordinator tool: #{tool_name}"}
    end
  end

  defp route_to_external_server(tool_name, args, state) do
    # Find which external server has this tool
    server_with_tool = find_server_for_tool(tool_name, state)

    case server_with_tool do
      nil ->
        {:error, "Tool not found in any external server: #{tool_name}"}

      {server_name, server_info} ->
        # Strip agent_id from args before sending to external server
        # External servers don't expect this parameter
        external_args = Map.delete(args, "agent_id")

        # Send tool call to the external server
        tool_call_request = %{
          "jsonrpc" => "2.0",
          "id" => System.unique_integer(),
          "method" => "tools/call",
          "params" => %{
            "name" => tool_name,
            "arguments" => external_args
          }
        }

        case send_external_server_request(server_info, tool_call_request) do
          {:ok, %{"result" => result}} ->
            # Extract the actual content from the MCP response
            case result do
              %{"content" => content} when is_list(content) ->
                # Return the first text content for simplicity
                text_content = Enum.find(content, fn item ->
                  Map.get(item, "type") == "text"
                end)

                if text_content do
                  case Jason.decode(Map.get(text_content, "text", "{}")) do
                    {:ok, decoded} -> {:ok, decoded}
                    {:error, _} -> {:ok, Map.get(text_content, "text")}
                  end
                else
                  {:ok, result}
                end

              _ ->
                {:ok, result}
            end

          {:ok, %{"error" => error}} ->
            {:error, "External server error: #{inspect(error)}"}

          {:error, reason} ->
            {:error, "Failed to call external server #{server_name}: #{reason}"}
        end
    end
  end

  defp find_server_for_tool(tool_name, state) do
    # Search through all external servers for the tool
    Enum.find_value(state.external_servers, fn {server_name, server_info} ->
      tools = Map.get(server_info, :tools, [])

      if Enum.any?(tools, fn tool -> Map.get(tool, "name") == tool_name end) do
        {server_name, server_info}
      else
        nil
      end
    end)
  end

  # Session management functions

  defp track_agent_session(agent_id, name, capabilities) do
    # Store session info in process state for this session
    session_info = %{
      name: name,
      capabilities: capabilities,
      registered_at: DateTime.utc_now(),
      last_activity: DateTime.utc_now()
    }

    # Store in process dictionary for now (could be enhanced to track caller PID)
    Process.put({:agent_session, agent_id}, session_info)
  end

  defp update_session_activity(agent_id) do
    case Process.get({:agent_session, agent_id}) do
      nil -> :ok
      session_info ->
        updated_session = %{session_info | last_activity: DateTime.utc_now()}
        Process.put({:agent_session, agent_id}, updated_session)
    end
  end

  defp extract_agent_context(request, _from, _state) do
    method = Map.get(request, "method")

    # For system calls, don't require agent_id
    if method in ["initialize", "tools/list", "notifications/initialized"] do
      %{agent_id: nil}  # System call, no agent context needed
    else
      # Try to get agent_id from various sources for non-system calls
      cond do
        # From request arguments
        Map.get(request, "params", %{})
        |> Map.get("arguments", %{})
        |> Map.get("agent_id") ->
          agent_id = request["params"]["arguments"]["agent_id"]
          %{agent_id: agent_id}

        # If no explicit agent_id, return error - agents must register first
        true ->
          {:error, "Missing agent_id. Agents must register themselves using register_agent before calling other tools."}
      end
    end
  end

  defp load_server_config do
    config_file = System.get_env("MCP_CONFIG_FILE", "mcp_servers.json")

    if File.exists?(config_file) do
      try do
        case Jason.decode!(File.read!(config_file)) do
          %{"servers" => servers} ->
            normalized_servers = Enum.into(servers, %{}, fn {name, config} ->
              normalized_config = normalize_server_config(config)
              {name, normalized_config}
            end)
            %{servers: normalized_servers}
          _ ->
            get_default_server_config()
        end
      rescue
        _ -> get_default_server_config()
      end
    else
      get_default_server_config()
    end
  end

  defp normalize_server_config(config) do
    config
    |> Map.update("type", :stdio, fn
      "stdio" -> :stdio
      "http" -> :http
      type when is_atom(type) -> type
      type -> String.to_existing_atom(type)
    end)
    |> Enum.into(%{}, fn
      {"type", type} -> {:type, type}
      {key, value} -> {String.to_atom(key), value}
    end)
  end

  defp get_default_server_config do
    %{
      servers: %{
        "mcp_filesystem" => %{
          type: :stdio,
          command: "bunx",
          args: ["-y", "@modelcontextprotocol/server-filesystem", "/home/ra"],
          auto_restart: true,
          description: "Filesystem operations server"
        },
        "mcp_memory" => %{
          type: :stdio,
          command: "bunx",
          args: ["-y", "@modelcontextprotocol/server-memory"],
          auto_restart: true,
          description: "Memory and knowledge graph server"
        }
      }
    }
  end
end
