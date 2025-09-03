# Search Files Timeout Fix

## Problem Description

The `search_files` tool (from the filesystem MCP server) was causing the agent-coordinator to exit with code 1 due to timeout issues. The error showed:

```
** (EXIT from #PID<0.95.0>) exited in: GenServer.call(AgentCoordinator.UnifiedMCPServer, {:handle_request, ...}, 5000)
** (EXIT) time out
```

## Root Cause Analysis

The issue was a timeout mismatch in the GenServer call chain:

1. **External tool calls** (like `search_files`) can take longer than 5 seconds to complete
2. **TaskRegistry and Inbox modules** were using default 5-second GenServer timeouts
3. During tool execution, **heartbeat operations** are called via `TaskRegistry.heartbeat_agent/1`
4. When the external tool took longer than 5 seconds, the heartbeat call would timeout
5. This caused the entire tool call to fail with exit code 1

## Call Chain Analysis

```
External MCP Tool Call (search_files)
  ↓
UnifiedMCPServer.handle_mcp_request (60s timeout) ✓
  ↓
MCPServerManager.route_tool_call (60s timeout) ✓
  ↓
call_external_tool
  ↓
TaskRegistry.heartbeat_agent (5s timeout) ❌ ← TIMEOUT HERE
```

## Solution Applied

Updated GenServer call timeouts in the following modules:

### TaskRegistry Module
- `register_agent/1`: 5s → 30s
- `heartbeat_agent/1`: 5s → 30s  ← **Most Critical Fix**
- `update_task_activity/3`: 5s → 30s
- `assign_task/1`: 5s → 30s
- `create_task/3`: 5s → 30s
- `complete_task/1`: 5s → 30s
- `get_agent_current_task/1`: 5s → 15s

### Inbox Module
- `add_task/2`: 5s → 30s
- `complete_current_task/1`: 5s → 30s
- `get_next_task/1`: 5s → 15s
- `get_status/1`: 5s → 15s
- `list_tasks/1`: 5s → 15s
- `get_current_task/1`: 5s → 15s

## Timeout Strategy

- **Long operations** (registration, task creation, heartbeat): **30 seconds**
- **Read operations** (status, get tasks, list): **15 seconds**
- **External tool routing**: **60 seconds** (already correct)

## Impact

This fix ensures that:

1. ✅ `search_files` and other long-running external tools won't cause timeouts
2. ✅ Agent heartbeat operations can complete successfully during tool execution
3. ✅ The agent-coordinator won't exit with code 1 due to timeout issues
4. ✅ All automatic task tracking continues to work properly

## Files Modified

- `/lib/agent_coordinator/task_registry.ex` - Updated GenServer call timeouts
- `/lib/agent_coordinator/inbox.ex` - Updated GenServer call timeouts

## Verification

The fix can be verified by:

1. Running the agent-coordinator with external MCP servers
2. Executing `search_files` or other filesystem tools on large directories
3. Confirming no timeout errors occur and exit code remains 0

## Future Considerations

- Consider making timeouts configurable via application config
- Monitor for any other GenServer calls that might need timeout adjustments
- Add timeout logging to help identify future timeout issues