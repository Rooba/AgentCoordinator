# AgentCoordinator

[![Elixir CI](https://github.com/your-username/agent_coordinator/workflows/CI/badge.svg)](https://github.com/your-username/agent_coordinator/actions)
[![Coverage Status](https://coveralls.io/repos/github/your-username/agent_coordinator/badge.svg?branch=main)](https://coveralls.io/github/your-username/agent_coordinator?branch=main)
[![Hex.pm](https://img.shields.io/hexpm/v/agent_coordinator.svg)](https://hex.pm/packages/agent_coordinator)

A distributed task coordination system for AI agents built with Elixir and NATS.

## 🚀 Overview

AgentCoordinator enables multiple AI agents (Claude Code, GitHub Copilot, etc.) to work collaboratively on the same codebase without conflicts. It provides:

- **🎯 Distributed Task Management**: Centralized task queue with agent-specific inboxes
- **🔒 Conflict Resolution**: File-level locking prevents agents from working on the same files
- **⚡ Real-time Communication**: NATS messaging for instant coordination
- **💾 Persistent Storage**: Event sourcing with configurable retention policies
- **🔌 MCP Integration**: Model Context Protocol server for agent communication
- **🛡️ Fault Tolerance**: Elixir supervision trees ensure system resilience

## 🏗️ Architecture

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

## 📋 Prerequisites

- **Elixir**: 1.16+ 
- **Erlang/OTP**: 26+
- **NATS Server**: With JetStream enabled

## ⚡ Quick Start

### 1. Clone and Setup

```bash
git clone https://github.com/your-username/agent_coordinator.git
cd agent_coordinator
mix deps.get
```

### 2. Start NATS Server

```bash
# Using Docker (recommended)
docker run -p 4222:4222 -p 8222:8222 nats:latest -js

# Or install locally and run
nats-server -js -p 4222 -m 8222
```

### 3. Run the Application

```bash
# Start in development mode
iex -S mix

# Or use the provided setup script
./scripts/setup.sh
```

### 4. Test the MCP Server

```bash
# Run example demo
mix run examples/demo_mcp_server.exs

# Or test with Python client
python3 examples/mcp_client_example.py
```

## 🔧 Configuration

### Environment Variables

```bash
export NATS_HOST=localhost
export NATS_PORT=4222
export MIX_ENV=dev
```

### VS Code Integration

Run the setup script to configure VS Code automatically:

```bash
./scripts/setup.sh
```

Or manually configure your VS Code `settings.json`:

```json
{
  "github.copilot.advanced": {
    "mcp": {
      "servers": {
        "agent-coordinator": {
          "command": "/path/to/agent_coordinator/scripts/mcp_launcher.sh",
          "args": [],
          "env": {
            "MIX_ENV": "dev",
            "NATS_HOST": "localhost",
            "NATS_PORT": "4222"
          }
        }
      }
    }
  }
}
```

## 🎮 Usage

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

- `register_agent` - Register a new agent with capabilities
- `create_task` - Create a new task with priority and requirements
- `get_next_task` - Get the next available task for an agent
- `complete_task` - Mark the current task as completed
- `get_task_board` - View all agents and their current status
- `heartbeat` - Send agent heartbeat to maintain active status

### API Example

```elixir
# Register an agent
{:ok, agent_id} = AgentCoordinator.register_agent("MyAgent", ["coding", "testing"])

# Create a task
{:ok, task_id} = AgentCoordinator.create_task(
  "Implement user authentication", 
  "Add JWT-based authentication to the API",
  priority: :high,
  required_capabilities: ["coding", "security"]
)

# Get next task for agent
{:ok, task} = AgentCoordinator.get_next_task(agent_id)

# Complete the task
:ok = AgentCoordinator.complete_task(agent_id, "Authentication implemented successfully")
```

## 🧪 Development

### Running Tests

```bash
# Run all tests
mix test

# Run with coverage
mix test --cover

# Run specific test file
mix test test/agent_coordinator/mcp_server_test.exs
```

### Code Quality

```bash
# Format code
mix format

# Run static analysis
mix credo

# Run Dialyzer for type checking
mix dialyzer
```

### Available Scripts

- `scripts/setup.sh` - Complete environment setup
- `scripts/mcp_launcher.sh` - Start MCP server
- `scripts/minimal_test.sh` - Quick functionality test
- `scripts/quick_test.sh` - Comprehensive test suite

## 📁 Project Structure

```
agent_coordinator/
├── lib/                    # Application source code
│   ├── agent_coordinator.ex
│   └── agent_coordinator/
│       ├── agent.ex
│       ├── application.ex
│       ├── cli.ex
│       ├── inbox.ex
│       ├── mcp_server.ex
│       ├── persistence.ex
│       ├── task_registry.ex
│       └── task.ex
├── test/                   # Test files
├── examples/               # Example implementations
│   ├── demo_mcp_server.exs
│   ├── mcp_client_example.py
│   └── full_workflow_demo.exs
├── scripts/                # Utility scripts
│   ├── setup.sh
│   ├── mcp_launcher.sh
│   └── minimal_test.sh
├── mix.exs                 # Project configuration
├── README.md               # This file
└── CHANGELOG.md            # Version history
```

## 🤝 Contributing

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add some amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

Please read [CONTRIBUTING.md](CONTRIBUTING.md) for details on our code of conduct and development process.

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🙏 Acknowledgments

- [NATS](https://nats.io/) for providing the messaging infrastructure
- [Elixir](https://elixir-lang.org/) community for the excellent ecosystem
- [Model Context Protocol](https://modelcontextprotocol.io/) for agent communication standards

## 📞 Support

- 📖 [Documentation](https://hexdocs.pm/agent_coordinator)
- 🐛 [Issue Tracker](https://github.com/your-username/agent_coordinator/issues)
- 💬 [Discussions](https://github.com/your-username/agent_coordinator/discussions)

---

Made with ❤️ by the AgentCoordinator team