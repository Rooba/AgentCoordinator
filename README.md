# Agent Coordinator

Agent Coordinator is a MCP proxy server that enables multiple AI agents to collaborate seamlessly without conflicts. It acts as a single MCP interface that proxies ALL tool calls through itself, ensuring every agent maintains full project awareness while the coordinator tracks real-time agent presence.

## What is Agent Coordinator?

**The coordinator operates as a transparent proxy layer:**

- **Single Interface**: All agents connect to one MCP server (the coordinator)
- **Proxy Architecture**: Every tool call flows through the coordinator to external MCP servers
- **Presence Tracking**: Each proxied tool call updates agent heartbeat and task status
- **Project Awareness**: All agents see the same unified view of project state through the proxy

**This proxy design orchestrates four core components:**

- **Task Registry**: Intelligent task queuing, agent matching, and automatic progress tracking
- **Agent Manager**: Agent registration, heartbeat monitoring, and capability-based assignment
- **Codebase Registry**: Cross-repository coordination, dependency management, and workspace organization
- **Unified Tool Registry**: Seamlessly proxies external MCP tools while adding coordination capabilities

## Overview
<!-- ![Agent Coordinator Architecture](docs/architecture-diagram.svg) Let's not show this it's confusing -->
### 🏗️ Architecture Components

**Core Coordinator Components:**

- Task Registry: Intelligent task queuing, agent matching, and progress tracking
- Agent Manager: Registration, heartbeat monitoring, and capability-based assignment
  Codebase Registry: Cross-repository coordination and workspace management
- Unified Tool Registry: Combines native coordination tools with external MCP tools
- Every tool call automatically updates the agent's activity for other agent's to see

**External Integration:**

- VS Code Integration: Direct editor commands and workspace management

### External Server Management

The coordinator automatically manages external MCP servers based on configuration in `mcp_servers.json`:

```json
{
  "servers": {
    "mcp_filesystem": {
      "type": "stdio",
      "command": "bunx",
      "args": ["-y", "@modelcontextprotocol/server-filesystem", "/workspace"],
      "auto_restart": true,
      "description": "Filesystem operations server"
    },
    "mcp_memory": {
      "type": "stdio",
      "command": "bunx",
      "args": ["-y", "@modelcontextprotocol/server-memory"],
      "auto_restart": true,
      "description": "Memory and knowledge graph server"
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

## Prerequisites

Choose one of these installation methods:

[Docker](#1-start-nats-server)

[Manual Installation](#manual-setup)

- **Elixir**: 1.16+ with OTP 26+
- **Node.js**: 18+ (for some MCP servers)
- **uv**: If using python MCP servers

### Docker Setup

#### 1. Start NATS Server

First, start a NATS server that the Agent Coordinator can connect to:

```bash
# Start NATS server with persistent storage
docker run -d \
  --name nats-server \
  --network agent-coordinator-net \
  -p 4222:4222 \
  -p 8222:8222 \
  -v nats_data:/data \
  nats:2.10-alpine \
  --jetstream \
  --store_dir=/data \
  --max_mem_store=1Gb \
  --max_file_store=10Gb

# Create the network first if it doesn't exist
docker network create agent-coordinator-net
```

#### 2. Configure Your AI Tools

**For STDIO Mode (Recommended - Direct MCP Integration):**

First, create a Docker network and start the NATS server:

```bash
# Create network for secure communication
docker network create agent-coordinator-net

# Start NATS server
docker run -d \
  --name nats-server \
  --network agent-coordinator-net \
  -p 4222:4222 \
  -v nats_data:/data \
  nats:2.10-alpine \
  --jetstream \
  --store_dir=/data \
  --max_mem_store=1Gb \
  --max_file_store=10Gb
```

Then add this configuration to your VS Code `mcp.json` configuration file via `ctrl + shift + p` → `MCP: Open User Configuration` or `MCP: Open Remote User Configuration` if running on a remote server:

```json
{
  "servers": {
    "agent-coordinator": {
      "command": "docker",
      "args": [
        "run",
        "--network=agent-coordinator-net",
        "-v=./mcp_servers.json:/app/mcp_servers.json:ro",
        "-v=/path/to/your/workspace:/workspace:rw",
        "-e=NATS_HOST=nats-server",
        "-e=NATS_PORT=4222",
        "-i",
        "--rm",
        "ghcr.io/rooba/agentcoordinator:latest"
      ],
      "type": "stdio"
    }
  }
}
```

**Important Notes for File System Access:**

If you're using MCP filesystem servers, mount the directories they need access to:

```json
{
  "args": [
    "run",
    "--network=agent-coordinator-net",
    "-v=./mcp_servers.json:/app/mcp_servers.json:ro",
    "-v=/home/user/projects:/home/user/projects:rw",
    "-v=/path/to/workspace:/workspace:rw",
    "-e=NATS_HOST=nats-server",
    "-e=NATS_PORT=4222",
    "-i",
    "--rm",
    "ghcr.io/rooba/agentcoordinator:latest"
  ]
}
```

**For HTTP/WebSocket Mode (Alternative - Web API Access):**

If you prefer to run as a web service instead of stdio:

```bash
# Create network first
docker network create agent-coordinator-net

# Start NATS server
docker run -d \
  --name nats-server \
  --network agent-coordinator-net \
  -p 4222:4222 \
  -v nats_data:/data \
  nats:2.10-alpine \
  --jetstream \
  --store_dir=/data \
  --max_mem_store=1Gb \
  --max_file_store=10Gb

# Run Agent Coordinator in HTTP mode
docker run -d \
  --name agent-coordinator \
  --network agent-coordinator-net \
  -p 8080:4000 \
  -v ./mcp_servers.json:/app/mcp_servers.json:ro \
  -v /path/to/workspace:/workspace:rw \
  -e NATS_HOST=nats-server \
  -e NATS_PORT=4222 \
  -e MCP_INTERFACE_MODE=http \
  -e MCP_HTTP_PORT=4000 \
  ghcr.io/rooba/agentcoordinator:latest
```

Then access via HTTP API at `http://localhost:8080/mcp` or configure your MCP client to use the HTTP endpoint.

Create or edit `mcp_servers.json` in your project directory to configure external MCP servers:

```json
{
  "servers": {
    "mcp_filesystem": {
      "type": "stdio",
      "command": "bunx",
      "args": ["-y", "@modelcontextprotocol/server-filesystem", "/workspace"],
      "auto_restart": true
    }
  }
}
```

### Manual Setup

#### Clone the Repository

> It is suggested to install Elixir (and Erlang) via [asdf](https://asdf-vm.com/) for easy version management.
> NATS can be found at [nats.io](https://github.com/nats-io/nats-server/releases/latest), or via Docker

```bash
git clone https://github.com/rooba/agentcoordinator.git
cd agentcoordinator
mix deps.get
mix compile
```

#### Start the MCP Server directly

```bash
# Start the MCP server directly
export MCP_INTERFACE_MODE=stdio # or http / websocket
# export MCP_HTTP_PORT=4000 # if using http mode

./scripts/mcp_launcher.sh

# Or in development mode
mix run --no-halt
```

### Run via VS Code or similar tools

Add this to your `mcp.json` or `mcp_servers.json` depending on your tool:

```json
{
  "servers": {
    "agent-coordinator": {
      "command": "/path/to/agent_coordinator/scripts/mcp_launcher.sh",
      "args": [],
      "env": {
        "MIX_ENV": "prod",
        "NATS_HOST": "localhost",
        "NATS_PORT": "4222"
      }
    }
  }
}
```
