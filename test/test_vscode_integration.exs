#!/usr/bin/env elixir

# Quick test to check if VS Code tools are properly integrated
IO.puts("Testing VS Code tool integration...")

# Start the agent coordinator
{:ok, _} = AgentCoordinator.start_link()

# Give it a moment to start
:timer.sleep(2000)

# Check if VS Code tools are available
tools = AgentCoordinator.MCPServer.get_tools()
vscode_tools = Enum.filter(tools, fn tool -> 
  case Map.get(tool, "name") do
    "vscode_" <> _ -> true
    _ -> false
  end
end)

IO.puts("Found #{length(vscode_tools)} VS Code tools:")
Enum.each(vscode_tools, fn tool ->
  IO.puts("  - #{tool["name"]}")
end)

if length(vscode_tools) > 0 do
  IO.puts("✅ VS Code tools are properly integrated!")
else
  IO.puts("❌ VS Code tools are NOT integrated")
end