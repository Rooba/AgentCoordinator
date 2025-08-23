# AgentCoordinator

A distributed task coordination system for AI agents built with Elixir and NATS.

## Overview

AgentCoordinator is a centralized task management system designed to enable multiple AI agents (Claude Code, GitHub Copilot, etc.) to work collaboratively on the same codebase without conflicts. It provides:

- **Distributed Task Management**: Centralized task queue with agent-specific inboxes
- **Conflict Resolution**: File-level locking prevents agents from working on the same files
- **Real-time Communication**: NATS messaging for instant coordination
- **Persistent Storage**: Event sourcing with configurable retention policies
- **MCP Integration**: Model Context Protocol server for agent communication
- **Fault Tolerance**: Elixir supervision trees ensure system resilience

## Architecture

```
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│   AI Agent 1    │    │   AI Agent 2     │    │   AI Agent N    │
│  (Claude Code)  │    │   (Copilot)      │    │      ...        │
└─────────┬───────┘    └─────────┬────────┘    └─────────┬───────┘
          │                      │                       │
          └──────────────────────┼───────────────────────┘
                                 │
                    ┌─────────────┴──────────────┐
                    │    MCP Server Interface    │
                    └─────────────┬──────────────┘
                                 │
                    ┌─────────────┴──────────────┐
                    │    AgentCoordinator        │
                    │                            │
                    │  ┌──────────────────────┐  │
                    │  │   Task Registry      │  │
                    │  │   ┌──────────────┐   │  │
                    │  │   │ Agent Inbox  │   │  │
                    │  │   │ Agent Inbox  │   │  │
                    │  │   │ Agent Inbox  │   │  │
                    │  │   └──────────────┘   │  │
                    │  └──────────────────────┘  │
                    │                            │
                    │  ┌──────────────────────┐  │
                    │  │   NATS Messaging     │  │
                    │  └──────────────────────┘  │
                    │                            │
                    │  ┌──────────────────────┐  │
                    │  │   Persistence        │  │
                    │  │   (JetStream)        │  │
                    │  └──────────────────────┘  │
                    └────────────────────────────┘
```

## Installation

### Prerequisites

- Elixir 1.16+ and Erlang/OTP 28+
- NATS server (with JetStream enabled)

### Setup

1. **Install Dependencies**
   ```bash
   mix deps.get
   ```

2. **Start NATS Server**
   ```bash
   # Using Docker
   docker run -p 4222:4222 -p 8222:8222 nats:latest -js

   # Or install locally and run
   nats-server -js
   ```

3. **Configure Environment**
   ```bash
   export NATS_HOST=localhost
   export NATS_PORT=4222
   ```

4. **Start the Application**
   ```bash
   iex -S mix
   ```

## Usage

### Command Line Interface

```bash
# Register an agent
mix run -e "AgentCoordinator.CLI.main([\"register\", \"CodeBot\", \"coding\", \"testing\"])"

# Create a task
mix run -e "AgentCoordinator.CLI.main([\"create-task\", \"Fix login bug\", \"User login fails\", \"priority=high\"])"

# View task board
mix run -e "AgentCoordinator.CLI.main([\"board\"])"
```

### MCP Integration

Available MCP tools for agents:
- `register_agent` - Register a new agent
- `create_task` - Create a new task
- `get_next_task` - Get next task for agent
- `complete_task` - Mark current task complete
- `get_task_board` - View all agent statuses
- `heartbeat` - Send agent heartbeat

## Connecting to GitHub Copilot

### Step 1: Start the MCP Server

The AgentCoordinator MCP server needs to be running and accessible via stdio. Here's how to set it up:

