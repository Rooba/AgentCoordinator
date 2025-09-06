# Agent Coordinator

A **Model Context Protocol (MCP) server** that enables multiple AI agents to coordinate their work seamlessly across codebases without conflicts. Built with Elixir for reliability and fault tolerance.

## 🎯 What is Agent Coordinator?

Agent Coordinator is a **unified MCP proxy server** that enables multiple AI agents to collaborate seamlessly without conflicts. As shown in the architecture diagram above, it acts as a single interface connecting multiple agents (Purple Zebra, Yellow Elephant, etc.) to a comprehensive ecosystem of tools and task management.

**The coordinator orchestrates three core components:**
- **Task Registry**: Intelligent task queuing, agent matching, and automatic progress tracking
- **Agent Manager**: Agent registration, heartbeat monitoring, and capability-based assignment
- **Codebase Registry**: Cross-repository coordination, dependency management, and workspace organization

**Plus a Unified Tool Registry** that seamlessly combines:
- Native coordination tools (register_agent, get_next_task, etc.)
- Proxied MCP tools from external servers (read_file, search_memory, etc.)
- VS Code integration tools (get_active_editor, run_command, etc.)

Instead of agents conflicting over files or duplicating work, they connect through a single MCP interface that automatically routes tool calls, tracks all operations as coordinated tasks, and maintains real-time communication via personal agent inboxes and shared task boards.

**Key Features:**

- **🤖 Multi-Agent Coordination**: Register multiple AI agents (GitHub Copilot, Claude, etc.) with different capabilities
- **� Unified MCP Proxy**: Single MCP server that manages and unifies multiple external MCP servers
- **📡 External Server Management**: Automatically starts, monitors, and manages MCP servers defined in `mcp_servers.json`
- **🛠️ Universal Tool Registry**: Combines tools from all external servers with native coordination tools
- **🎯 Intelligent Tool Routing**: Automatically routes tool calls to the appropriate server or handles natively
- **📝 Automatic Task Tracking**: Every tool usage becomes a tracked task with agent coordination
- **⚡ Real-Time Communication**: Agents can communicate and share progress via heartbeat system
- **🔌 Dynamic Tool Discovery**: Automatically discovers new tools when external servers start/restart
- **🎮 Cross-Codebase Support**: Coordinate work across multiple repositories and projects
- **🔌 MCP Standard Compliance**: Works with any MCP-compatible AI agent or tool

## 🚀 How It Works

