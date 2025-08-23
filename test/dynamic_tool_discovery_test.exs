defmodule AgentCoordinator.DynamicToolDiscoveryTest do
  use ExUnit.Case, async: false  # Changed to false since we're using shared resources

  describe "Dynamic tool discovery" do
    test "tools are discovered from external MCP servers via tools/list" do
      # Use the shared MCP server manager (started by application supervision tree)

      # Get initial tools - should include coordinator tools and external servers
      initial_tools = AgentCoordinator.MCPServerManager.get_unified_tools()

      # Should have at least the coordinator native tools
      coordinator_tool_names = ["register_agent", "create_task", "get_next_task", "complete_task", "get_task_board", "heartbeat"]

      Enum.each(coordinator_tool_names, fn tool_name ->
        assert Enum.any?(initial_tools, fn tool -> tool["name"] == tool_name end),
          "Coordinator tool #{tool_name} should be available"
      end)

      # Verify VS Code tools are conditionally included
      vscode_tools = Enum.filter(initial_tools, fn tool ->
        String.starts_with?(tool["name"], "vscode_")
      end)

      # Should have VS Code tools if the module is available
      if Code.ensure_loaded?(AgentCoordinator.VSCodeToolProvider) do
        assert length(vscode_tools) > 0, "VS Code tools should be available when module is loaded"
      else
        assert length(vscode_tools) == 0, "VS Code tools should not be available when module is not loaded"
      end

      # Test tool refresh functionality
      {:ok, tool_count} = AgentCoordinator.MCPServerManager.refresh_tools()
      assert is_integer(tool_count) and tool_count >= length(coordinator_tool_names)

      # No cleanup needed - using shared instance
    end

    test "tool routing works with dynamic discovery" do
      # Use the shared MCP server manager

      # Test routing for coordinator tools
      result = AgentCoordinator.MCPServerManager.route_tool_call(
        "register_agent",
        %{"name" => "TestAgent", "capabilities" => ["testing"]},
        %{agent_id: "test_#{:rand.uniform(1000)}"}
      )

      # Should succeed (returns :ok for register_agent)
      assert result == :ok or (is_map(result) and not Map.has_key?(result, "error"))

      # Test routing for non-existent tool
      error_result = AgentCoordinator.MCPServerManager.route_tool_call(
        "nonexistent_tool",
        %{},
        %{agent_id: "test"}
      )

      assert error_result["error"]["code"] == -32601
      assert String.contains?(error_result["error"]["message"], "Tool not found")

      # No cleanup needed - using shared instance
    end

    test "external server tools are discovered via MCP protocol" do
      # Use the shared MCP server manager

      # Verify the rediscovery function exists and can be called
      tools = AgentCoordinator.MCPServerManager.get_unified_tools()
      {:ok, tool_count} = AgentCoordinator.MCPServerManager.refresh_tools()

      assert is_integer(tool_count)
      assert tool_count >= 0

      # Verify we have external tools (context7, filesystem, etc.)
      external_tools = Enum.filter(tools, fn tool ->
        name = tool["name"]
        not String.starts_with?(name, "vscode_") and
        name not in ["register_agent", "create_task", "get_next_task", "complete_task", "get_task_board", "heartbeat"]
      end)

      # Should have some external tools from the configured MCP servers
      assert length(external_tools) > 0, "Should have external MCP server tools available"

      # No cleanup needed - using shared instance
    end
  end
end