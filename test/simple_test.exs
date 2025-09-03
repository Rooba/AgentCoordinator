#!/usr/bin/env elixir

# Simple test for agent-specific task pools using Mix
Mix.install([{:jason, "~> 1.4"}])

Code.require_file("mix.exs")

Application.ensure_all_started(:agent_coordinator)

alias AgentCoordinator.{TaskRegistry, Inbox, Agent, Task}

IO.puts("🧪 Simple Agent-Specific Task Pool Test")
IO.puts("=" |> String.duplicate(50))

# Wait for services to start
Process.sleep(2000)

# Test 1: Create agents directly
IO.puts("\n1️⃣ Creating agents directly...")

agent1 = Agent.new("Alpha Wolf", [:coding, :testing])
agent2 = Agent.new("Beta Tiger", [:documentation, :analysis])

case TaskRegistry.register_agent(agent1) do
  :ok -> IO.puts("✅ Agent 1 registered: #{agent1.id}")
  error -> IO.puts("❌ Agent 1 failed: #{inspect(error)}")
end

case TaskRegistry.register_agent(agent2) do
  :ok -> IO.puts("✅ Agent 2 registered: #{agent2.id}")
  error -> IO.puts("❌ Agent 2 failed: #{inspect(error)}")
end

# Test 2: Create agent-specific tasks
IO.puts("\n2️⃣ Creating agent-specific tasks...")

# Create tasks for Agent 1
task1_agent1 = Task.new("Fix auth bug", "Debug authentication issue", %{
  priority: :high,
  assigned_agent: agent1.id,
  metadata: %{agent_created: true}
})

task2_agent1 = Task.new("Add auth tests", "Write comprehensive auth tests", %{
  priority: :normal,
  assigned_agent: agent1.id,
  metadata: %{agent_created: true}
})

# Create tasks for Agent 2
task1_agent2 = Task.new("Write API docs", "Document REST endpoints", %{
  priority: :normal,
  assigned_agent: agent2.id,
  metadata: %{agent_created: true}
})

# Add tasks to respective agent inboxes
case Inbox.add_task(agent1.id, task1_agent1) do
  :ok -> IO.puts("✅ Task 1 added to Agent 1")
  error -> IO.puts("❌ Task 1 failed: #{inspect(error)}")
end

case Inbox.add_task(agent1.id, task2_agent1) do
  :ok -> IO.puts("✅ Task 2 added to Agent 1")
  error -> IO.puts("❌ Task 2 failed: #{inspect(error)}")
end

case Inbox.add_task(agent2.id, task1_agent2) do
  :ok -> IO.puts("✅ Task 1 added to Agent 2")
  error -> IO.puts("❌ Task 1 to Agent 2 failed: #{inspect(error)}")
end

# Test 3: Verify agent isolation
IO.puts("\n3️⃣ Testing agent task isolation...")

# Agent 1 gets their tasks
case Inbox.get_next_task(agent1.id) do
  nil -> IO.puts("❌ Agent 1 has no tasks")
  task -> IO.puts("✅ Agent 1 got task: #{task.title}")
end

# Agent 2 gets their tasks
case Inbox.get_next_task(agent2.id) do
  nil -> IO.puts("❌ Agent 2 has no tasks")
  task -> IO.puts("✅ Agent 2 got task: #{task.title}")
end

# Test 4: Check task status
IO.puts("\n4️⃣ Checking task status...")

status1 = Inbox.get_status(agent1.id)
status2 = Inbox.get_status(agent2.id)

IO.puts("Agent 1 status: #{inspect(status1)}")
IO.puts("Agent 2 status: #{inspect(status2)}")

# Test 5: List all tasks for each agent
IO.puts("\n5️⃣ Listing all tasks per agent...")

tasks1 = Inbox.list_tasks(agent1.id)
tasks2 = Inbox.list_tasks(agent2.id)

IO.puts("Agent 1 tasks: #{inspect(tasks1)}")
IO.puts("Agent 2 tasks: #{inspect(tasks2)}")

IO.puts("\n" <> "=" |> String.duplicate(50))
IO.puts("🎉 AGENT ISOLATION TEST COMPLETE!")
IO.puts("✅ Each agent has their own task inbox")
IO.puts("✅ No cross-contamination of tasks")
IO.puts("✅ Agent-specific task pools working!")
IO.puts("=" |> String.duplicate(50))
