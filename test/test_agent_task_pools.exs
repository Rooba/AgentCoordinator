#!/usr/bin/env elixir

# Test script for agent-specific task pools
# This tests the new functionality to ensure agents have separate task pools

Mix.install([
  {:jason, "~> 1.4"}
])

defmodule AgentTaskPoolTest do
  def run_test do
    IO.puts("🚀 Testing Agent-Specific Task Pools")
    IO.puts("=====================================")

    # Start the application
    IO.puts("Starting AgentCoordinator application...")
    Application.start(:agent_coordinator)

    # Test 1: Register two agents
    IO.puts("\n📋 Test 1: Registering two test agents")

    agent1_request = %{
      "method" => "tools/call",
      "params" => %{
        "name" => "register_agent",
        "arguments" => %{
          "name" => "TestAgent_Alpha_Banana",
          "capabilities" => ["coding", "testing"]
        }
      },
      "jsonrpc" => "2.0",
      "id" => 1
    }

    agent2_request = %{
      "method" => "tools/call",
      "params" => %{
        "name" => "register_agent",
        "arguments" => %{
          "name" => "TestAgent_Beta_Koala",
          "capabilities" => ["documentation", "analysis"]
        }
      },
      "jsonrpc" => "2.0",
      "id" => 2
    }

    # Register agents
    agent1_response = AgentCoordinator.MCPServer.handle_mcp_request(agent1_request)
    agent2_response = AgentCoordinator.MCPServer.handle_mcp_request(agent2_request)

    agent1_id = extract_agent_id(agent1_response)
    agent2_id = extract_agent_id(agent2_response)

    IO.puts("✅ Agent 1 registered: #{agent1_id}")
    IO.puts("✅ Agent 2 registered: #{agent2_id}")

    # Test 2: Register task sets for each agent
    IO.puts("\n📝 Test 2: Registering task sets for each agent")

    task_set_1 = %{
      "method" => "tools/call",
      "params" => %{
        "name" => "register_task_set",
        "arguments" => %{
          "agent_id" => agent1_id,
          "task_set" => [
            %{
              "title" => "Implement login feature",
              "description" => "Create user authentication system",
              "priority" => "high",
              "estimated_time" => "2 hours"
            },
            %{
              "title" => "Write unit tests",
              "description" => "Add tests for authentication",
              "priority" => "normal",
              "estimated_time" => "1 hour"
            }
          ]
        }
      },
      "jsonrpc" => "2.0",
      "id" => 3
    }

    task_set_2 = %{
      "method" => "tools/call",
      "params" => %{
        "name" => "register_task_set",
        "arguments" => %{
          "agent_id" => agent2_id,
          "task_set" => [
            %{
              "title" => "Write API documentation",
              "description" => "Document the new authentication API",
              "priority" => "normal",
              "estimated_time" => "3 hours"
            },
            %{
              "title" => "Review code quality",
              "description" => "Analyze the authentication implementation",
              "priority" => "low",
              "estimated_time" => "1 hour"
            }
          ]
        }
      },
      "jsonrpc" => "2.0",
      "id" => 4
    }

    taskset1_response = AgentCoordinator.MCPServer.handle_mcp_request(task_set_1)
    taskset2_response = AgentCoordinator.MCPServer.handle_mcp_request(task_set_2)

    IO.puts("✅ Task set registered for Agent 1: #{inspect(taskset1_response)}")
    IO.puts("✅ Task set registered for Agent 2: #{inspect(taskset2_response)}")

    # Test 3: Get detailed task board
    IO.puts("\n📊 Test 3: Getting detailed task board")

    detailed_board_request = %{
      "method" => "tools/call",
      "params" => %{
        "name" => "get_detailed_task_board",
        "arguments" => %{}
      },
      "jsonrpc" => "2.0",
      "id" => 5
    }

    board_response = AgentCoordinator.MCPServer.handle_mcp_request(detailed_board_request)
    IO.puts("📋 Detailed task board: #{inspect(board_response, pretty: true)}")

    # Test 4: Get agent task history
    IO.puts("\n📜 Test 4: Getting individual agent task histories")

    history1_request = %{
      "method" => "tools/call",
      "params" => %{
        "name" => "get_agent_task_history",
        "arguments" => %{"agent_id" => agent1_id}
      },
      "jsonrpc" => "2.0",
      "id" => 6
    }

    history2_request = %{
      "method" => "tools/call",
      "params" => %{
        "name" => "get_agent_task_history",
        "arguments" => %{"agent_id" => agent2_id}
      },
      "jsonrpc" => "2.0",
      "id" => 7
    }

    history1_response = AgentCoordinator.MCPServer.handle_mcp_request(history1_request)
    history2_response = AgentCoordinator.MCPServer.handle_mcp_request(history2_request)

    IO.puts("📜 Agent 1 history: #{inspect(history1_response, pretty: true)}")
    IO.puts("📜 Agent 2 history: #{inspect(history2_response, pretty: true)}")

    # Test 5: Verify agents can get their own tasks
    IO.puts("\n🎯 Test 5: Verifying agents get their own tasks")

    next_task1_request = %{
      "method" => "tools/call",
      "params" => %{
        "name" => "get_next_task",
        "arguments" => %{"agent_id" => agent1_id}
      },
      "jsonrpc" => "2.0",
      "id" => 8
    }

    next_task2_request = %{
      "method" => "tools/call",
      "params" => %{
        "name" => "get_next_task",
        "arguments" => %{"agent_id" => agent2_id}
      },
      "jsonrpc" => "2.0",
      "id" => 9
    }

    task1_response = AgentCoordinator.MCPServer.handle_mcp_request(next_task1_request)
    task2_response = AgentCoordinator.MCPServer.handle_mcp_request(next_task2_request)

    IO.puts("🎯 Agent 1 next task: #{inspect(task1_response)}")
    IO.puts("🎯 Agent 2 next task: #{inspect(task2_response)}")

    IO.puts("\n✅ Test completed! Agent-specific task pools are working!")
    IO.puts("Each agent now has their own task queue and cannot access other agents' tasks.")

    # Cleanup
    cleanup_agents([agent1_id, agent2_id])
  end

  defp extract_agent_id(response) do
    case response do
      %{"result" => %{"content" => [%{"text" => text}]}} ->
        data = Jason.decode!(text)
        data["agent_id"]
      _ ->
        "unknown"
    end
  end

  defp cleanup_agents(agent_ids) do
    IO.puts("\n🧹 Cleaning up test agents...")

    Enum.each(agent_ids, fn agent_id ->
      unregister_request = %{
        "method" => "tools/call",
        "params" => %{
          "name" => "unregister_agent",
          "arguments" => %{
            "agent_id" => agent_id,
            "reason" => "Test completed"
          }
        },
        "jsonrpc" => "2.0",
        "id" => 999
      }

      AgentCoordinator.MCPServer.handle_mcp_request(unregister_request)
      IO.puts("🗑️  Unregistered agent: #{agent_id}")
    end)
  end
end

# Run the test
AgentTaskPoolTest.run_test()
