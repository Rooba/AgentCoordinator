# Test enhanced Agent Coordinator with auto-heartbeat and unregister

# Start a client with automatic heartbeat
IO.puts "🚀 Testing Enhanced Agent Coordinator"
IO.puts "====================================="

{:ok, client1} = AgentCoordinator.Client.start_session("TestAgent1", [:coding, :analysis])

# Get session info  
{:ok, info} = AgentCoordinator.Client.get_session_info(client1)
IO.puts "✅ Agent registered: #{info.agent_name} (#{info.agent_id})"
IO.puts "   Auto-heartbeat: #{info.auto_heartbeat_enabled}"

# Check task board
{:ok, board} = AgentCoordinator.Client.get_task_board(client1)
IO.puts "📊 Task board status:"
IO.puts "   Total agents: #{length(board.agents)}"
IO.puts "   Active sessions: #{board.active_sessions}"

# Find our agent on the board
our_agent = Enum.find(board.agents, fn a -> a["agent_id"] == info.agent_id end)
IO.puts "   Our agent online: #{our_agent["online"]}"
IO.puts "   Session active: #{our_agent["session_active"]}"

# Test heartbeat functionality
IO.puts "\n💓 Testing manual heartbeat..."
{:ok, _} = AgentCoordinator.Client.heartbeat(client1)
IO.puts "   Heartbeat sent successfully"

# Wait to observe automatic heartbeats
IO.puts "\n⏱️  Waiting 3 seconds to observe automatic heartbeats..."
Process.sleep(3000)

{:ok, updated_info} = AgentCoordinator.Client.get_session_info(client1)
IO.puts "   Last heartbeat updated: #{DateTime.diff(updated_info.last_heartbeat, info.last_heartbeat) > 0}"

# Test unregister functionality
IO.puts "\n🔄 Testing unregister functionality..."
{:ok, result} = AgentCoordinator.Client.unregister_agent(client1, "Testing unregister from script")
IO.puts "   Unregister result: #{result["status"]}"

# Check agent status after unregister
{:ok, final_board} = AgentCoordinator.Client.get_task_board(client1)
final_agent = Enum.find(final_board.agents, fn a -> a["agent_id"] == info.agent_id end)

case final_agent do
  nil -> 
    IO.puts "   Agent removed from board ✅"
  agent ->
    IO.puts "   Agent still on board, online: #{agent["online"]}"
end

# Test task creation
IO.puts "\n📝 Testing task creation with heartbeats..."
{:ok, task_result} = AgentCoordinator.Client.create_task(
  client1, 
  "Test Task", 
  "A test task to verify heartbeat integration",
  %{"priority" => "normal"}
)

IO.puts "   Task created: #{task_result["task_id"]}"
if Map.has_key?(task_result, "_heartbeat_metadata") do
  IO.puts "   Heartbeat metadata included ✅"
else
  IO.puts "   No heartbeat metadata ❌"  
end

# Clean up
AgentCoordinator.Client.stop_session(client1)
IO.puts "\n✨ Test completed successfully!"
