defmodule AgentCoordinator.CLI do
  @moduledoc """
  Command line interface for testing the agent coordination system.
  """

  alias AgentCoordinator.{MCPServer, Inbox}

  def main(args \\ []) do
    case args do
      ["register", name | capabilities] ->
        register_agent(name, capabilities)

      ["create-task", title, description | opts] ->
        create_task(title, description, parse_task_opts(opts))

      ["board"] ->
        show_task_board()

      ["agent-status", agent_id] ->
        show_agent_status(agent_id)

      ["help"] ->
        show_help()

      _ ->
        IO.puts("Invalid command. Use 'help' for usage information.")
    end
  end

  defp register_agent(name, capabilities) do
    # Note: capabilities should be passed as strings to the MCP server
    # The server will handle the validation

    request = %{
      "method" => "tools/call",
      "params" => %{
        "name" => "register_agent",
        "arguments" => %{
          "name" => name,
          "capabilities" => capabilities
        }
      }
    }

    case MCPServer.handle_mcp_request(request) do
      %{"result" => %{"content" => [%{"text" => result}]}} ->
        data = Jason.decode!(result)
        IO.puts("✓ Agent registered successfully!")
        IO.puts("  Agent ID: #{data["agent_id"]}")
        IO.puts("  Status: #{data["status"]}")

      %{"error" => %{"message" => message}} ->
        IO.puts("✗ Registration failed: #{message}")
    end
  end

  defp create_task(title, description, opts) do
    request = %{
      "method" => "tools/call",
      "params" => %{
        "name" => "create_task",
        "arguments" =>
          Map.merge(
            %{
              "title" => title,
              "description" => description
            },
            opts
          )
      }
    }

    case MCPServer.handle_mcp_request(request) do
      %{"result" => %{"content" => [%{"text" => result}]}} ->
        data = Jason.decode!(result)
        IO.puts("✓ Task created successfully!")
        IO.puts("  Task ID: #{data["task_id"]}")
        IO.puts("  Status: #{data["status"]}")

        if Map.has_key?(data, "assigned_to") do
          IO.puts("  Assigned to: #{data["assigned_to"]}")
        end

      %{"error" => %{"message" => message}} ->
        IO.puts("✗ Task creation failed: #{message}")
    end
  end

  defp show_task_board do
    request = %{
      "method" => "tools/call",
      "params" => %{
        "name" => "get_task_board",
        "arguments" => %{}
      }
    }

    case MCPServer.handle_mcp_request(request) do
      %{"result" => %{"content" => [%{"text" => result}]}} ->
        %{"agents" => agents} = Jason.decode!(result)

        IO.puts("\n📋 Task Board")
        IO.puts(String.duplicate("=", 50))

        if Enum.empty?(agents) do
          IO.puts("No agents registered.")
        else
          Enum.each(agents, &print_agent_summary/1)
        end

      error ->
        IO.puts("✗ Failed to fetch task board: #{inspect(error)}")
    end
  end

  defp show_agent_status(agent_id) do
    case Inbox.get_status(agent_id) do
      status ->
        IO.puts("\n👤 Agent Status: #{agent_id}")
        IO.puts(String.duplicate("-", 30))
        IO.puts("Pending tasks: #{status.pending_count}")
        IO.puts("Completed tasks: #{status.completed_count}")

        case status.current_task do
          nil ->
            IO.puts("Current task: None")

          task ->
            IO.puts("Current task: #{task.title}")
            IO.puts("  Description: #{task.description}")
            IO.puts("  Priority: #{task.priority}")
        end
    end
  end

  defp print_agent_summary(agent) do
    status_icon =
      case agent["status"] do
        "idle" -> "💤"
        "busy" -> "🔧"
        "offline" -> "❌"
        _ -> "❓"
      end

    online_status = if agent["online"], do: "🟢", else: "🔴"

    IO.puts("\n#{status_icon} #{agent["name"]} (#{agent["agent_id"]}) #{online_status}")
    IO.puts("   Capabilities: #{Enum.join(agent["capabilities"], ", ")}")
    IO.puts("   Pending: #{agent["pending_tasks"]} | Completed: #{agent["completed_tasks"]}")

    case agent["current_task"] do
      nil ->
        IO.puts("   Current: No active task")

      task ->
        IO.puts("   Current: #{task["title"]}")
    end
  end

  defp parse_task_opts(opts) do
    Enum.reduce(opts, %{}, fn opt, acc ->
      case String.split(opt, "=", parts: 2) do
        ["priority", value] ->
          Map.put(acc, "priority", value)

        ["files", files] ->
          Map.put(acc, "file_paths", String.split(files, ","))

        ["caps", capabilities] ->
          Map.put(acc, "required_capabilities", String.split(capabilities, ","))

        _ ->
          acc
      end
    end)
  end

  defp show_help do
    IO.puts("""
    Agent Coordinator CLI

    Commands:
      register <name> <capability1> <capability2> ...
        Register a new agent with specified capabilities
        Capabilities: coding, testing, documentation, analysis, review

      create-task <title> <description> [priority=<low|normal|high|urgent>] [files=<file1,file2>] [caps=<cap1,cap2>]
        Create a new task with optional parameters

      board
        Show current task board with all agents and their status

      agent-status <agent-id>
        Show detailed status for a specific agent

      help
        Show this help message

    Examples:
      register "CodeBot" coding testing
      create-task "Fix login bug" "User login fails with 500 error" priority=high files=auth.ex,login.ex
      board
      agent-status abc-123-def
    """)
  end
end
