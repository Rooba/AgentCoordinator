#!/usr/bin/env elixir

# Simple test script to demonstrate MCP server functionality
Mix.install([
  {:jason, "~> 1.4"}
])

# Start the agent coordinator application
Application.ensure_all_started(:agent_coordinator)

alias AgentCoordinator.MCPServer

IO.puts("🚀 Testing Agent Coordinator MCP Server")
IO.puts("=" |> String.duplicate(50))

# Test 1: Get tools list
IO.puts("\n📋 Getting available tools...")
tools_request = %{"method" => "tools/list", "jsonrpc" => "2.0", "id" => 1}
tools_response = MCPServer.handle_mcp_request(tools_request)

case tools_response do
  %{"result" => %{"tools" => tools}} ->
    IO.puts("✅ Found #{length(tools)} tools:")
    Enum.each(tools, fn tool ->
      IO.puts("   - #{tool["name"]}: #{tool["description"]}")
    end)
  error ->
    IO.puts("❌ Error getting tools: #{inspect(error)}")
end

# Test 2: Register an agent
IO.puts("\n👤 Registering test agent...")
register_request = %{
  "method" => "tools/call",
  "params" => %{
    "name" => "register_agent",
    "arguments" => %{
      "name" => "DemoAgent",
      "capabilities" => ["coding", "testing"]
    }
  },
  "jsonrpc" => "2.0",
  "id" => 2
}

register_response = MCPServer.handle_mcp_request(register_request)

agent_id = case register_response do
  %{"result" => %{"content" => [%{"text" => text}]}} ->
    data = Jason.decode!(text)
    IO.puts("✅ Agent registered: #{data["agent_id"]}")
    data["agent_id"]
  error ->
    IO.puts("❌ Error registering agent: #{inspect(error)}")
    nil
end

if agent_id do
  # Test 3: Create a task
  IO.puts("\n📝 Creating a test task...")
  task_request = %{
    "method" => "tools/call",
    "params" => %{
      "name" => "create_task",
      "arguments" => %{
        "title" => "Demo Task",
        "description" => "A demonstration task for the MCP server",
        "priority" => "high",
        "required_capabilities" => ["coding"]
      }
    },
    "jsonrpc" => "2.0",
    "id" => 3
  }

  task_response = MCPServer.handle_mcp_request(task_request)

  case task_response do
    %{"result" => %{"content" => [%{"text" => text}]}} ->
      data = Jason.decode!(text)
      IO.puts("✅ Task created: #{data["task_id"]}")
      if data["assigned_to"] do
        IO.puts("   Assigned to: #{data["assigned_to"]}")
      end
    error ->
      IO.puts("❌ Error creating task: #{inspect(error)}")
  end

  # Test 4: Get task board
  IO.puts("\n📊 Getting task board...")
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

  case board_response do
    %{"result" => %{"content" => [%{"text" => text}]}} ->
      data = Jason.decode!(text)
      IO.puts("✅ Task board retrieved:")
      Enum.each(data["agents"], fn agent ->
        IO.puts("   Agent: #{agent["name"]} (#{agent["agent_id"]})")
        IO.puts("   Capabilities: #{Enum.join(agent["capabilities"], ", ")}")
        IO.puts("   Status: #{agent["status"]}")
        if agent["current_task"] do
          IO.puts("   Current Task: #{agent["current_task"]["title"]}")
        else
          IO.puts("   Current Task: None")
        end
        IO.puts("   Pending: #{agent["pending_tasks"]} | Completed: #{agent["completed_tasks"]}")
        IO.puts("")
      end)
    error ->
      IO.puts("❌ Error getting task board: #{inspect(error)}")
  end

  # Test 5: Send heartbeat
  IO.puts("\n💓 Sending heartbeat...")
  heartbeat_request = %{
    "method" => "tools/call",
    "params" => %{
      "name" => "heartbeat",
      "arguments" => %{
        "agent_id" => agent_id
      }
    },
    "jsonrpc" => "2.0",
    "id" => 5
  }

  heartbeat_response = MCPServer.handle_mcp_request(heartbeat_request)

  case heartbeat_response do
    %{"result" => %{"content" => [%{"text" => text}]}} ->
      data = Jason.decode!(text)
      IO.puts("✅ Heartbeat sent: #{data["status"]}")
    error ->
      IO.puts("❌ Error sending heartbeat: #{inspect(error)}")
  end
end

IO.puts("\n🎉 MCP Server testing completed!")
IO.puts("=" |> String.duplicate(50))