```ascii
                        ┌────────────────────────────┐
                        │AI AGENTS & TOOLS CONNECTION│
                        └────────────────────────────┘
    Agent 1 (Purple Zebra)   Agent 2(Yellow Elephant)    Agent N (...)
           │                        │                            │
           └────────────MCP Protocol┼(Single Interface)──────────┘
                                    │
    ┌───────────────────────────────┴──────────────────────────────────┐
    │               AGENT COORDINATOR (Unified MCP Server)             │
    ├──────────────────────────────────────────────────────────────────┤
    │  ┌─────────────────┐  ┌─────────────────┐  ┌──────────────────┐  │
    │  │  Task Registry  │  │ Agent Manager   │  │Codebase Registry │  │
    │  ├─────────────────┤  ├─────────────────┤  ├──────────────────┤  │
    │  │• Task Queuing   │  │• Registration   │  │• Cross-Repo      │  │
    │  │• Agent Matching │  │• Heartbeat      │  │• Dependencies    │  │
    │  │• Auto-Tracking  │  │• Capabilities   │  │• Workspace Mgmt  │  │
    │  └─────────────────┘  └─────────────────┘  └──────────────────┘  │
    │  ┌─────────────────────────────────────────────────────────────┐ │
    │  │                    UNIFIED TOOL REGISTRY                    │ │
    │  ├─────────────────────────────────────────────────────────────┤ │
    │  │ Native Tools:      register_agent, get_next_task,           │ ╞═══════════════════════════════════╕
    │  │                    create_task_set, complete_task, ...      │ │                                   │
    │  │ Proxied MCP Tools: read_file, write_file,                   │ │                       ┍━━━━━━━━━━━┷━━━━━━━━━━━┑
    │  │                    search_memory, get_docs, ...             │ │                       │       Task Board      │
    │  │ VS Code Tools:     get_active_editor, set_selection,        │ │ ┏━━━━━━━━━━━━━━━━━━━━┓┝━━━━━━━━━━━┳━━━━━━━━━━━┥ ┏━━━━━━━━━━━━━━━━━━━━┓
    │  │                    get_workspace_folders, run_command, ...  │ │ ┃    Agent 1 INBOX   ┃│ Agent 1 Q ┃ Agent 2 Q │ ┃    Agent 2 INBOX   ┃
    │  ├─────────────────────────────────────────────────────────────┤ │ ┣━━━━━━━━━━━━━━━━━━━━┫┝━━━━━━━━━━━╋━━━━━━━━━━━┥ ┣━━━━━━━━━━━━━━━━━━━━┫
    │  │       Routes to appropriate server or handles natively      │ │ ┃   current: task 3  ┃│ ✓ Task 1  ┃ ✓ Task 1  │ ┃   current: task 2  ┃
    │  │       Configure MCP Servers to run via MCP_TOOLS_FILE       │ │ ┃  [ complete task ] ┣┥ ✓ Task 2  ┃ ➔ Task 2  ┝━┫  [ complete task ] ┃<─┐
    │  └─────────────────────────────────────────────────────────────┘ │ ┗━━━━━━━━━━━━━━━━━━━━┛│ ➔ Task 3  ┃ … Task 3  │ ┗━━━━━━━━━━━━━━━━━━━━┛  │
    └─────────────────────────────────┬────────────────────────────────┘                       ┝━━━━━━━━━━━╋━━━━━━━━━━━┥                         │
                                      │                                                        │ Agent 3 Q ┃ Agent 4 Q │ ┏━━━━━━━━━━━━━━━━━━━━┓  │
                                      │                                                        ┝━━━━━━━━━━━╋━━━━━━━━━━━┥ ┃    Agent 4 INBOX   ┃<─┤ Personal inboxes
                                      │                                                        │ ✓ Task 1  ┃ ➔ Task 1  │ ┣━━━━━━━━━━━━━━━━━━━━┫  │
                                      │                                                        │ ✓ Task 2  ┃ … Task 2  │ ┃   current: task 2  ┃  │
    ┌─────────────────────────────────┴─────────────────────────────────────┐                  │ ✓ Task 3  ┃ … Task 3  ┝━┫  [ complete task ] ┃  │
    │                         EXTERNAL MCP SERVERS                          │                  ┕━━━━━┳━━━━━┻━━━━━━━━━━━┙ ┗━━━━━━━━━━━━━━━━━━━━┛  │
    └──────────────┬─────────┬─────────┬─────────┬─────────┬─────────┬──────┤             ┏━━━━━━━━━━┻━━━━━━━━━┓                                 │
         │         │         │         │         │         │         │      │             ┃    Agent 3 INBOX   ┃<━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┙
    ┌────┴───┐     │    ┌────┴───┐     │    ┌────┴───┐     │    ┌────┴───┐  │             ┣━━━━━━━━━━━━━━━━━━━━┫
    │  MCP 1 │     │    │  MCP 2 │     │    │  MCP 3 │     │    │  MCP 4 │  │             ┃   current: none    ┃
    ├────────┤     │    ├────────┤     │    ├────────┤     │    ├────────┤  │             ┃  [ view history ]  ┃
    │• tool 1│     │    │• tool 1│     │    │• tool 1│     │    │• tool 1│  │             ┗━━━━━━━━━━━━━━━━━━━━┛
    │• tool 2│     │    │• tool 2│     │    │• tool 2│     │    │• tool 2│  │
    │• tool 3│┌────┴───┐│• tool 3│┌────┴───┐│• tool 3│┌────┴───┐│• tool 3│┌─┴──────┐
    └────────┘│  MCP 5 │└────────┘│  MCP 6 │└────────┘│  MCP 7 │└────────┘│  MCP 8 │
              ├────────┤          ├────────┤          ├────────┤          ├────────┤
              │• tool 1│          │• tool 1│          │• tool 1│          │• tool 1│
              │• tool 2│          │• tool 2│          │• tool 2│          │• tool 2│
              │• tool 3│          │• tool 3│          │• tool 3│          │• tool 3│
              └────────┘          └────────┘          └────────┘          └────────┘



    🔥 WHAT HAPPENS:
    1. Agent Coordinator reads mcp_servers.json config
    2. Spawns & initializes all external MCP servers
    3. Discovers tools from each server via MCP protocol
    4. Builds unified tool registry (native + external)
    5. Presents single MCP interface to AI agents
    6. Routes tool calls to appropriate servers
    7. Automatically tracks all operations as tasks
    8. Maintains heartbeat & coordination across agents

```

## 🔧 MCP Server Management & Unified Tool Registry

Agent Coordinator acts as a **unified MCP proxy server** that manages multiple external MCP servers while providing its own coordination capabilities. This creates a single, powerful interface for AI agents to access hundreds of tools seamlessly.

