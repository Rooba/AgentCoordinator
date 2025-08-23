defmodule AgentCoordinator.MCPServerTest do
  use ExUnit.Case, async: false
  alias AgentCoordinator.{MCPServer, TaskRegistry, Agent, Task, Inbox}

  setup do
    # Clean up any existing named processes safely
    if Process.whereis(MCPServer), do: GenServer.stop(MCPServer, :normal, 1000)
    if Process.whereis(TaskRegistry), do: GenServer.stop(TaskRegistry, :normal, 1000)

    if Process.whereis(AgentCoordinator.PubSub),
      do: GenServer.stop(AgentCoordinator.PubSub, :normal, 1000)

    if Process.whereis(AgentCoordinator.InboxSupervisor),
      do: DynamicSupervisor.stop(AgentCoordinator.InboxSupervisor, :normal, 1000)

    # Registry has to be handled differently
    case Process.whereis(AgentCoordinator.InboxRegistry) do
      nil ->
        :ok

      pid ->
        Process.unlink(pid)
        Process.exit(pid, :kill)
    end

    # Wait a bit for processes to terminate
    Process.sleep(200)

    # Start fresh components needed for testing (without NATS)
    start_supervised!({Registry, keys: :unique, name: AgentCoordinator.InboxRegistry})
    start_supervised!({Phoenix.PubSub, name: AgentCoordinator.PubSub})

    start_supervised!(
      {DynamicSupervisor, name: AgentCoordinator.InboxSupervisor, strategy: :one_for_one}
    )

    # Start task registry without NATS for testing
    # Empty map for no NATS connection
    start_supervised!({TaskRegistry, nats: %{}})
    start_supervised!(MCPServer)

    :ok
  end

  describe "MCP protocol compliance" do
    test "returns tools list for tools/list method" do
      request = %{"method" => "tools/list", "jsonrpc" => "2.0", "id" => 1}

      response = MCPServer.handle_mcp_request(request)

      assert %{"jsonrpc" => "2.0", "result" => %{"tools" => tools}} = response
      assert is_list(tools)
      assert length(tools) == 6

      # Check that all expected tools are present
      tool_names = Enum.map(tools, & &1["name"])

      expected_tools = [
        "register_agent",
        "create_task",
        "get_next_task",
        "complete_task",
        "get_task_board",
        "heartbeat"
      ]

      for tool_name <- expected_tools do
        assert tool_name in tool_names, "Missing tool: #{tool_name}"
      end
    end

    test "returns error for unknown method" do
      request = %{"method" => "unknown/method", "jsonrpc" => "2.0", "id" => 1}

      response = MCPServer.handle_mcp_request(request)

      assert %{
               "jsonrpc" => "2.0",
               "error" => %{"code" => -32601, "message" => "Method not found"}
             } = response
    end

    test "returns error for unknown tool" do
      request = %{
        "method" => "tools/call",
        "params" => %{"name" => "unknown_tool", "arguments" => %{}},
        "jsonrpc" => "2.0",
        "id" => 1
      }

      response = MCPServer.handle_mcp_request(request)

      assert %{
               "jsonrpc" => "2.0",
               "id" => 1,
               "error" => %{"code" => -1, "message" => "Unknown tool: unknown_tool"}
             } = response
    end
  end

  describe "register_agent tool" do
    test "successfully registers an agent with valid capabilities" do
      request = %{
        "method" => "tools/call",
        "params" => %{
          "name" => "register_agent",
          "arguments" => %{
            "name" => "TestAgent",
            "capabilities" => ["coding", "testing"]
          }
        },
        "jsonrpc" => "2.0",
        "id" => 1
      }

      response = MCPServer.handle_mcp_request(request)

      assert %{
               "jsonrpc" => "2.0",
               "id" => 1,
               "result" => %{"content" => [%{"type" => "text", "text" => text}]}
             } = response

      data = Jason.decode!(text)
      assert %{"agent_id" => agent_id, "status" => "registered"} = data
      assert is_binary(agent_id)

      # Verify agent is in registry
      agents = TaskRegistry.list_agents()
      assert Enum.any?(agents, fn agent -> agent.id == agent_id and agent.name == "TestAgent" end)
    end

    test "fails to register agent with duplicate name" do
      # Register first agent
      args1 = %{"name" => "DuplicateAgent", "capabilities" => ["coding"]}

      request1 = %{
        "method" => "tools/call",
        "params" => %{"name" => "register_agent", "arguments" => args1},
        "jsonrpc" => "2.0",
        "id" => 1
      }

      MCPServer.handle_mcp_request(request1)

      # Try to register second agent with same name
      args2 = %{"name" => "DuplicateAgent", "capabilities" => ["testing"]}

      request2 = %{
        "method" => "tools/call",
        "params" => %{"name" => "register_agent", "arguments" => args2},
        "jsonrpc" => "2.0",
        "id" => 2
      }

      response = MCPServer.handle_mcp_request(request2)

      assert %{"jsonrpc" => "2.0", "id" => 2, "error" => %{"code" => -1, "message" => message}} =
               response

      assert String.contains?(message, "Agent name already exists")
    end
  end

  describe "create_task tool" do
    setup do
      # Register an agent for task assignment
      agent = Agent.new("TaskAgent", [:coding, :testing])
      TaskRegistry.register_agent(agent)
      Inbox.start_link(agent.id)

      %{agent_id: agent.id}
    end

    test "successfully creates and assigns task to available agent", %{agent_id: agent_id} do
      request = %{
        "method" => "tools/call",
        "params" => %{
          "name" => "create_task",
          "arguments" => %{
            "title" => "Test Task",
            "description" => "A test task description",
            "priority" => "high",
            "file_paths" => ["test.ex"],
            "required_capabilities" => ["coding"]
          }
        },
        "jsonrpc" => "2.0",
        "id" => 1
      }

      response = MCPServer.handle_mcp_request(request)

      assert %{
               "jsonrpc" => "2.0",
               "id" => 1,
               "result" => %{"content" => [%{"type" => "text", "text" => text}]}
             } = response

      data = Jason.decode!(text)
      assert %{"task_id" => task_id, "assigned_to" => ^agent_id, "status" => "assigned"} = data
      assert is_binary(task_id)
    end

    test "queues task when no agents available" do
      # Don't register any agents
      request = %{
        "method" => "tools/call",
        "params" => %{
          "name" => "create_task",
          "arguments" => %{
            "title" => "Queued Task",
            "description" => "This task will be queued"
          }
        },
        "jsonrpc" => "2.0",
        "id" => 1
      }

      response = MCPServer.handle_mcp_request(request)

      assert %{
               "jsonrpc" => "2.0",
               "id" => 1,
               "result" => %{"content" => [%{"type" => "text", "text" => text}]}
             } = response

      data = Jason.decode!(text)
      assert %{"task_id" => task_id, "status" => "queued"} = data
      assert is_binary(task_id)
    end

    test "creates task with minimum required fields" do
      request = %{
        "method" => "tools/call",
        "params" => %{
          "name" => "create_task",
          "arguments" => %{
            "title" => "Minimal Task",
            "description" => "Minimal task description"
          }
        },
        "jsonrpc" => "2.0",
        "id" => 1
      }

      response = MCPServer.handle_mcp_request(request)

      assert %{
               "jsonrpc" => "2.0",
               "id" => 1,
               "result" => %{"content" => [%{"type" => "text", "text" => text}]}
             } = response

      data = Jason.decode!(text)
      assert %{"task_id" => task_id} = data
      assert is_binary(task_id)
    end
  end

  describe "get_next_task tool" do
    setup do
      # Register agent and create a task
      agent = Agent.new("WorkerAgent", [:coding])
      TaskRegistry.register_agent(agent)
      Inbox.start_link(agent.id)

      task = Task.new("Work Task", "Some work to do", priority: :high)
      Inbox.add_task(agent.id, task)

      %{agent_id: agent.id, task_id: task.id}
    end

    test "returns next task for agent with pending tasks", %{agent_id: agent_id, task_id: task_id} do
      request = %{
        "method" => "tools/call",
        "params" => %{
          "name" => "get_next_task",
          "arguments" => %{"agent_id" => agent_id}
        },
        "jsonrpc" => "2.0",
        "id" => 1
      }

      response = MCPServer.handle_mcp_request(request)

      assert %{
               "jsonrpc" => "2.0",
               "id" => 1,
               "result" => %{"content" => [%{"type" => "text", "text" => text}]}
             } = response

      data = Jason.decode!(text)

      assert %{
               "task_id" => ^task_id,
               "title" => "Work Task",
               "description" => "Some work to do",
               "priority" => "high"
             } = data
    end

    test "returns no tasks message when no pending tasks", %{agent_id: agent_id} do
      # First get the task to make inbox empty
      Inbox.get_next_task(agent_id)

      request = %{
        "method" => "tools/call",
        "params" => %{
          "name" => "get_next_task",
          "arguments" => %{"agent_id" => agent_id}
        },
        "jsonrpc" => "2.0",
        "id" => 1
      }

      response = MCPServer.handle_mcp_request(request)

      assert %{
               "jsonrpc" => "2.0",
               "id" => 1,
               "result" => %{"content" => [%{"type" => "text", "text" => text}]}
             } = response

      data = Jason.decode!(text)
      assert %{"message" => "No tasks available"} = data
    end
  end

  describe "complete_task tool" do
    setup do
      # Setup agent with a task in progress
      agent = Agent.new("CompletionAgent", [:coding])
      TaskRegistry.register_agent(agent)
      Inbox.start_link(agent.id)

      task = Task.new("Complete Me", "Task to complete")
      Inbox.add_task(agent.id, task)
      # Start the task
      completed_task = Inbox.get_next_task(agent.id)

      %{agent_id: agent.id, task_id: completed_task.id}
    end

    test "successfully completes current task", %{agent_id: agent_id, task_id: task_id} do
      request = %{
        "method" => "tools/call",
        "params" => %{
          "name" => "complete_task",
          "arguments" => %{"agent_id" => agent_id}
        },
        "jsonrpc" => "2.0",
        "id" => 1
      }

      response = MCPServer.handle_mcp_request(request)

      assert %{
               "jsonrpc" => "2.0",
               "id" => 1,
               "result" => %{"content" => [%{"type" => "text", "text" => text}]}
             } = response

      data = Jason.decode!(text)

      assert %{
               "task_id" => ^task_id,
               "status" => "completed",
               "completed_at" => completed_at
             } = data

      assert is_binary(completed_at)
    end

    test "fails when no task in progress" do
      # Register agent without starting any tasks
      agent = Agent.new("IdleAgent", [:coding])
      TaskRegistry.register_agent(agent)
      Inbox.start_link(agent.id)

      request = %{
        "method" => "tools/call",
        "params" => %{
          "name" => "complete_task",
          "arguments" => %{"agent_id" => agent.id}
        },
        "jsonrpc" => "2.0",
        "id" => 1
      }

      response = MCPServer.handle_mcp_request(request)

      assert %{"jsonrpc" => "2.0", "id" => 1, "error" => %{"code" => -1, "message" => message}} =
               response

      assert String.contains?(message, "no_task_in_progress")
    end
  end

  describe "get_task_board tool" do
    setup do
      # Register multiple agents with different states
      agent1 = Agent.new("BusyAgent", [:coding])
      agent2 = Agent.new("IdleAgent", [:testing])

      TaskRegistry.register_agent(agent1)
      TaskRegistry.register_agent(agent2)

      Inbox.start_link(agent1.id)
      Inbox.start_link(agent2.id)

      # Add task to first agent
      task = Task.new("Busy Work", "Work in progress")
      Inbox.add_task(agent1.id, task)
      # Start the task
      Inbox.get_next_task(agent1.id)

      %{agent1_id: agent1.id, agent2_id: agent2.id}
    end

    test "returns status of all agents", %{agent1_id: agent1_id, agent2_id: agent2_id} do
      request = %{
        "method" => "tools/call",
        "params" => %{
          "name" => "get_task_board",
          "arguments" => %{}
        },
        "jsonrpc" => "2.0",
        "id" => 1
      }

      response = MCPServer.handle_mcp_request(request)

      assert %{
               "jsonrpc" => "2.0",
               "id" => 1,
               "result" => %{"content" => [%{"type" => "text", "text" => text}]}
             } = response

      data = Jason.decode!(text)
      assert %{"agents" => agents} = data
      assert length(agents) == 2

      # Find agents by ID
      busy_agent = Enum.find(agents, fn agent -> agent["agent_id"] == agent1_id end)
      idle_agent = Enum.find(agents, fn agent -> agent["agent_id"] == agent2_id end)

      assert busy_agent["name"] == "BusyAgent"
      assert busy_agent["capabilities"] == ["coding"]
      assert busy_agent["current_task"]["title"] == "Busy Work"

      assert idle_agent["name"] == "IdleAgent"
      assert idle_agent["capabilities"] == ["testing"]
      assert is_nil(idle_agent["current_task"])
    end
  end

  describe "heartbeat tool" do
    setup do
      agent = Agent.new("HeartbeatAgent", [:coding])
      TaskRegistry.register_agent(agent)

      %{agent_id: agent.id}
    end

    test "successfully processes heartbeat for registered agent", %{agent_id: agent_id} do
      request = %{
        "method" => "tools/call",
        "params" => %{
          "name" => "heartbeat",
          "arguments" => %{"agent_id" => agent_id}
        },
        "jsonrpc" => "2.0",
        "id" => 1
      }

      response = MCPServer.handle_mcp_request(request)

      assert %{
               "jsonrpc" => "2.0",
               "id" => 1,
               "result" => %{"content" => [%{"type" => "text", "text" => text}]}
             } = response

      data = Jason.decode!(text)
      assert %{"status" => "heartbeat_received"} = data
    end

    test "fails heartbeat for non-existent agent" do
      request = %{
        "method" => "tools/call",
        "params" => %{
          "name" => "heartbeat",
          "arguments" => %{"agent_id" => "non-existent-id"}
        },
        "jsonrpc" => "2.0",
        "id" => 1
      }

      response = MCPServer.handle_mcp_request(request)

      assert %{"jsonrpc" => "2.0", "id" => 1, "error" => %{"code" => -1, "message" => message}} =
               response

      assert String.contains?(message, "agent_not_found")
    end
  end

  describe "full workflow integration" do
    test "complete agent coordination workflow" do
      # 1. Register an agent
      register_request = %{
        "method" => "tools/call",
        "params" => %{
          "name" => "register_agent",
          "arguments" => %{
            "name" => "WorkflowAgent",
            "capabilities" => ["coding", "testing"]
          }
        },
        "jsonrpc" => "2.0",
        "id" => 1
      }

      register_response = MCPServer.handle_mcp_request(register_request)

      register_data =
        register_response["result"]["content"]
        |> List.first()
        |> Map.get("text")
        |> Jason.decode!()

      agent_id = register_data["agent_id"]

      # 2. Create a task
      create_request = %{
        "method" => "tools/call",
        "params" => %{
          "name" => "create_task",
          "arguments" => %{
            "title" => "Workflow Task",
            "description" => "Complete workflow test",
            "priority" => "high",
            "required_capabilities" => ["coding"]
          }
        },
        "jsonrpc" => "2.0",
        "id" => 2
      }

      create_response = MCPServer.handle_mcp_request(create_request)

      create_data =
        create_response["result"]["content"] |> List.first() |> Map.get("text") |> Jason.decode!()

      task_id = create_data["task_id"]

      assert create_data["assigned_to"] == agent_id

      # 3. Get the task
      get_request = %{
        "method" => "tools/call",
        "params" => %{
          "name" => "get_next_task",
          "arguments" => %{"agent_id" => agent_id}
        },
        "jsonrpc" => "2.0",
        "id" => 3
      }

      get_response = MCPServer.handle_mcp_request(get_request)

      get_data =
        get_response["result"]["content"] |> List.first() |> Map.get("text") |> Jason.decode!()

      assert get_data["task_id"] == task_id
      assert get_data["title"] == "Workflow Task"

      # 4. Check task board
      board_request = %{
        "method" => "tools/call",
        "params" => %{
          "name" => "get_task_board",
          "arguments" => %{}
        },
        "jsonrpc" => "2.0",
        "id" => 4
      }

      board_response = MCPServer.handle_mcp_request(board_request)

      board_data =
        board_response["result"]["content"] |> List.first() |> Map.get("text") |> Jason.decode!()

      agent_status = board_data["agents"] |> List.first()
      assert agent_status["agent_id"] == agent_id
      assert agent_status["current_task"]["id"] == task_id

      # 5. Complete the task
      complete_request = %{
        "method" => "tools/call",
        "params" => %{
          "name" => "complete_task",
          "arguments" => %{"agent_id" => agent_id}
        },
        "jsonrpc" => "2.0",
        "id" => 5
      }

      complete_response = MCPServer.handle_mcp_request(complete_request)

      complete_data =
        complete_response["result"]["content"]
        |> List.first()
        |> Map.get("text")
        |> Jason.decode!()

      assert complete_data["task_id"] == task_id
      assert complete_data["status"] == "completed"

      # 6. Verify task board shows completed state
      final_board_response = MCPServer.handle_mcp_request(board_request)

      final_board_data =
        final_board_response["result"]["content"]
        |> List.first()
        |> Map.get("text")
        |> Jason.decode!()

      final_agent_status = final_board_data["agents"] |> List.first()
      assert is_nil(final_agent_status["current_task"])
      assert final_agent_status["completed_tasks"] == 1
    end
  end
end
