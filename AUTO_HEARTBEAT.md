# Unified MCP Server with Auto-Heartbeat System Documentation

## Overview

The Agent Coordinator now operates as a **unified MCP server** that internally manages all external MCP servers (Context7, Figma, Filesystem, Firebase, Memory, Sequential Thinking, etc.) while providing automatic task tracking and heartbeat coverage for every tool operation. GitHub Copilot sees only a single MCP server, but gets access to all tools with automatic coordination.

## Key Features

### 1. Unified MCP Server Architecture
- **Single interface**: GitHub Copilot connects to only the Agent Coordinator
- **Internal server management**: Automatically starts and manages all external MCP servers
- **Unified tool registry**: Aggregates tools from all servers into one comprehensive list
- **Automatic task tracking**: Every tool call automatically creates/updates agent tasks

### 2. Automatic Task Tracking
- **Transparent operation**: Any tool usage automatically becomes a tracked task
- **No explicit coordination needed**: Agents don't need to call `create_task` manually
- **Real-time activity monitoring**: See what each agent is working on in real-time
- **Smart task titles**: Automatically generated based on tool usage and context

### 3. Enhanced Heartbeat Coverage
- **Universal coverage**: Every tool call from any server includes heartbeat management
- **Agent session tracking**: Automatic agent registration for GitHub Copilot
- **Activity-based heartbeats**: Heartbeats sent before/after each tool operation
- **Session metadata**: Enhanced task board shows real activity and tool usage

## Architecture

```
GitHub Copilot
      ↓
Agent Coordinator (Single Visible MCP Server)
      ↓
┌─────────────────────────────────────────────────────────┐
│  Unified MCP Server                                     │
│  • Aggregates all tools into single interface          │
│  • Automatic task tracking for every operation         │
│  • Agent coordination tools (create_task, etc.)        │
│  • Universal heartbeat coverage                        │
└─────────────────────────────────────────────────────────┘
      ↓
┌─────────────────────────────────────────────────────────┐
│  MCP Server Manager                                     │
│  • Starts & manages external servers internally        │
│  • Health monitoring & auto-restart                    │
│  • Tool aggregation & routing                          │
│  • Auto-task creation for any tool usage               │
└─────────────────────────────────────────────────────────┘
      ↓
┌──────────┬──────────┬───────────┬──────────┬─────────────┐
│ Context7 │  Figma   │Filesystem │ Firebase │ Memory +    │
│ Server   │ Server   │ Server    │ Server   │ Sequential  │
└──────────┴──────────┴───────────┴──────────┴─────────────┘
```

## Usage

### GitHub Copilot Experience

From GitHub Copilot's perspective, there's only one MCP server with all tools available:

```javascript
// All these tools are available from the single Agent Coordinator server:

// Agent coordination tools
register_agent, create_task, get_next_task, complete_task, get_task_board, heartbeat

// Context7 tools
mcp_context7_get-library-docs, mcp_context7_resolve-library-id

// Figma tools
mcp_figma_get_code, mcp_figma_get_image, mcp_figma_get_variable_defs

// Filesystem tools
mcp_filesystem_read_file, mcp_filesystem_write_file, mcp_filesystem_list_directory

// Firebase tools
mcp_firebase_firestore_get_documents, mcp_firebase_auth_get_user

// Memory tools
mcp_memory_search_nodes, mcp_memory_create_entities

// Sequential thinking tools
mcp_sequentialthi_sequentialthinking

// Plus any other configured MCP servers...
```

### Automatic Task Tracking

Every tool usage automatically creates or updates an agent's current task:

```elixir
# When GitHub Copilot calls any tool, it automatically:
# 1. Sends pre-operation heartbeat
# 2. Creates/updates current task based on tool usage
# 3. Routes to appropriate external server
# 4. Sends post-operation heartbeat
# 5. Updates task activity log

# Example: Reading a file automatically creates a task
Tool Call: mcp_filesystem_read_file(%{"path" => "/project/src/main.rs"})
Auto-Created Task: "Reading file: main.rs"
Description: "Reading and analyzing file content from /project/src/main.rs"

# Example: Figma code generation automatically creates a task
Tool Call: mcp_figma_get_code(%{"nodeId" => "123:456"})
Auto-Created Task: "Generating Figma code: 123:456"
Description: "Generating code for Figma component 123:456"

# Example: Library research automatically creates a task
Tool Call: mcp_context7_get-library-docs(%{"context7CompatibleLibraryID" => "/vercel/next.js"})
Auto-Created Task: "Researching: /vercel/next.js"
Description: "Researching documentation for /vercel/next.js library"
```

### Task Board with Real Activity

```elixir
# Get enhanced task board showing real agent activity
{:ok, board} = get_task_board()

# Returns:
%{
  agents: [
    %{
      agent_id: "github_copilot_session",
      name: "GitHub Copilot",
      status: :working,
      current_task: %{
        title: "Reading file: database.ex",
        description: "Reading and analyzing file content from /project/lib/database.ex",
        auto_generated: true,
        tool_name: "mcp_filesystem_read_file",
        created_at: ~U[2025-08-23 10:30:00Z]
      },
      last_heartbeat: ~U[2025-08-23 10:30:05Z],
      online: true
    }
  ],
  pending_tasks: [],
  total_agents: 1,
  active_tasks: 1,
  pending_count: 0
}
```

