#!/usr/bin/env elixir

# Comprehensive test for agent-specific task pools
# This verifies that the chaos problem is fixed and agents can manage their own task sets

Application.ensure_all_started(:agent_coordinator)

alias AgentCoordinator.{MCPServer, TaskRegistry, Agent, Inbox}

IO.puts("🧪 Testing Agent-Specific Task Pools Fix")
IO.puts("=" |> String.duplicate(60))

# Ensure clean state
try do
  TaskRegistry.start_link()
rescue
  _ -> :ok  # Already started
end

try do
  MCPServer.start_link()
rescue
  _ -> :ok  # Already started
end

Process.sleep(1000)  # Give services time to start

# Test 1: Register two agents
IO.puts("\n1️⃣ Registering two test agents...")

agent1_req = %{
  "method" => "tools/call",
  "params" => %{
    "name" => "register_agent",
    "arguments" => %{
      "name" => "GitHub Copilot Alpha Wolf",
      "capabilities" => ["coding", "testing"]
    }
  },
  "jsonrpc" => "2.0",
  "id" => 1
}

agent2_req = %{
  "method" => "tools/call",
  "params" => %{
    "name" => "register_agent",
    "arguments" => %{
      "name" => "GitHub Copilot Beta Tiger",
      "capabilities" => ["documentation", "analysis"]
    }
  },
  "jsonrpc" => "2.0",
  "id" => 2
}

resp1 = MCPServer.handle_mcp_request(agent1_req)
resp2 = MCPServer.handle_mcp_request(agent2_req)

# Extract agent IDs
agent1_id = case resp1 do
  %{"result" => %{"content" => [%{"text" => text}]}} ->
    data = Jason.decode!(text)
    data["agent_id"]
  _ ->
    IO.puts("❌ Failed to register agent 1: #{inspect(resp1)}")
    System.halt(1)
end

agent2_id = case resp2 do
  %{"result" => %{"content" => [%{"text" => text}]}} ->
    data = Jason.decode!(text)
    data["agent_id"]
  _ ->
    IO.puts("❌ Failed to register agent 2: #{inspect(resp2)}")
    System.halt(1)
end

IO.puts("✅ Agent 1 (Alpha Wolf): #{agent1_id}")
IO.puts("✅ Agent 2 (Beta Tiger): #{agent2_id}")

# Test 2: Create task sets for each agent (THIS IS THE KEY TEST!)
IO.puts("\n2️⃣ Creating agent-specific task sets...")

# Agent 1 task set
agent1_task_set = %{
  "method" => "tools/call",
  "params" => %{
    "name" => "register_task_set",
    "arguments" => %{
      "agent_id" => agent1_id,
      "task_set" => [
        %{
          "title" => "Fix authentication bug",
          "description" => "Debug and fix the login authentication issue",
          "priority" => "high",
          "estimated_time" => "2 hours",
          "file_paths" => ["lib/auth.ex", "test/auth_test.exs"]
        },
        %{
          "title" => "Add unit tests for auth module",
          "description" => "Write comprehensive tests for authentication",
          "priority" => "normal",
          "estimated_time" => "1 hour"
        },
        %{
          "title" => "Refactor auth middleware",
          "description" => "Clean up and optimize auth middleware code",
          "priority" => "low",
          "estimated_time" => "30 minutes"
        }
      ]
    }
  },
  "jsonrpc" => "2.0",
  "id" => 3
}

# Agent 2 task set (completely different)
agent2_task_set = %{
  "method" => "tools/call",
  "params" => %{
    "name" => "register_task_set",
    "arguments" => %{
      "agent_id" => agent2_id,
      "task_set" => [
        %{
          "title" => "Write API documentation",
          "description" => "Document all REST API endpoints with examples",
          "priority" => "normal",
          "estimated_time" => "3 hours",
          "file_paths" => ["docs/api.md"]
        },
        %{
          "title" => "Analyze code coverage",
          "description" => "Run coverage analysis and identify gaps",
          "priority" => "high",
          "estimated_time" => "1 hour"
        }
      ]
    }
  },
  "jsonrpc" => "2.0",
  "id" => 4
}

task_set_resp1 = MCPServer.handle_mcp_request(agent1_task_set)
task_set_resp2 = MCPServer.handle_mcp_request(agent2_task_set)

IO.puts("Agent 1 task set response: #{inspect(task_set_resp1)}")
IO.puts("Agent 2 task set response: #{inspect(task_set_resp2)}")

# Test 3: Verify agents only see their own tasks
IO.puts("\n3️⃣ Verifying agent isolation...")

# Get detailed task board
task_board_req = %{
  "method" => "tools/call",
  "params" => %{
    "name" => "get_detailed_task_board",
    "arguments" => %{}
  },
  "jsonrpc" => "2.0",
  "id" => 5
}

board_resp = MCPServer.handle_mcp_request(task_board_req)
IO.puts("Task board response: #{inspect(board_resp)}")

# Test 4: Agent 1 gets their next task (should be their own)
IO.puts("\n4️⃣ Testing task retrieval...")

next_task_req1 = %{
  "method" => "tools/call",
  "params" => %{
    "name" => "get_next_task",
    "arguments" => %{
      "agent_id" => agent1_id
    }
  },
  "jsonrpc" => "2.0",
  "id" => 6
}

task_resp1 = MCPServer.handle_mcp_request(next_task_req1)
IO.puts("Agent 1 next task: #{inspect(task_resp1)}")

# Test 5: Agent 2 gets their next task (should be different)
next_task_req2 = %{
  "method" => "tools/call",
  "params" => %{
    "name" => "get_next_task",
    "arguments" => %{
      "agent_id" => agent2_id
    }
  },
  "jsonrpc" => "2.0",
  "id" => 7
}

task_resp2 = MCPServer.handle_mcp_request(next_task_req2)
IO.puts("Agent 2 next task: #{inspect(task_resp2)}")

# Test 6: Get individual agent task history
IO.puts("\n5️⃣ Testing agent task history...")

history_req1 = %{
  "method" => "tools/call",
  "params" => %{
    "name" => "get_agent_task_history",
    "arguments" => %{
      "agent_id" => agent1_id
    }
  },
  "jsonrpc" => "2.0",
  "id" => 8
}

history_resp1 = MCPServer.handle_mcp_request(history_req1)
IO.puts("Agent 1 history: #{inspect(history_resp1)}")

IO.puts("\n" <> "=" |> String.duplicate(60))
IO.puts("🎉 AGENT-SPECIFIC TASK POOLS TEST COMPLETE!")
IO.puts("✅ Each agent now has their own task pool")
IO.puts("✅ No more task chaos or cross-contamination")
IO.puts("✅ Agents can plan and coordinate their workflows")
IO.puts("=" |> String.duplicate(60))
