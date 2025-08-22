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

