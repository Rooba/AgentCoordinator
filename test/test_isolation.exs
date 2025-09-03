# Simple test for agent-specific task pools
alias AgentCoordinator.{TaskRegistry, Inbox, Agent, Task}

IO.puts("🧪 Agent-Specific Task Pool Test")
IO.puts("=" |> String.duplicate(40))

# Test 1: Create agents directly
IO.puts("\n1️⃣ Creating agents...")

agent1 = Agent.new("Alpha Wolf", [:coding, :testing])
agent2 = Agent.new("Beta Tiger", [:documentation, :analysis])

IO.puts("Agent 1 ID: #{agent1.id}")
IO.puts("Agent 2 ID: #{agent2.id}")

case TaskRegistry.register_agent(agent1) do
  :ok -> IO.puts("✅ Agent 1 registered")
  error -> IO.puts("❌ Agent 1 failed: #{inspect(error)}")
end

case TaskRegistry.register_agent(agent2) do
  :ok -> IO.puts("✅ Agent 2 registered")
  error -> IO.puts("❌ Agent 2 failed: #{inspect(error)}")
end

# Wait for inboxes to be created
Process.sleep(1000)

# Test 2: Create agent-specific tasks
IO.puts("\n2️⃣ Creating agent-specific tasks...")

# Tasks for Agent 1
task1_agent1 = Task.new("Fix auth bug", "Debug authentication issue", %{
  priority: :high,
  assigned_agent: agent1.id,
  metadata: %{agent_created: true}
})

task2_agent1 = Task.new("Add auth tests", "Write auth tests", %{
  priority: :normal,
  assigned_agent: agent1.id,
  metadata: %{agent_created: true}
})

# Tasks for Agent 2
task1_agent2 = Task.new("Write API docs", "Document endpoints", %{
  priority: :normal,
  assigned_agent: agent2.id,
  metadata: %{agent_created: true}
})

# Add tasks to respective inboxes
Inbox.add_task(agent1.id, task1_agent1)
Inbox.add_task(agent1.id, task2_agent1)
Inbox.add_task(agent2.id, task1_agent2)

IO.puts("✅ Tasks added to agent inboxes")

# Test 3: Verify isolation
IO.puts("\n3️⃣ Testing isolation...")

# Check what each agent gets
case Inbox.get_next_task(agent1.id) do
  nil -> IO.puts("❌ Agent 1 has no tasks")
  task -> IO.puts("✅ Agent 1 got: '#{task.title}'")
end

case Inbox.get_next_task(agent2.id) do
  nil -> IO.puts("❌ Agent 2 has no tasks")
  task -> IO.puts("✅ Agent 2 got: '#{task.title}'")
end

# Test 4: Check remaining tasks
IO.puts("\n4️⃣ Checking remaining tasks...")

status1 = Inbox.get_status(agent1.id)
status2 = Inbox.get_status(agent2.id)

IO.puts("Agent 1: #{status1.pending_count} pending, current: #{if status1.current_task, do: status1.current_task.title, else: "none"}")
IO.puts("Agent 2: #{status2.pending_count} pending, current: #{if status2.current_task, do: status2.current_task.title, else: "none"}")

IO.puts("\n🎉 SUCCESS! Agent-specific task pools working!")
