#!/usr/bin/env elixir

# Test script to simulate VS Code MCP initialization sequence

# Start the application
Application.start(:agent_coordinator)

# Wait a moment for the server to fully start
Process.sleep(1000)

# Test 1: Initialize call (system call, should work without agent_id)
IO.puts("Testing initialize call...")
init_request = %{
  "jsonrpc" => "2.0",
  "id" => 1,
  "method" => "initialize",
  "params" => %{
    "protocolVersion" => "2024-11-05",
    "capabilities" => %{
      "tools" => %{}
    },
    "clientInfo" => %{
      "name" => "vscode",
      "version" => "1.0.0"
    }
  }
}

init_response = GenServer.call(AgentCoordinator.MCPServer, {:mcp_request, init_request})
IO.puts("Initialize response: #{inspect(init_response)}")

# Test 2: Tools/list call (system call, should work without agent_id)
IO.puts("\nTesting tools/list call...")
tools_request = %{
  "jsonrpc" => "2.0",
  "id" => 2,
  "method" => "tools/list"
}

tools_response = GenServer.call(AgentCoordinator.MCPServer, {:mcp_request, tools_request})
IO.puts("Tools/list response: #{inspect(tools_response)}")

# Test 3: Register agent call (should work)
IO.puts("\nTesting register_agent call...")
register_request = %{
  "jsonrpc" => "2.0",
  "id" => 3,
  "method" => "tools/call",
  "params" => %{
    "name" => "register_agent",
    "arguments" => %{
      "name" => "GitHub Copilot Test Agent",
      "capabilities" => ["file_operations", "code_generation"]
    }
  }
}

register_response = GenServer.call(AgentCoordinator.MCPServer, {:mcp_request, register_request})
IO.puts("Register agent response: #{inspect(register_response)}")

# Test 4: Try a call that requires agent_id (should fail without agent_id)
IO.puts("\nTesting call that requires agent_id (should fail)...")
task_request = %{
  "jsonrpc" => "2.0",
  "id" => 4,
  "method" => "tools/call",
  "params" => %{
    "name" => "create_task",
    "arguments" => %{
      "title" => "Test task",
      "description" => "This should fail without agent_id"
    }
  }
}

task_response = GenServer.call(AgentCoordinator.MCPServer, {:mcp_request, task_request})
IO.puts("Task creation response: #{inspect(task_response)}")

IO.puts("\n✅ All tests completed!")"