1. **Create MCP Server Launcher Script**
   ```bash
   # Create a launcher script for the MCP server
   cat > mcp_launcher.sh << 'EOF'
   #!/bin/bash
   cd /home/ra/agent_coordinator
   export MIX_ENV=prod
   mix run --no-halt -e "
   # Start the application
   Application.ensure_all_started(:agent_coordinator)

   # Start MCP stdio interface
   IO.puts(\"MCP server started...\")

   # Read JSON-RPC messages from stdin and send responses to stdout
   spawn(fn ->
     Stream.repeatedly(fn -> IO.read(:stdio, :line) end)
     |> Stream.take_while(&(&1 != :eof))
     |> Enum.each(fn line ->
       case String.trim(line) do
         \"\" -> :ok
         json_line ->
           try do
             request = Jason.decode!(json_line)
             response = AgentCoordinator.MCPServer.handle_mcp_request(request)
             IO.puts(Jason.encode!(response))
           rescue
             e ->
               error_response = %{
                 \"jsonrpc\" => \"2.0\",
                 \"id\" => Map.get(Jason.decode!(json_line), \"id\", null),
                 \"error\" => %{\"code\" => -32603, \"message\" => Exception.message(e)}
               }
               IO.puts(Jason.encode!(error_response))
           end
       end
     end)
   end)

   # Keep process alive
   Process.sleep(:infinity)
   "
   EOF
   chmod +x mcp_launcher.sh
   ```

### Step 2: Configure VS Code for MCP

1. **Install Required Extensions**
   - Make sure you have the latest GitHub Copilot extension
   - Install any MCP-related VS Code extensions if available

2. **Create MCP Configuration**
   Create or update your VS Code settings to include the MCP server:

   ```json
   // In your VS Code settings.json or workspace settings
   {
     "github.copilot.advanced": {
       "mcp": {
         "servers": {
           "agent-coordinator": {
             "command": "/home/ra/agent_coordinator/mcp_launcher.sh",
             "args": [],
             "env": {}
           }
         }
       }
     }
   }
   ```

### Step 3: Alternative Direct Integration

If VS Code MCP integration isn't available yet, you can create a VS Code extension to bridge the gap:

1. **Create Extension Scaffold**
   ```bash
   mkdir agent-coordinator-extension
   cd agent-coordinator-extension
   npm init -y

   # Create package.json for VS Code extension
   cat > package.json << 'EOF'
   {
     "name": "agent-coordinator",
     "displayName": "Agent Coordinator",
     "description": "Integration with AgentCoordinator MCP server",
     "version": "0.1.0",
     "engines": { "vscode": "^1.74.0" },
     "categories": ["Other"],
     "activationEvents": ["*"],
     "main": "./out/extension.js",
     "contributes": {
       "commands": [
         {
           "command": "agentCoordinator.registerAgent",
           "title": "Register as Agent"
         },
         {
           "command": "agentCoordinator.getNextTask",
           "title": "Get Next Task"
         },
         {
           "command": "agentCoordinator.viewTaskBoard",
           "title": "View Task Board"
         }
       ]
     },
     "devDependencies": {
       "@types/vscode": "^1.74.0",
       "typescript": "^4.9.0"
     }
   }
   EOF
   ```

### Step 4: Direct Command Line Usage

For immediate use, you can interact with the MCP server directly:

1. **Start the Server**
   ```bash
   cd /home/ra/agent_coordinator
   iex -S mix
   ```

2. **In another terminal, use the MCP tools**
   ```bash
   # Test MCP server directly
   cd /home/ra/agent_coordinator
   mix run demo_mcp_server.exs
   ```

### Step 5: Production Deployment

1. **Create Systemd Service for MCP Server**
   ```bash
   sudo tee /etc/systemd/system/agent-coordinator-mcp.service > /dev/null << EOF
   [Unit]
   Description=Agent Coordinator MCP Server
   After=network.target nats.service
   Requires=nats.service

   [Service]
   Type=simple
   User=ra
   WorkingDirectory=/home/ra/agent_coordinator
   Environment=MIX_ENV=prod
   Environment=NATS_HOST=localhost
   Environment=NATS_PORT=4222
   ExecStart=/usr/bin/mix run --no-halt
   Restart=always
   RestartSec=5

   [Install]
   WantedBy=multi-user.target
   EOF

   sudo systemctl daemon-reload
   sudo systemctl enable agent-coordinator-mcp
   sudo systemctl start agent-coordinator-mcp
   ```

2. **Check Status**
   ```bash
   sudo systemctl status agent-coordinator-mcp
   sudo journalctl -fu agent-coordinator-mcp
   ```

