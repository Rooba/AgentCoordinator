#!/usr/bin/env elixir

# Multi-Codebase Coordination Test Script
# This script demonstrates how agents can coordinate across multiple codebases

Mix.install([
  {:jason, "~> 1.4"},
  {:uuid, "~> 1.1"}
])

defmodule MultiCodebaseTest do
  @moduledoc """
  Test script for multi-codebase agent coordination functionality.
  Demonstrates cross-codebase task creation, dependency management, and agent coordination.
  """

  def run do
    IO.puts("=== Multi-Codebase Agent Coordination Test ===\n")

    # Test 1: Register multiple codebases
    test_codebase_registration()

    # Test 2: Register agents in different codebases
    test_agent_registration()

    # Test 3: Create tasks within individual codebases
    test_single_codebase_tasks()

    # Test 4: Create cross-codebase tasks
    test_cross_codebase_tasks()

    # Test 5: Test cross-codebase dependencies
    test_codebase_dependencies()

    # Test 6: Verify coordination and task board
    test_coordination_overview()

    IO.puts("\n=== Test Completed ===")
  end

  def test_codebase_registration do
    IO.puts("1. Testing Codebase Registration")
    IO.puts("   - Registering frontend codebase...")
    IO.puts("   - Registering backend codebase...")
    IO.puts("   - Registering shared-lib codebase...")

    frontend_codebase = %{
      "id" => "frontend-app",
      "name" => "Frontend Application",
      "workspace_path" => "/workspace/frontend",
      "description" => "React-based frontend application",
      "metadata" => %{
        "tech_stack" => ["react", "typescript", "tailwind"],
        "dependencies" => ["backend-api", "shared-lib"]
      }
    }

    backend_codebase = %{
      "id" => "backend-api",
      "name" => "Backend API",
      "workspace_path" => "/workspace/backend",
      "description" => "Node.js API server",
      "metadata" => %{
        "tech_stack" => ["nodejs", "express", "mongodb"],
        "dependencies" => ["shared-lib"]
      }
    }

    shared_lib_codebase = %{
      "id" => "shared-lib",
      "name" => "Shared Library",
      "workspace_path" => "/workspace/shared",
      "description" => "Shared utilities and types",
      "metadata" => %{
        "tech_stack" => ["typescript"],
        "dependencies" => []
      }
    }

    # Simulate MCP calls
    simulate_mcp_call("register_codebase", frontend_codebase)
    simulate_mcp_call("register_codebase", backend_codebase)
    simulate_mcp_call("register_codebase", shared_lib_codebase)

    IO.puts("   ✓ All codebases registered successfully\n")
  end

  def test_agent_registration do
    IO.puts("2. Testing Agent Registration")

    # Frontend agents
    frontend_agent1 = %{
      "name" => "frontend-dev-1",
      "capabilities" => ["coding", "testing"],
      "codebase_id" => "frontend-app",
      "workspace_path" => "/workspace/frontend",
      "cross_codebase_capable" => true
    }

    frontend_agent2 = %{
      "name" => "frontend-dev-2",
      "capabilities" => ["coding", "review"],
      "codebase_id" => "frontend-app",
      "workspace_path" => "/workspace/frontend",
      "cross_codebase_capable" => false
    }

    # Backend agents
    backend_agent1 = %{
      "name" => "backend-dev-1",
      "capabilities" => ["coding", "testing", "analysis"],
      "codebase_id" => "backend-api",
      "workspace_path" => "/workspace/backend",
      "cross_codebase_capable" => true
    }

    # Shared library agent (cross-codebase capable)
    shared_agent = %{
      "name" => "shared-lib-dev",
      "capabilities" => ["coding", "documentation", "review"],
      "codebase_id" => "shared-lib",
      "workspace_path" => "/workspace/shared",
      "cross_codebase_capable" => true
    }

    agents = [frontend_agent1, frontend_agent2, backend_agent1, shared_agent]

    Enum.each(agents, fn agent ->
      IO.puts("   - Registering agent: #{agent["name"]} (#{agent["codebase_id"]})")
      simulate_mcp_call("register_agent", agent)
    end)

    IO.puts("   ✓ All agents registered successfully\n")
  end

  def test_single_codebase_tasks do
    IO.puts("3. Testing Single Codebase Tasks")

    tasks = [
      %{
        "title" => "Update user interface components",
        "description" => "Modernize the login and dashboard components",
        "codebase_id" => "frontend-app",
        "file_paths" => ["/src/components/Login.tsx", "/src/components/Dashboard.tsx"],
        "required_capabilities" => ["coding"],
        "priority" => "normal"
      },
      %{
        "title" => "Implement user authentication API",
        "description" => "Create secure user authentication endpoints",
        "codebase_id" => "backend-api",
        "file_paths" => ["/src/routes/auth.js", "/src/middleware/auth.js"],
        "required_capabilities" => ["coding", "testing"],
        "priority" => "high"
      },
      %{
        "title" => "Add utility functions for date handling",
        "description" => "Create reusable date utility functions",
        "codebase_id" => "shared-lib",
        "file_paths" => ["/src/utils/date.ts", "/src/types/date.ts"],
        "required_capabilities" => ["coding", "documentation"],
        "priority" => "normal"
      }
    ]

    Enum.each(tasks, fn task ->
      IO.puts("   - Creating task: #{task["title"]} (#{task["codebase_id"]})")
      simulate_mcp_call("create_task", task)
    end)

    IO.puts("   ✓ All single-codebase tasks created successfully\n")
  end

  def test_cross_codebase_tasks do
    IO.puts("4. Testing Cross-Codebase Tasks")

    # Task that affects multiple codebases
    cross_codebase_task = %{
      "title" => "Implement real-time notifications feature",
      "description" => "Add real-time notifications across frontend and backend",
      "primary_codebase_id" => "backend-api",
      "affected_codebases" => ["backend-api", "frontend-app", "shared-lib"],
      "coordination_strategy" => "sequential"
    }

    IO.puts("   - Creating cross-codebase task: #{cross_codebase_task["title"]}")
    IO.puts("     Primary: #{cross_codebase_task["primary_codebase_id"]}")
    IO.puts("     Affected: #{Enum.join(cross_codebase_task["affected_codebases"], ", ")}")
    
    simulate_mcp_call("create_cross_codebase_task", cross_codebase_task)

    # Another cross-codebase task with different strategy
    parallel_task = %{
      "title" => "Update shared types and interfaces",
      "description" => "Synchronize type definitions across all codebases",
      "primary_codebase_id" => "shared-lib",
      "affected_codebases" => ["shared-lib", "frontend-app", "backend-api"],
      "coordination_strategy" => "parallel"
    }

    IO.puts("   - Creating parallel cross-codebase task: #{parallel_task["title"]}")
    simulate_mcp_call("create_cross_codebase_task", parallel_task)

    IO.puts("   ✓ Cross-codebase tasks created successfully\n")
  end

  def test_codebase_dependencies do
    IO.puts("5. Testing Codebase Dependencies")

    dependencies = [
      %{
        "source_codebase_id" => "frontend-app",
        "target_codebase_id" => "backend-api",
        "dependency_type" => "api_consumption",
        "metadata" => %{"api_version" => "v1", "endpoints" => ["auth", "users", "notifications"]}
      },
      %{
        "source_codebase_id" => "frontend-app",
        "target_codebase_id" => "shared-lib",
        "dependency_type" => "library_import",
        "metadata" => %{"imports" => ["types", "utils", "constants"]}
      },
      %{
        "source_codebase_id" => "backend-api",
        "target_codebase_id" => "shared-lib",
        "dependency_type" => "library_import",
        "metadata" => %{"imports" => ["types", "validators"]}
      }
    ]

    Enum.each(dependencies, fn dep ->
      IO.puts("   - Adding dependency: #{dep["source_codebase_id"]} → #{dep["target_codebase_id"]} (#{dep["dependency_type"]})")
      simulate_mcp_call("add_codebase_dependency", dep)
    end)

    IO.puts("   ✓ All codebase dependencies added successfully\n")
  end

  def test_coordination_overview do
    IO.puts("6. Testing Coordination Overview")

    IO.puts("   - Getting overall task board...")
    simulate_mcp_call("get_task_board", %{})

    IO.puts("   - Getting frontend codebase status...")
    simulate_mcp_call("get_codebase_status", %{"codebase_id" => "frontend-app"})

    IO.puts("   - Getting backend codebase status...")
    simulate_mcp_call("get_codebase_status", %{"codebase_id" => "backend-api"})

    IO.puts("   - Listing all codebases...")
    simulate_mcp_call("list_codebases", %{})

    IO.puts("   ✓ Coordination overview retrieved successfully\n")
  end

  defp simulate_mcp_call(tool_name, arguments) do
    request = %{
      "jsonrpc" => "2.0",
      "id" => UUID.uuid4(),
      "method" => "tools/call",
      "params" => %{
        "name" => tool_name,
        "arguments" => arguments
      }
    }

    # In a real implementation, this would make an actual MCP call
    # For now, we'll just show the structure
    IO.puts("     MCP Call: #{tool_name}")
    IO.puts("     Arguments: #{Jason.encode!(arguments, pretty: true) |> String.replace("\n", "\n     ")}")
    
    # Simulate successful response
    response = %{
      "jsonrpc" => "2.0",
      "id" => request["id"],
      "result" => %{
        "content" => [%{
          "type" => "text",
          "text" => Jason.encode!(%{"status" => "success", "tool" => tool_name})
        }]
      }
    }
    
    IO.puts("     Response: success")
  end

  def simulate_task_flow do
    IO.puts("\n=== Simulating Multi-Codebase Task Flow ===")
    
    IO.puts("1. Cross-codebase task created:")
    IO.puts("   - Main task assigned to backend agent")
    IO.puts("   - Dependent task created for frontend")
    IO.puts("   - Dependent task created for shared library")
    
    IO.puts("\n2. Agent coordination:")
    IO.puts("   - Backend agent starts implementation")
    IO.puts("   - Publishes API specification to NATS stream")
    IO.puts("   - Frontend agent receives notification")
    IO.puts("   - Shared library agent updates type definitions")
    
    IO.puts("\n3. File conflict detection:")
    IO.puts("   - Frontend agent attempts to modify shared types")
    IO.puts("   - System detects conflict with shared-lib agent's work")
    IO.puts("   - Task is queued until shared-lib work completes")
    
    IO.puts("\n4. Cross-codebase synchronization:")
    IO.puts("   - Shared-lib agent completes type updates")
    IO.puts("   - Frontend task is automatically unblocked")
    IO.puts("   - All agents coordinate through NATS streams")
    
    IO.puts("\n5. Task completion:")
    IO.puts("   - All subtasks complete successfully")
    IO.puts("   - Cross-codebase dependencies resolved")
    IO.puts("   - Coordination system updates task board")
  end
end

# Run the test
MultiCodebaseTest.run()
MultiCodebaseTest.simulate_task_flow()