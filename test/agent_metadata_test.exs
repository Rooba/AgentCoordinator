defmodule AgentCoordinator.MetadataTest do
  use ExUnit.Case, async: true

  describe "Agent registration with metadata" do
    test "register agent with metadata through TaskRegistry" do
      # Use the existing TaskRegistry (started by application)

      # Test metadata structure
      metadata = %{
        client_type: "github_copilot",
        session_id: "test_session_123",
        vs_code_version: "1.85.0",
        auto_registered: true
      }

      agent_name = "MetadataTestAgent_#{:rand.uniform(1000)}"

      # Register agent with metadata
      result = AgentCoordinator.TaskRegistry.register_agent(
        agent_name,
        ["coding", "testing", "vscode_integration"],
        [metadata: metadata]
      )

      assert :ok = result

      # Retrieve agent and verify metadata
      {:ok, agent} = AgentCoordinator.TaskRegistry.get_agent_by_name(agent_name)

      assert agent.metadata[:client_type] == "github_copilot"
      assert agent.metadata[:session_id] == "test_session_123"
      assert agent.metadata[:vs_code_version] == "1.85.0"
      assert agent.metadata[:auto_registered] == true

      # Verify capabilities are preserved
      assert "coding" in agent.capabilities
      assert "testing" in agent.capabilities
      assert "vscode_integration" in agent.capabilities
    end

    test "register agent without metadata (legacy compatibility)" do
      # Use the existing TaskRegistry (started by application)

      agent_name = "LegacyTestAgent_#{:rand.uniform(1000)}"

      # Register agent without metadata (old way)
      result = AgentCoordinator.TaskRegistry.register_agent(
        agent_name,
        ["coding", "testing"]
      )

      assert :ok = result

      # Retrieve agent and verify empty metadata
      {:ok, agent} = AgentCoordinator.TaskRegistry.get_agent_by_name(agent_name)

      assert agent.metadata == %{}
      assert "coding" in agent.capabilities
      assert "testing" in agent.capabilities
    end

    test "Agent.new creates proper metadata structure" do
      # Test metadata handling in Agent.new
      metadata = %{
        test_key: "test_value",
        number: 42,
        boolean: true
      }

      agent = AgentCoordinator.Agent.new(
        "TestAgent",
        ["capability1"],
        [metadata: metadata]
      )

      assert agent.metadata[:test_key] == "test_value"
      assert agent.metadata[:number] == 42
      assert agent.metadata[:boolean] == true

      # Test default empty metadata
      agent_no_metadata = AgentCoordinator.Agent.new("NoMetadataAgent", ["capability1"])
      assert agent_no_metadata.metadata == %{}
    end
  end
end