### 📡 External Server Management

The coordinator automatically manages external MCP servers based on configuration in `mcp_servers.json`:

```json
{
  "servers": {
    "mcp_filesystem": {
      "type": "stdio",
      "command": "bunx",
      "args": ["-y", "@modelcontextprotocol/server-filesystem", "/home/ra"],
      "auto_restart": true,
      "description": "Filesystem operations server"
    },
    "mcp_memory": {
      "type": "stdio",
      "command": "bunx",
      "args": ["-y", "@modelcontextprotocol/server-memory"],
      "auto_restart": true,
      "description": "Memory and knowledge graph server"
    },
    "mcp_figma": {
      "type": "http",
      "url": "http://127.0.0.1:3845/mcp",
      "auto_restart": true,
      "description": "Figma design integration server"
    }
  },
  "config": {
    "startup_timeout": 30000,
    "heartbeat_interval": 10000,
    "auto_restart_delay": 1000,
    "max_restart_attempts": 3
  }
}
```

**Server Lifecycle Management:**

1. **🚀 Startup**: Reads config and spawns each external server process
2. **🔍 Discovery**: Sends MCP `initialize` and `tools/list` requests to discover available tools
3. **📋 Registration**: Adds discovered tools to the unified tool registry
4. **💓 Monitoring**: Continuously monitors server health and heartbeat
5. **🔄 Auto-Restart**: Automatically restarts failed servers (if configured)
6. **🛡️ Cleanup**: Properly terminates processes and cleans up resources on shutdown

### 🛠️ Unified Tool Registry

The coordinator combines tools from multiple sources into a single, coherent interface:

**Native Coordination Tools:**

- `register_agent` - Register agents with capabilities
- `create_task` - Create coordination tasks
- `get_next_task` - Get assigned tasks
- `complete_task` - Mark tasks complete
- `get_task_board` - View all agent status
- `heartbeat` - Maintain agent liveness

**External Server Tools (Auto-Discovered):**

- **Filesystem**: `read_file`, `write_file`, `list_directory`, `search_files`
- **Memory**: `search_nodes`, `store_memory`, `recall_information`
- **Context7**: `get-library-docs`, `search-docs`, `get-library-info`
- **Figma**: `get_code`, `get_designs`, `fetch_assets`
- **Sequential Thinking**: `sequentialthinking`, `analyze_problem`
- **VS Code**: `run_command`, `install_extension`, `open_file`, `create_task`

**Dynamic Discovery Process:**

```ascii
┌─────────────────┐    MCP Protocol    ┌─────────────────┐
│ Agent           │ ──────────────────▶│ Agent           │
│ Coordinator     │                    │ Coordinator     │
│                 │ initialize         │                 │
│ 1. Starts       │◀─────────────────  │ 2. Responds     │
│    External     │                    │    with info    │
│    Server       │ tools/list         │                 │
│                 │ ──────────────────▶│ 3. Returns      │
│ 4. Registers    │                    │    tool list    │
│    Tools        │◀─────────────────  │                 │
└─────────────────┘                    └─────────────────┘
```

### 🎯 Intelligent Tool Routing

When an AI agent calls a tool, the coordinator intelligently routes the request:

**Routing Logic:**

1. **Native Tools**: Handled directly by Agent Coordinator modules
2. **External Tools**: Routed to the appropriate external MCP server
3. **VS Code Tools**: Routed to integrated VS Code Tool Provider
4. **Unknown Tools**: Return helpful error with available alternatives

**Automatic Task Tracking:**

- Every tool call automatically creates or updates agent tasks
- Maintains context of what agents are working on
- Provides visibility into cross-agent coordination
- Enables intelligent task distribution and conflict prevention

**Example Tool Call Flow:**

```bash
Agent calls "read_file" → Coordinator routes to filesystem server →
Updates agent task → Sends heartbeat → Returns file content
```

## 🛠️ Prerequisites

Choose one of these installation methods:

### Option 1: Docker (Recommended - No Elixir Installation Required)

- **Docker**: 20.10+ and Docker Compose
- **Node.js**: 18+ (for external MCP servers via bun)

### Option 2: Manual Installation

- **Elixir**: 1.16+ with OTP 26+
- **Mix**: Comes with Elixir installation
- **Node.js**: 18+ (for external MCP servers via bun)

## ⚡ Quick Start

### Option A: Docker Setup (Easiest)

#### 1. Get the Code

```bash
git clone https://github.com/your-username/agent_coordinator.git
cd agent_coordinator
```

