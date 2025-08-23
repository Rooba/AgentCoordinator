#!/bin/bash

# Quick test script to verify Agentecho "💡 Next steps:"
echo "   1. Run scripts/setup.sh to configure VS Code integration"
echo "   2. Or test manually with: scripts/mcp_launcher.sh"rdinator works without getting stuck

echo "🧪 Quick AgentCoordinator Test"
echo "=============================="

cd "$(dirname "$0")"

echo "📋 Testing basic compilation..."
if mix compile --force >/dev/null 2>&1; then
    echo "✅ Compilation successful"
else
    echo "❌ Compilation failed"
    exit 1
fi

echo "📋 Testing application startup (without persistence)..."
if timeout 10 mix run -e "
Application.put_env(:agent_coordinator, :enable_persistence, false)
{:ok, _apps} = Application.ensure_all_started(:agent_coordinator)
IO.puts('✅ Application started successfully')

# Quick MCP server test
response = AgentCoordinator.MCPServer.handle_mcp_request(%{
  \"jsonrpc\" => \"2.0\",
  \"id\" => 1,
  \"method\" => \"tools/list\"
})

case response do
  %{\"result\" => %{\"tools\" => tools}} when is_list(tools) ->
    IO.puts(\"✅ MCP server working (#{length(tools)} tools available)\")
  _ ->
    IO.puts(\"❌ MCP server not responding correctly\")
end

System.halt(0)
"; then
    echo "✅ Quick test passed!"
else
    echo "❌ Quick test failed"
    exit 1
fi

echo ""
echo "🎉 AgentCoordinator is ready!"
echo ""
echo "🚀 Next steps:"
echo "   1. Run ./setup.sh to configure VS Code integration"
echo "   2. Or test manually with: ./mcp_launcher.sh"
echo "   3. Or run Python example: python3 mcp_client_example.py"