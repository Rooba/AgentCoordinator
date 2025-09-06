# Agent Coordinator Multi-Interface MCP Server

The Agent Coordinator now supports multiple interface modes to accommodate different client types and use cases, from local VSCode integration to remote web applications.

## Interface Modes

### 1. STDIO Mode (Default)
Traditional MCP over stdin/stdout for local clients like VSCode.

**Features:**
- Full tool access (filesystem, VSCode, terminal tools)
- Local security context (trusted)
- Backward compatible with existing MCP clients

**Usage:**
```bash
./scripts/mcp_launcher_multi.sh stdio
# or
./scripts/mcp_launcher.sh  # original launcher
```

### 2. HTTP Mode
REST API interface for remote clients and web applications.

**Features:**
- HTTP endpoints for MCP operations
- Tool filtering (removes local-only tools)
- CORS support for web clients
- Remote security context (sandboxed)

**Usage:**
```bash
./scripts/mcp_launcher_multi.sh http 8080
```

**Endpoints:**
- `GET /health` - Health check
- `GET /mcp/capabilities` - Server capabilities and filtered tools
- `GET /mcp/tools` - List available tools (filtered by context)
- `POST /mcp/tools/:tool_name` - Execute specific tool
- `POST /mcp/request` - Full MCP JSON-RPC request
- `GET /agents` - Agent status (requires authorization)

### 3. WebSocket Mode
Real-time interface for web clients requiring live updates.

**Features:**
- Real-time MCP JSON-RPC over WebSocket
- Tool filtering for remote clients
- Session management and heartbeat
- Automatic cleanup on disconnect

**Usage:**
```bash
./scripts/mcp_launcher_multi.sh websocket 8081
```

**Endpoint:**
- `ws://localhost:8081/mcp/ws` - WebSocket connection

### 4. Remote Mode
Both HTTP and WebSocket on the same port for complete remote access.

**Usage:**
```bash
./scripts/mcp_launcher_multi.sh remote 8080
```

### 5. All Mode
All interface modes simultaneously for maximum compatibility.

**Usage:**
```bash
./scripts/mcp_launcher_multi.sh all 8080
```

## Tool Filtering

The system intelligently filters available tools based on client context:

### Local Clients (STDIO)
- **Context**: Trusted, local machine
- **Tools**: All tools available
- **Use case**: VSCode extension, local development

### Remote Clients (HTTP/WebSocket)
- **Context**: Sandboxed, remote access
- **Tools**: Filtered to exclude local-only operations
- **Use case**: Web applications, CI/CD, remote dashboards

### Tool Categories

**Always Available (All Contexts):**
- Agent coordination: `register_agent`, `create_task`, `get_task_board`, `heartbeat`
- Memory/Knowledge: `create_entities`, `read_graph`, `search_nodes`
- Documentation: `get-library-docs`, `resolve-library-id`
- Reasoning: `sequentialthinking`

**Local Only (Filtered for Remote):**
- Filesystem: `read_file`, `write_file`, `create_file`, `delete_file`
- VSCode: `vscode_*` tools
- Terminal: `run_in_terminal`, `get_terminal_output`
- System: Local file operations

## Configuration

Configuration is managed through environment variables and config files:

### Environment Variables
- `MCP_INTERFACE_MODE`: Interface mode (`stdio`, `http`, `websocket`, `remote`, `all`)
- `MCP_HTTP_PORT`: HTTP server port (default: 8080)
- `MCP_WS_PORT`: WebSocket port (default: 8081)

### Configuration File
See `mcp_interfaces_config.json` for detailed configuration options.

## Security Considerations

### Local Context (STDIO)
- Full filesystem access
- Trusted environment
- No network exposure

### Remote Context (HTTP/WebSocket)
- Sandboxed environment
- Tool filtering active
- CORS protection
- No local file access

### Tool Filtering Rules
1. **Allowlist approach**: Safe tools are explicitly allowed for remote clients
2. **Pattern matching**: Local-only tools identified by name patterns
3. **Schema analysis**: Tools with local-only parameters are filtered
4. **Context-aware**: Different tool sets per connection type

## Client Examples

