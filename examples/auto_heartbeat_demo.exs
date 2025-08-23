#!/usr/bin/env elixir

# Auto-heartbeat demo script
# This demonstrates the enhanced coordination system with automatic heartbeats

Mix.install([
  {:jason, "~> 1.4"},
  {:uuid, "~> 1.1"}
])

# Load the agent coordinator modules
Code.require_file("lib/agent_coordinator.ex")
Code.require_file("lib/agent_coordinator/agent.ex")
Code.require_file("lib/agent_coordinator/task.ex")
Code.require_file("lib/agent_coordinator/inbox.ex")
Code.require_file("lib/agent_coordinator/task_registry.ex")
Code.require_file("lib/agent_coordinator/mcp_server.ex")
Code.require_file("lib/agent_coordinator/auto_heartbeat.ex")
Code.require_file("lib/agent_coordinator/enhanced_mcp_server.ex")
Code.require_file("lib/agent_coordinator/client.ex")

defmodule AutoHeartbeatDemo do
  @moduledoc """
  Demonstrates the automatic heartbeat functionality
  """

  def run do
    IO.puts("🚀 Starting Auto-Heartbeat Demo")
    IO.puts("================================")

    # Start the core services
    start_services()

    # Demo 1: Basic client with auto-heartbeat
    demo_basic_client()

    # Demo 2: Multiple agents with coordination
    demo_multiple_agents()

    # Demo 3: Task creation and completion with heartbeats
    demo_task_workflow()

    IO.puts("\n✅ Demo completed!")
  end

  defp start_services do
    IO.puts("\n📡 Starting coordination services...")
    
    # Start registry for inboxes
    Registry.start_link(keys: :unique, name: AgentCoordinator.InboxRegistry)
    
    # Start dynamic supervisor
    DynamicSupervisor.start_link(name: AgentCoordinator.InboxSupervisor, strategy: :one_for_one)
    
    # Start task registry (without NATS for demo)
    AgentCoordinator.TaskRegistry.start_link()
    
    # Start MCP servers
    AgentCoordinator.MCPServer.start_link()
    AgentCoordinator.AutoHeartbeat.start_link()
    AgentCoordinator.EnhancedMCPServer.start_link()
    
    Process.sleep(500)  # Let services initialize
    IO.puts("✅ Services started")
  end

  defp demo_basic_client do
    IO.puts("\n🤖 Demo 1: Basic Client with Auto-Heartbeat")
    IO.puts("-------------------------------------------")

    # Start a client session
    {:ok, client} = AgentCoordinator.Client.start_session(
      "DemoAgent1", 
      [:coding, :analysis],
      auto_heartbeat: true,
      heartbeat_interval: 3000  # 3 seconds for demo
    )

    # Get session info
    {:ok, info} = AgentCoordinator.Client.get_session_info(client)
    IO.puts("Agent registered: #{info.agent_name} (ID: #{info.agent_id})")
    IO.puts("Auto-heartbeat enabled: #{info.auto_heartbeat_enabled}")

    # Check task board to see the agent
    {:ok, board} = AgentCoordinator.Client.get_task_board(client)
    agent = Enum.find(board.agents, fn a -> a["agent_id"] == info.agent_id end)
    
    IO.puts("Agent status: #{agent["status"]}")
    IO.puts("Agent online: #{agent["online"]}")
    IO.puts("Session active: #{agent["session_active"]}")

    # Wait and check heartbeat activity
    IO.puts("\n⏱️  Waiting 8 seconds to observe automatic heartbeats...")
    Process.sleep(8000)

    # Check board again
    {:ok, updated_board} = AgentCoordinator.Client.get_task_board(client)
    updated_agent = Enum.find(updated_board.agents, fn a -> a["agent_id"] == info.agent_id end)
    
    IO.puts("Agent still online: #{updated_agent["online"]}")
    IO.puts("Active sessions: #{updated_board.active_sessions}")

    # Stop the client
    AgentCoordinator.Client.stop_session(client)
    IO.puts("✅ Client session stopped")
  end

  defp demo_multiple_agents do
    IO.puts("\n👥 Demo 2: Multiple Agents Coordination")
    IO.puts("--------------------------------------")

    # Start multiple agents
    agents = []

    {:ok, agent1} = AgentCoordinator.Client.start_session("CodingAgent", [:coding, :testing])
    {:ok, agent2} = AgentCoordinator.Client.start_session("AnalysisAgent", [:analysis, :documentation])
    {:ok, agent3} = AgentCoordinator.Client.start_session("ReviewAgent", [:review, :analysis])

    agents = [agent1, agent2, agent3]

    # Check the task board
    {:ok, board} = AgentCoordinator.Client.get_task_board(agent1)
    IO.puts("Total agents: #{length(board.agents)}")
    IO.puts("Active sessions: #{board.active_sessions}")

    Enum.each(board.agents, fn agent ->
      if agent["online"] do
        IO.puts("  - #{agent["name"]}: #{Enum.join(agent["capabilities"], ", ")} (ONLINE)")
      else
        IO.puts("  - #{agent["name"]}: #{Enum.join(agent["capabilities"], ", ")} (offline)")
      end
    end)

    # Demonstrate heartbeat coordination
    IO.puts("\n💓 All agents sending heartbeats...")
    
    # Each agent does some activity
    Enum.each(agents, fn agent ->
      AgentCoordinator.Client.heartbeat(agent)
    end)

    Process.sleep(1000)

    # Check board after activity
    {:ok, updated_board} = AgentCoordinator.Client.get_task_board(agent1)
    online_count = Enum.count(updated_board.agents, fn a -> a["online"] end)
    IO.puts("Agents online after heartbeat activity: #{online_count}/#{length(updated_board.agents)}")

    # Cleanup
    Enum.each(agents, &AgentCoordinator.Client.stop_session/1)
    IO.puts("✅ All agents disconnected")
  end

  defp demo_task_workflow do
    IO.puts("\n📋 Demo 3: Task Workflow with Heartbeats")
    IO.puts("---------------------------------------")

    # Start an agent
    {:ok, agent} = AgentCoordinator.Client.start_session("WorkflowAgent", [:coding, :testing])

    # Create a task
    task_result = AgentCoordinator.Client.create_task(
      agent,
      "Fix Bug #123",
      "Fix the authentication bug in user login",
      %{
        "priority" => "high",
        "file_paths" => ["lib/auth.ex", "test/auth_test.exs"],
        "required_capabilities" => ["coding", "testing"]
      }
    )

    case task_result do
      {:ok, task_data} ->
        IO.puts("✅ Task created: #{task_data["task_id"]}")
        
        # Check heartbeat metadata
        if Map.has_key?(task_data, "_heartbeat_metadata") do
          metadata = task_data["_heartbeat_metadata"]
          IO.puts("   Heartbeat metadata: Agent #{metadata["agent_id"]} at #{metadata["timestamp"]}")
        end

      {:error, reason} ->
        IO.puts("❌ Task creation failed: #{reason}")
    end

    # Try to get next task
    case AgentCoordinator.Client.get_next_task(agent) do
      {:ok, task} ->
        if Map.has_key?(task, "task_id") do
          IO.puts("📝 Got task: #{task["title"]}")
          
          # Simulate some work
          IO.puts("⚙️  Working on task...")
          Process.sleep(2000)
          
          # Complete the task
          case AgentCoordinator.Client.complete_task(agent) do
            {:ok, result} ->
              IO.puts("✅ Task completed: #{result["task_id"]}")
            
            {:error, reason} ->
              IO.puts("❌ Task completion failed: #{reason}")
          end
        else
          IO.puts("📝 No tasks available: #{task["message"]}")
        end

      {:error, reason} ->
        IO.puts("❌ Failed to get task: #{reason}")
    end

    # Final status check
    {:ok, final_info} = AgentCoordinator.Client.get_session_info(agent)
    IO.puts("Final session info:")
    IO.puts("  - Last heartbeat: #{final_info.last_heartbeat}")
    IO.puts("  - Session duration: #{final_info.session_duration} seconds")

    # Cleanup
    AgentCoordinator.Client.stop_session(agent)
    IO.puts("✅ Workflow demo completed")
  end
end

# Run the demo
AutoHeartbeatDemo.run()