#### 2. Run with Docker Compose

```bash
# Start the full stack (MCP server + NATS + monitoring)
docker-compose up -d

# Or start just the MCP server
docker-compose up agent-coordinator

# Check logs
docker-compose logs -f agent-coordinator
```

#### 3. Configuration

Edit `mcp_servers.json` to configure external MCP servers, then restart:

```bash
docker-compose restart agent-coordinator
```

### Option B: Manual Setup

#### 1. Get the Code

```bash
git clone https://github.com/your-username/agent_coordinator.git
cd agent_coordinator
mix deps.get
```

#### 2. Start the MCP Server

```bash
# Start the MCP server directly
./scripts/mcp_launcher.sh

# Or in development mode
mix run --no-halt
```

### 3. Configure Your AI Tools

#### For Docker Setup

If using Docker, the MCP server is available at the container's stdio interface. Add this to your VS Code `settings.json`:

```json
{
  "github.copilot.advanced": {
    "mcp": {
      "servers": {
        "agent-coordinator": {
          "command": "docker",
          "args": ["exec", "-i", "agent-coordinator", "/app/scripts/mcp_launcher.sh"],
          "env": {
            "MIX_ENV": "prod"
          }
        }
      }
    }
  }
}
```

#### For Manual Setup

Add this to your VS Code `settings.json`:

```json
{
  "github.copilot.advanced": {
    "mcp": {
      "servers": {
        "agent-coordinator": {
          "command": "/path/to/agent_coordinator/scripts/mcp_launcher.sh",
          "args": [],
          "env": {
            "MIX_ENV": "dev"
          }
        }
      }
    }
  }
}
  }
}
```

### 4. Test It Works

#### Docker Testing

```bash
# Test with Docker
docker-compose exec agent-coordinator /app/bin/agent_coordinator ping

# Run example (if available in container)
docker-compose exec agent-coordinator mix run examples/full_workflow_demo.exs

# View logs
docker-compose logs -f agent-coordinator
```

#### Manual Testing

```bash
# Run the demo to see it in action
mix run examples/full_workflow_demo.exs
```

## 🐳 Docker Usage Guide

### Available Docker Commands

#### Basic Operations

```bash
# Build the image
docker build -t agent-coordinator .

# Run standalone container
docker run -d --name agent-coordinator -p 4000:4000 agent-coordinator

# Run with custom config
docker run -d \
  -v ./mcp_servers.json:/app/mcp_servers.json:ro \
  -p 4000:4000 \
  agent-coordinator
```

#### Docker Compose Operations

```bash
# Start full stack
docker-compose up -d

# Start only agent coordinator
docker-compose up -d agent-coordinator

# View logs
docker-compose logs -f agent-coordinator

# Restart after config changes
docker-compose restart agent-coordinator

# Stop everything
docker-compose down

# Remove volumes (reset data)
docker-compose down -v
```

#### Development with Docker

```bash
# Start in development mode
docker-compose -f docker-compose.yml -f docker-compose.dev.yml up

# Interactive shell for debugging
docker-compose exec agent-coordinator bash

# Run tests in container
docker-compose exec agent-coordinator mix test

# Watch logs during development
docker-compose logs -f
```

### Environment Variables

Configure the container using environment variables:

```bash
# docker-compose.override.yml example
version: '3.8'
services:
  agent-coordinator:
    environment:
      - MIX_ENV=prod
      - NATS_HOST=nats
      - NATS_PORT=4222
      - LOG_LEVEL=info
```

### Custom Configuration

#### External MCP Servers

Mount your own `mcp_servers.json`:

```bash
docker run -d \
  -v ./my-mcp-config.json:/app/mcp_servers.json:ro \
  agent-coordinator
```

#### Persistent Data

```bash
docker run -d \
  -v agent_data:/app/data \
  -v nats_data:/data \
  agent-coordinator
```

### Monitoring & Health Checks

#### Container Health

```bash
# Check container health
docker-compose ps

# Health check details
docker inspect --format='{{json .State.Health}}' agent-coordinator

# Manual health check
docker-compose exec agent-coordinator /app/bin/agent_coordinator ping
```

#### NATS Monitoring

Access NATS monitoring dashboard:
```bash
# Start with monitoring profile
docker-compose --profile monitoring up -d

# Access dashboard at http://localhost:8080
open http://localhost:8080
```

### Troubleshooting

#### Common Issues

```bash
# Check container logs
docker-compose logs agent-coordinator

# Check NATS connectivity
docker-compose exec agent-coordinator nc -z nats 4222

# Restart stuck container
docker-compose restart agent-coordinator

# Reset everything
docker-compose down -v && docker-compose up -d
```

