#!/usr/bin/env elixir

# Unified MCP Server Demo
# This demo shows how the unified MCP server provides automatic task tracking
# for all external MCP server operations

Mix.install([
  {:agent_coordinator, path: "."},
  {:jason, "~> 1.4"}
])

defmodule UnifiedDemo do
  @moduledoc """
  Demo showing the unified MCP server with automatic task tracking
  """

  def run do
    IO.puts("🚀 Starting Unified MCP Server Demo...")
    IO.puts("=" * 60)

    # Start the unified system
    {:ok, _} = AgentCoordinator.TaskRegistry.start_link()
    {:ok, _} = AgentCoordinator.MCPServerManager.start_link(config_file: "mcp_servers.json")
    {:ok, _} = AgentCoordinator.UnifiedMCPServer.start_link()

    IO.puts("✅ Unified MCP server started successfully")

    # Demonstrate automatic tool aggregation
    demonstrate_tool_aggregation()

    # Demonstrate automatic task tracking
    demonstrate_automatic_task_tracking()

    # Demonstrate coordination features
    demonstrate_coordination_features()

    IO.puts("\n🎉 Demo completed successfully!")
    IO.puts("📋 Key Points:")
    IO.puts("   • All external MCP servers are managed internally")
    IO.puts("   • Every tool call automatically creates/updates tasks")
    IO.puts("   • GitHub Copilot sees only one MCP server")
    IO.puts("   • Coordination tools are still available for planning")
  end

  defp demonstrate_tool_aggregation do
    IO.puts("\n📊 Testing Tool Aggregation...")

    # Get all available tools from the unified server
    request = %{
      "jsonrpc" => "2.0",
      "id" => 1,
      "method" => "tools/list"
    }

    response = AgentCoordinator.UnifiedMCPServer.handle_mcp_request(request)

    case response do
      %{"result" => %{"tools" => tools}} ->
        IO.puts("✅ Found #{length(tools)} total tools from all servers:")

        # Group tools by server origin
        coordinator_tools =
          Enum.filter(tools, fn tool ->
            tool["name"] in ~w[register_agent create_task get_next_task complete_task get_task_board heartbeat]
          end)

        external_tools = tools -- coordinator_tools

        IO.puts("   • Agent Coordinator: #{length(coordinator_tools)} tools")
        IO.puts("   • External Servers: #{length(external_tools)} tools")

        # Show sample tools
        IO.puts("\n📝 Sample Agent Coordinator tools:")

        Enum.take(coordinator_tools, 3)
        |> Enum.each(fn tool ->
          IO.puts("   - #{tool["name"]}: #{tool["description"]}")
        end)

        if length(external_tools) > 0 do
          IO.puts("\n📝 Sample External tools:")

          Enum.take(external_tools, 3)
          |> Enum.each(fn tool ->
            IO.puts(
              "   - #{tool["name"]}: #{String.slice(tool["description"] || "External tool", 0, 50)}"
            )
          end)
        end

      error ->
        IO.puts("❌ Error getting tools: #{inspect(error)}")
    end
  end

  defp demonstrate_automatic_task_tracking do
    IO.puts("\n🎯 Testing Automatic Task Tracking...")

    # First, register an agent (this creates an agent context)
    register_request = %{
      "jsonrpc" => "2.0",
      "id" => 2,
      "method" => "tools/call",
      "params" => %{
        "name" => "register_agent",
        "arguments" => %{
          "name" => "Demo Agent",
          "capabilities" => ["coding", "analysis"]
        }
      }
    }

    response = AgentCoordinator.UnifiedMCPServer.handle_mcp_request(register_request)
    IO.puts("✅ Agent registered: #{inspect(response["result"])}")

    # Now simulate using an external tool - this should automatically create a task
    # Note: In a real scenario, external servers would be running
    external_tool_request = %{
      "jsonrpc" => "2.0",
      "id" => 3,
      "method" => "tools/call",
      "params" => %{
        "name" => "mcp_filesystem_read_file",
        "arguments" => %{
          "path" => "/home/ra/agent_coordinator/README.md"
        }
      }
    }

    IO.puts("🔄 Simulating external tool call: mcp_filesystem_read_file")

    external_response =
      AgentCoordinator.UnifiedMCPServer.handle_mcp_request(external_tool_request)

    case external_response do
      %{"result" => result} ->
        IO.puts("✅ Tool call succeeded with automatic task tracking")

        if metadata = result["_metadata"] do
          IO.puts("📊 Automatic metadata:")
          IO.puts("   - Tool: #{metadata["tool_name"]}")
          IO.puts("   - Agent: #{metadata["agent_id"]}")
          IO.puts("   - Auto-tracked: #{metadata["auto_tracked"]}")
        end

      %{"error" => error} ->
        IO.puts("ℹ️  External server not available (expected in demo): #{error["message"]}")
        IO.puts("   In real usage, this would automatically create a task")
    end

    # Check the task board to see auto-created tasks
    IO.puts("\n📋 Checking Task Board...")

    task_board_request = %{
      "jsonrpc" => "2.0",
      "id" => 4,
      "method" => "tools/call",
      "params" => %{
        "name" => "get_task_board",
        "arguments" => %{}
      }
    }

    board_response = AgentCoordinator.UnifiedMCPServer.handle_mcp_request(task_board_request)

    case board_response do
      %{"result" => %{"content" => [%{"text" => board_json}]}} ->
        case Jason.decode(board_json) do
          {:ok, board} ->
            IO.puts("✅ Task Board Status:")
            IO.puts("   - Total Agents: #{board["total_agents"]}")
            IO.puts("   - Active Tasks: #{board["active_tasks"]}")
            IO.puts("   - Pending Tasks: #{board["pending_count"]}")

            if length(board["agents"]) > 0 do
              agent = List.first(board["agents"])
              IO.puts("   - Agent '#{agent["name"]}' is #{agent["status"]}")
            end

          {:error, _} ->
            IO.puts("📊 Task board response: #{board_json}")
        end

      _ ->
        IO.puts("📊 Task board response: #{inspect(board_response)}")
    end
  end

  defp demonstrate_coordination_features do
    IO.puts("\n🤝 Testing Coordination Features...")

    # Create a manual task for coordination
    create_task_request = %{
      "jsonrpc" => "2.0",
      "id" => 5,
      "method" => "tools/call",
      "params" => %{
        "name" => "create_task",
        "arguments" => %{
          "title" => "Review Database Design",
          "description" => "Review the database schema for the new feature",
          "priority" => "high"
        }
      }
    }

    response = AgentCoordinator.UnifiedMCPServer.handle_mcp_request(create_task_request)
    IO.puts("✅ Manual task created for coordination: #{inspect(response["result"])}")

    # Send a heartbeat
    heartbeat_request = %{
      "jsonrpc" => "2.0",
      "id" => 6,
      "method" => "tools/call",
      "params" => %{
        "name" => "heartbeat",
        "arguments" => %{
          "agent_id" => "github_copilot_session"
        }
      }
    }

    heartbeat_response = AgentCoordinator.UnifiedMCPServer.handle_mcp_request(heartbeat_request)
    IO.puts("✅ Heartbeat sent: #{inspect(heartbeat_response["result"])}")

    IO.puts("\n💡 Coordination tools are seamlessly integrated:")
    IO.puts("   • Agents can still create tasks manually for planning")
    IO.puts("   • Heartbeats maintain agent liveness")
    IO.puts("   • Task board shows both auto and manual tasks")
    IO.puts("   • All operations work through the single unified interface")
  end
end

# Run the demo
UnifiedDemo.run()
