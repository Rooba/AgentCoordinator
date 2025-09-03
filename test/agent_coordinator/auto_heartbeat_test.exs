defmodule AgentCoordinator.AutoHeartbeatTest do
  use ExUnit.Case, async: true
  alias AgentCoordinator.{Client, EnhancedMCPServer, TaskRegistry}

  setup do
    # Start necessary services for testing
    {:ok, _} = Registry.start_link(keys: :unique, name: AgentCoordinator.InboxRegistry)

    {:ok, _} =
      DynamicSupervisor.start_link(name: AgentCoordinator.InboxSupervisor, strategy: :one_for_one)

    {:ok, _} = TaskRegistry.start_link()
    {:ok, _} = AgentCoordinator.MCPServer.start_link()
    {:ok, _} = AgentCoordinator.AutoHeartbeat.start_link()
    {:ok, _} = EnhancedMCPServer.start_link()

    :ok
  end

  describe "automatic heartbeat functionality" do
    test "agent automatically sends heartbeats during operations" do
      # Start a client with auto-heartbeat
      {:ok, client} =
        Client.start_session("TestAgent", [:coding],
          auto_heartbeat: true,
          heartbeat_interval: 1000
        )

      # Get initial session info
      {:ok, initial_info} = Client.get_session_info(client)
      initial_heartbeat = initial_info.last_heartbeat

      # Wait a bit for automatic heartbeat
      Process.sleep(1500)

      # Check that heartbeat was updated
      {:ok, updated_info} = Client.get_session_info(client)
      assert DateTime.compare(updated_info.last_heartbeat, initial_heartbeat) == :gt

      # Cleanup
      Client.stop_session(client)
    end

    test "agent stays online with regular heartbeats" do
      # Start client
      {:ok, client} =
        Client.start_session("OnlineAgent", [:analysis],
          auto_heartbeat: true,
          heartbeat_interval: 500
        )

      # Get agent info
      {:ok, session_info} = Client.get_session_info(client)
      agent_id = session_info.agent_id

      # Check task board initially
      {:ok, initial_board} = Client.get_task_board(client)
      agent = Enum.find(initial_board.agents, fn a -> a["agent_id"] == agent_id end)
      assert agent["online"] == true

      # Wait longer than heartbeat interval but not longer than online timeout
      Process.sleep(2000)

      # Agent should still be online due to automatic heartbeats
      {:ok, updated_board} = Client.get_task_board(client)
      updated_agent = Enum.find(updated_board.agents, fn a -> a["agent_id"] == agent_id end)
      assert updated_agent["online"] == true

      Client.stop_session(client)
    end

    test "multiple agents coordinate without collisions" do
      # Start multiple agents
      {:ok, agent1} = Client.start_session("Agent1", [:coding], auto_heartbeat: true)
      {:ok, agent2} = Client.start_session("Agent2", [:testing], auto_heartbeat: true)
      {:ok, agent3} = Client.start_session("Agent3", [:review], auto_heartbeat: true)

      # All should be online
      {:ok, board} = Client.get_task_board(agent1)
      online_agents = Enum.filter(board.agents, fn a -> a["online"] end)
      assert length(online_agents) >= 3

      # Create tasks from different agents simultaneously
      task1 =
        Task.async(fn ->
          Client.create_task(agent1, "Task1", "Description1", %{"priority" => "normal"})
        end)

      task2 =
        Task.async(fn ->
          Client.create_task(agent2, "Task2", "Description2", %{"priority" => "high"})
        end)

      task3 =
        Task.async(fn ->
          Client.create_task(agent3, "Task3", "Description3", %{"priority" => "low"})
        end)

      # All tasks should complete successfully
      {:ok, result1} = Task.await(task1)
      {:ok, result2} = Task.await(task2)
      {:ok, result3} = Task.await(task3)

      # Verify heartbeat metadata is included
      assert Map.has_key?(result1, "_heartbeat_metadata")
      assert Map.has_key?(result2, "_heartbeat_metadata")
      assert Map.has_key?(result3, "_heartbeat_metadata")

      # Cleanup
      Client.stop_session(agent1)
      Client.stop_session(agent2)
      Client.stop_session(agent3)
    end

    test "heartbeat metadata is included in responses" do
      {:ok, client} = Client.start_session("MetadataAgent", [:documentation])

      # Perform an operation
      {:ok, result} = Client.create_task(client, "Test Task", "Test Description")

      # Check for heartbeat metadata
      assert Map.has_key?(result, "_heartbeat_metadata")
      metadata = result["_heartbeat_metadata"]

      # Verify metadata structure
      {:ok, session_info} = Client.get_session_info(client)
      assert metadata["agent_id"] == session_info.agent_id
      assert Map.has_key?(metadata, "timestamp")
      assert Map.has_key?(metadata, "pre_heartbeat")
      assert Map.has_key?(metadata, "post_heartbeat")

      Client.stop_session(client)
    end

    test "session cleanup on client termination" do
      # Start client
      {:ok, client} = Client.start_session("CleanupAgent", [:coding])

      # Get session info
      {:ok, session_info} = Client.get_session_info(client)
      agent_id = session_info.agent_id

      # Verify agent is in task board
      {:ok, board} = Client.get_task_board(client)
      assert Enum.any?(board.agents, fn a -> a["agent_id"] == agent_id end)

      # Stop client
      Client.stop_session(client)

      # Give some time for cleanup
      Process.sleep(100)

      # Start another client to check board
      {:ok, checker_client} = Client.start_session("CheckerAgent", [:analysis])
      {:ok, updated_board} = Client.get_task_board(checker_client)

      # Original agent should show as offline or be cleaned up
      case Enum.find(updated_board.agents, fn a -> a["agent_id"] == agent_id end) do
        nil ->
          # Agent was cleaned up - this is acceptable
          :ok

        agent ->
          # Agent should be offline
          refute agent["online"]
      end

      Client.stop_session(checker_client)
    end
  end

  describe "enhanced task board" do
    test "provides session information" do
      {:ok, client} = Client.start_session("BoardAgent", [:analysis])

      {:ok, board} = Client.get_task_board(client)

      # Should have session metadata
      assert Map.has_key?(board, "active_sessions")
      assert board["active_sessions"] >= 1

      # Agents should have enhanced information
      agent = Enum.find(board.agents, fn a -> a["name"] == "BoardAgent" end)
      assert Map.has_key?(agent, "session_active")
      assert agent["session_active"] == true

      Client.stop_session(client)
    end
  end
end