#### Performance Tuning

```bash
# Allocate more memory
docker-compose up -d --scale agent-coordinator=1 \
  --memory=1g --cpus="2.0"
```

## 🎮 How to Use

Once your AI agents are connected via MCP, they can:

### Register as an Agent

```bash
# An agent identifies itself with capabilities
register_agent("GitHub Copilot", ["coding", "testing"], codebase_id: "my-project")
```

### Create Tasks

```bash
# Tasks are created with requirements
create_task("Fix login bug", "Authentication fails on mobile",
  priority: "high",
  required_capabilities: ["coding", "debugging"]
)
```

### Coordinate Automatically

The coordinator automatically:

- **Matches** tasks to agents based on capabilities
- **Queues** tasks when no suitable agents are available
- **Tracks** agent heartbeats to ensure they're still working
- **Handles** cross-codebase tasks that span multiple repositories

### Available MCP Tools

All MCP-compatible AI agents get these tools automatically:

| Tool | Purpose |
|------|---------|
| `register_agent` | Register an agent with capabilities |
| `create_task` | Create a new task with requirements |
| `get_next_task` | Get the next task assigned to an agent |
| `complete_task` | Mark current task as completed |
| `get_task_board` | View all agents and their status |
| `heartbeat` | Send agent heartbeat to stay active |
| `register_codebase` | Register a new codebase/repository |
| `create_cross_codebase_task` | Create tasks spanning multiple repos |

## 🧪 Development & Testing

### Running Tests

```bash
# Run all tests
mix test

# Run with coverage
mix test --cover

# Try the examples
mix run examples/full_workflow_demo.exs
mix run examples/auto_heartbeat_demo.exs
```

### Code Quality

```bash
# Format code
mix format

# Run static analysis
mix credo

# Type checking
mix dialyzer
```

## 📁 Project Structure

```text
agent_coordinator/
├── lib/
│   ├── agent_coordinator.ex           # Main module
│   └── agent_coordinator/
│       ├── mcp_server.ex             # MCP protocol implementation
│       ├── task_registry.ex          # Task management
│       ├── agent.ex                  # Agent management
│       ├── codebase_registry.ex      # Multi-repository support
│       └── application.ex            # Application supervisor
├── examples/                         # Working examples
├── test/                            # Test suite
├── scripts/                         # Helper scripts
└── docs/                            # Technical documentation
    ├── README.md                    # Documentation index
    ├── AUTO_HEARTBEAT.md            # Unified MCP server details
    ├── VSCODE_TOOL_INTEGRATION.md   # VS Code integration
    └── LANGUAGE_IMPLEMENTATIONS.md  # Alternative language guides
```

## 🤔 Why This Design?

**The Problem**: Multiple AI agents working on the same codebase step on each other, duplicate work, or create conflicts.

**The Solution**: A coordination layer that:

- Lets agents register their capabilities
- Intelligently distributes tasks
- Tracks progress and prevents conflicts
- Scales across multiple repositories

**Why Elixir?**: Built-in concurrency, fault tolerance, and excellent for coordination systems.

## 🚀 Alternative Implementations

While this Elixir version works great, you might want to consider these languages for broader adoption:

### Go Implementation

- **Pros**: Single binary deployment, great performance, large community
- **Cons**: More verbose concurrency patterns
- **Best for**: Teams wanting simple deployment and good performance

### Python Implementation

- **Pros**: Huge ecosystem, familiar to most developers, excellent tooling
- **Cons**: GIL limitations for true concurrency
- **Best for**: AI/ML teams already using Python ecosystem

### Rust Implementation

- **Pros**: Maximum performance, memory safety, growing adoption
- **Cons**: Steeper learning curve, smaller ecosystem
- **Best for**: Performance-critical deployments

### Node.js Implementation

- **Pros**: JavaScript familiarity, event-driven nature fits coordination
- **Cons**: Single-threaded limitations, callback complexity
- **Best for**: Web teams already using Node.js

## 🤝 Contributing

Contributions are welcome! Here's how:

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add some amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

See [CONTRIBUTING.md](CONTRIBUTING.md) for detailed guidelines.

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🙏 Acknowledgments

- [Model Context Protocol](https://modelcontextprotocol.io/) for the agent communication standard
- [Elixir](https://elixir-lang.org/) community for the excellent ecosystem
- AI development teams pushing the boundaries of collaborative coding

---

**Agent Coordinator** - Making AI agents work together, not against each other.