## Configuration

### MCP Server Configuration

External servers are configured in `mcp_servers.json`:

```json
{
  "servers": {
    "mcp_context7": {
      "type": "stdio",
      "command": "uvx",
      "args": ["mcp-server-context7"],
      "auto_restart": true,
      "description": "Context7 library documentation server"
    },
    "mcp_figma": {
      "type": "stdio",
      "command": "npx",
      "args": ["-y", "@figma/mcp-server-figma"],
      "auto_restart": true,
      "description": "Figma design integration server"
    },
    "mcp_filesystem": {
      "type": "stdio",
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-filesystem", "/home/ra"],
      "auto_restart": true,
      "description": "Filesystem operations with auto-task tracking"
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

### VS Code Settings

Update your VS Code MCP settings to point to the unified server:

```json
{
  "mcp.servers": {
    "agent-coordinator": {
      "command": "/home/ra/agent_coordinator/scripts/mcp_launcher.sh",
      "args": []
    }
  }
}
```

## Benefits

### 1. Simplified Configuration
- **One server**: GitHub Copilot only needs to connect to Agent Coordinator
- **No manual setup**: External servers are managed automatically
- **Unified tools**: All tools appear in one comprehensive list

### 2. Automatic Coordination
- **Zero-effort tracking**: Every tool usage automatically tracked as tasks
- **Real-time visibility**: See exactly what agents are working on
- **Smart task creation**: Descriptive task titles based on actual tool usage
- **Universal heartbeats**: Every operation maintains agent liveness

### 3. Enhanced Collaboration
- **Agent communication**: Coordination tools still available for planning
- **Multi-agent workflows**: Agents can create tasks for each other
- **Activity awareness**: Agents can see what others are working on
- **File conflict prevention**: Automatic file locking across operations

### 4. Operational Excellence
- **Auto-restart**: Failed external servers automatically restarted
- **Health monitoring**: Real-time status of all managed servers
- **Error handling**: Graceful degradation when servers unavailable
- **Performance**: Direct routing without external proxy overhead

## Migration Guide

### From Individual MCP Servers

**Before:**
```json
// VS Code settings with multiple servers
{
  "mcp.servers": {
    "context7": {"command": "uvx", "args": ["mcp-server-context7"]},
    "figma": {"command": "npx", "args": ["-y", "@figma/mcp-server-figma"]},
    "filesystem": {"command": "npx", "args": ["-y", "@modelcontextprotocol/server-filesystem", "/path"]},
    "agent-coordinator": {"command": "/path/to/mcp_launcher.sh"}
  }
}
```

**After:**
```json
// VS Code settings with single unified server
{
  "mcp.servers": {
    "agent-coordinator": {
      "command": "/home/ra/agent_coordinator/scripts/mcp_launcher.sh",
      "args": []
    }
  }
}
```

### Configuration Migration

1. **Remove individual MCP servers** from VS Code settings
2. **Add external servers** to `mcp_servers.json` configuration
3. **Update launcher script** path if needed
4. **Restart VS Code** to apply changes

## Startup and Testing

### Starting the Unified Server

```bash
# From the project directory
./scripts/mcp_launcher.sh
```

### Testing Tool Aggregation

```bash
# Test that all tools are available
echo '{"jsonrpc":"2.0","id":1,"method":"tools/list"}' | ./scripts/mcp_launcher.sh

# Should return tools from Agent Coordinator + all external servers
```

### Testing Automatic Task Tracking

```bash
# Use any tool - it should automatically create a task
echo '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"mcp_filesystem_read_file","arguments":{"path":"/home/ra/test.txt"}}}' | ./scripts/mcp_launcher.sh

# Check task board to see auto-created task
echo '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"get_task_board","arguments":{}}}' | ./scripts/mcp_launcher.sh
```

## Troubleshooting

### External Server Issues

1. **Server won't start**
   - Check command path in `mcp_servers.json`
   - Verify dependencies are installed (`npm install -g @modelcontextprotocol/server-*`)
   - Check logs for startup errors

2. **Tools not appearing**
   - Verify server started successfully
   - Check server health: use `get_server_status` tool
   - Restart specific servers if needed

3. **Auto-restart not working**
   - Check `auto_restart: true` in server config
   - Verify process monitoring is active
   - Check restart attempt limits

### Task Tracking Issues

1. **Tasks not auto-creating**
   - Verify agent session is active
   - Check that GitHub Copilot is registered as agent
   - Ensure heartbeat system is working

2. **Incorrect task titles**
   - Task titles are generated based on tool name and arguments
   - Can be customized in `generate_task_title/2` function
   - File-based operations use file paths in titles

## Future Enhancements

Planned improvements:

1. **Dynamic server discovery** - Auto-detect and add new MCP servers
2. **Load balancing** - Distribute tool calls across multiple server instances
3. **Tool versioning** - Support multiple versions of the same tool
4. **Custom task templates** - Configurable task generation based on tool patterns
5. **Inter-agent messaging** - Direct communication channels between agents
6. **Workflow orchestration** - Multi-step task coordination across agents