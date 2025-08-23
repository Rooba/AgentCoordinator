defmodule FullWorkflowDemo do
  @moduledoc """
  Demonstration of the complete task workflow
  """

  alias AgentCoordinator.MCPServer

  def run do
    IO.puts("🚀 Complete Agent Coordinator Workflow Demo")
    IO.puts("=" |> String.duplicate(50))

    # Register multiple agents
    IO.puts("\n👥 Registering multiple agents...")

    agents = [
      %{"name" => "CodingAgent", "capabilities" => ["coding", "debugging"]},
      %{"name" => "TestingAgent", "capabilities" => ["testing", "qa"]},
      %{"name" => "FullStackAgent", "capabilities" => ["coding", "testing", "ui"]}
    ]

    agent_ids = Enum.map(agents, fn agent ->
      register_request = %{
        "method" => "tools/call",
        "params" => %{
          "name" => "register_agent",
          "arguments" => agent
        },
        "jsonrpc" => "2.0",
        "id" => :rand.uniform(1000)
      }

      case MCPServer.handle_mcp_request(register_request) do
        %{"result" => %{"content" => [%{"text" => text}]}} ->
          data = Jason.decode!(text)
          IO.puts("✅ #{agent["name"]} registered: #{data["agent_id"]}")
          data["agent_id"]
        error ->
          IO.puts("❌ Error registering #{agent["name"]}: #{inspect(error)}")
          nil
      end
    end)

    # Create tasks with different requirements
    IO.puts("\n📝 Creating various tasks...")

    tasks = [
      %{"title" => "Fix Bug #123", "description" => "Debug authentication issue", "priority" => "high", "required_capabilities" => ["coding", "debugging"]},
      %{"title" => "Write Unit Tests", "description" => "Create comprehensive test suite", "priority" => "medium", "required_capabilities" => ["testing"]},
      %{"title" => "UI Enhancement", "description" => "Improve user interface", "priority" => "low", "required_capabilities" => ["ui", "coding"]},
      %{"title" => "Code Review", "description" => "Review pull request #456", "priority" => "medium", "required_capabilities" => ["coding"]}
    ]

    task_ids = Enum.map(tasks, fn task ->
      task_request = %{
        "method" => "tools/call",
        "params" => %{
          "name" => "create_task",
          "arguments" => task
        },
        "jsonrpc" => "2.0",
        "id" => :rand.uniform(1000)
      }

      case MCPServer.handle_mcp_request(task_request) do
        %{"result" => %{"content" => [%{"text" => text}]}} ->
          data = Jason.decode!(text)
          IO.puts("✅ Task '#{task["title"]}' created: #{data["task_id"]}")
          if data["assigned_to"] do
            IO.puts("   → Assigned to: #{data["assigned_to"]}")
          end
          data["task_id"]
        error ->
          IO.puts("❌ Error creating task '#{task["title"]}': #{inspect(error)}")
          nil
      end
    end)

    # Show current task board
    IO.puts("\n📊 Current Task Board:")
    show_task_board()

    # Test getting next task for first agent
    if agent_id = Enum.at(agent_ids, 0) do
      IO.puts("\n🎯 Getting next task for CodingAgent...")
      next_task_request = %{
        "method" => "tools/call",
        "params" => %{
          "name" => "get_next_task",
          "arguments" => %{
            "agent_id" => agent_id
          }
        },
        "jsonrpc" => "2.0",
        "id" => :rand.uniform(1000)
      }

      case MCPServer.handle_mcp_request(next_task_request) do
        %{"result" => %{"content" => [%{"text" => text}]}} ->
          data = Jason.decode!(text)
          if data["task"] do
            IO.puts("✅ Got task: #{data["task"]["title"]}")

            # Complete the task
            IO.puts("\n✅ Completing the task...")
            complete_request = %{
              "method" => "tools/call",
              "params" => %{
                "name" => "complete_task",
                "arguments" => %{
                  "agent_id" => agent_id,
                  "result" => "Task completed successfully!"
                }
              },
              "jsonrpc" => "2.0",
              "id" => :rand.uniform(1000)
            }

            case MCPServer.handle_mcp_request(complete_request) do
              %{"result" => %{"content" => [%{"text" => text}]}} ->
                completion_data = Jason.decode!(text)
                IO.puts("✅ Task completed: #{completion_data["message"]}")
              error ->
                IO.puts("❌ Error completing task: #{inspect(error)}")
            end
          else
            IO.puts("ℹ️  No tasks available: #{data["message"]}")
          end
        error ->
          IO.puts("❌ Error getting next task: #{inspect(error)}")
      end
    end

    # Final task board
    IO.puts("\n📊 Final Task Board:")
    show_task_board()

    IO.puts("\n🎉 Complete workflow demonstration finished!")
    IO.puts("=" |> String.duplicate(50))
  end

  defp show_task_board do
    board_request = %{
      "method" => "tools/call",
      "params" => %{
        "name" => "get_task_board",
        "arguments" => %{}
      },
      "jsonrpc" => "2.0",
      "id" => :rand.uniform(1000)
    }

    case MCPServer.handle_mcp_request(board_request) do
      %{"result" => %{"content" => [%{"text" => text}]}} ->
        data = Jason.decode!(text)
        Enum.each(data["agents"], fn agent ->
          IO.puts("   📱 #{agent["name"]} (#{String.slice(agent["agent_id"], 0, 8)}...)")
          IO.puts("      Capabilities: #{Enum.join(agent["capabilities"], ", ")}")
          IO.puts("      Status: #{agent["status"]}")
          if agent["current_task"] do
            IO.puts("      🎯 Current: #{agent["current_task"]["title"]}")
          end
          IO.puts("      📈 Stats: #{agent["pending_tasks"]} pending | #{agent["completed_tasks"]} completed")
          IO.puts("")
        end)
      error ->
        IO.puts("❌ Error getting task board: #{inspect(error)}")
    end
  end
end

# Run the demo
FullWorkflowDemo.run()