### HTTP Client (Python)
```python
import requests

# Get available tools
response = requests.get("http://localhost:8080/mcp/tools")
tools = response.json()

# Register an agent
agent_data = {
    "arguments": {
        "name": "Remote Agent",
        "capabilities": ["analysis", "coordination"]
    }
}
response = requests.post("http://localhost:8080/mcp/tools/register_agent", 
                        json=agent_data)
```

### WebSocket Client (JavaScript)
```javascript
const ws = new WebSocket('ws://localhost:8080/mcp/ws');

ws.onopen = () => {
    // Initialize connection
    ws.send(JSON.stringify({
        jsonrpc: "2.0",
        id: 1,
        method: "initialize",
        params: {
            protocolVersion: "2024-11-05",
            clientInfo: { name: "web-client", version: "1.0.0" }
        }
    }));
};

ws.onmessage = (event) => {
    const response = JSON.parse(event.data);
    console.log('MCP Response:', response);
};
```

### VSCode MCP (Traditional)
```json
{
    "mcpServers": {
        "agent-coordinator": {
            "command": "./scripts/mcp_launcher_multi.sh",
            "args": ["stdio"]
        }
    }
}
```

## Testing

Run the test suite to verify all interface modes:

```bash
# Start the server in remote mode
./scripts/mcp_launcher_multi.sh remote 8080 &

# Run tests
python3 scripts/test_multi_interface.py

# Stop the server
kill %1
```

## Use Cases

### VSCode Extension Development
```bash
./scripts/mcp_launcher_multi.sh stdio
```
Full local tool access for development workflows.

### Web Dashboard
```bash
./scripts/mcp_launcher_multi.sh remote 8080
```
Remote access with HTTP API and WebSocket for real-time updates.

### CI/CD Integration
```bash
./scripts/mcp_launcher_multi.sh http 8080
```
REST API access for automated workflows.

### Development/Testing
```bash
./scripts/mcp_launcher_multi.sh all 8080
```
All interfaces available for comprehensive testing.

## Architecture

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   STDIO Client  │    │   HTTP Client   │    │ WebSocket Client│
│    (VSCode)     │    │  (Web/API)     │    │   (Web/Real-time)│
└─────────┬───────┘    └─────────┬───────┘    └─────────┬───────┘
          │                      │                      │
          │ Full Tools           │ Filtered Tools       │ Filtered Tools
          │                      │                      │
          v                      v                      v
┌─────────────────────────────────────────────────────────────────────┐
│                    Interface Manager                                │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐                │
│  │   STDIO     │  │    HTTP     │  │  WebSocket  │                │
│  │ Interface   │  │ Interface   │  │ Interface   │                │
│  └─────────────┘  └─────────────┘  └─────────────┘                │
└─────────────────────┬───────────────────────────────────────────────┘
                      │
                      v
┌─────────────────────────────────────────────────────────────────────┐
│                     Tool Filter                                    │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐     │
│  │ Local Context   │  │ Remote Context  │  │  Web Context    │     │
│  │ (Full Access)   │  │  (Sandboxed)   │  │  (Restricted)   │     │
│  └─────────────────┘  └─────────────────┘  └─────────────────┘     │
└─────────────────────┬───────────────────────────────────────────────┘
                      │
                      v
┌─────────────────────────────────────────────────────────────────────┐
│                     MCP Server                                     │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐     │
│  │ Agent Registry  │  │ Task Manager    │  │ External MCPs   │     │
│  └─────────────────┘  └─────────────────┘  └─────────────────┘     │
└─────────────────────────────────────────────────────────────────────┘
```

## Benefits

1. **Flexible Deployment**: Choose the right interface for your use case
2. **Security**: Automatic tool filtering prevents unauthorized local access
3. **Scalability**: HTTP/WebSocket interfaces support multiple concurrent clients
4. **Backward Compatibility**: STDIO mode maintains compatibility with existing tools
5. **Real-time Capability**: WebSocket enables live updates and notifications
6. **Developer Experience**: Consistent MCP protocol across all interfaces

The multi-interface system allows the Agent Coordinator to serve both local development workflows and remote/web applications while maintaining security and appropriate tool access levels.