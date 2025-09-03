# Agent Coordinator

A **Model Context Protocol (MCP) server** that enables multiple AI agents to coordinate their work seamlessly across codebases without conflicts. Built with Elixir for reliability and fault tolerance.

## 🎯 What is Agent Coordinator?

Agent Coordinator is an MCP server that solves the problem of multiple AI agents stepping on each other's toes when working on the same codebase. Instead of agents conflicting over files or duplicating work, they can register with the coordinator, receive tasks, and collaborate intelligently.

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
    │  │ Native Tools:      register_agent, get_next_task,           │ │
    │  │                    create_task_set, complete_task, ...      │ │
    │  │ Proxied MCP Tools: read_file, write_file,                   │ │
    │  │                    search_memory, get_docs, ...             │ │
    │  │ VS Code Tools:     get_active_editor, set_selection,        │ │
    │  │                    get_workspace_folders, run_command, ...  │ │
    │  ├─────────────────────────────────────────────────────────────┤ │
    │  │       Routes to appropriate server or handles natively      │ │
    │  │       Configure MCP Servers to run via MCP_TOOLS_FILE                     │ │
    │  └─────────────────────────────────────────────────────────────┘ │
    └─────────────────────────────────┬────────────────────────────────┘
                                      │
                                      │
                                      │
    ┌─────────────────────────────────┴─────────────────────────────────────┐
    │                         EXTERNAL MCP SERVERS                          │
    └──────────────┬─────────┬─────────┬─────────┬─────────┬─────────┬──────┤
         │         │         │         │         │         │         │      │
    ┌────┴───┐     │    ┌────┴───┐     │    ┌────┴───┐     │    ┌────┴───┐  │
    │  MCP 1 │     │    │  MCP 2 │     │    │  MCP 3 │     │    │  MCP 4 │  │
    ├────────┤     │    ├────────┤     │    ├────────┤     │    ├────────┤  │
    │• tool 1│     │    │• tool 1│     │    │• tool 1│     │    │• tool 1│  │
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

You need these installed to run Agent Coordinator:

- **Elixir**: 1.16+ with OTP 26+
- **Mix**: Comes with Elixir installation

## ⚡ Quick Start

### 1. Get the Code

```bash
git clone https://github.com/your-username/agent_coordinator.git
cd agent_coordinator
mix deps.get
```

### 2. Start the MCP Server

```bash
# Start the MCP server directly
./scripts/mcp_launcher.sh

# Or in development mode
mix run --no-halt
```

### 3. Configure Your AI Tools

The agent coordinator is designed to work with VS Code and AI tools that support MCP. Add this to your VS Code `settings.json`:

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
```

### 4. Test It Works

```bash
# Run the demo to see it in action
mix run examples/full_workflow_demo.exs
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
