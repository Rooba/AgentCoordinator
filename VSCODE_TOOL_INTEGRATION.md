# VS Code Tool Integration with Agent Coordinator

## Overview

This document outlines the implementation of VS Code's built-in tools as MCP (Model Context Protocol) tools within the Agent Coordinator system. This integration allows agents to access VS Code's native capabilities alongside external MCP servers through a unified coordination interface.

## Architecture

### Current State
- Agent Coordinator acts as a unified MCP server
- Proxies tools from external MCP servers (Context7, filesystem, memory, sequential thinking, etc.)
- Manages task coordination, agent assignment, and cross-codebase workflows

### Proposed Enhancement
- Add VS Code Extension API tools as native MCP tools
- Integrate with existing tool routing and coordination system
- Maintain security and permission controls

## Implementation Plan

### Phase 1: Core VS Code Tool Provider

#### 1.1 Create VSCodeToolProvider Module
**File**: `lib/agent_coordinator/vscode_tool_provider.ex`

**Core Tools to Implement**:
- `vscode_read_file` - Read file contents using VS Code API
- `vscode_write_file` - Write file contents 
- `vscode_create_file` - Create new files
- `vscode_delete_file` - Delete files
- `vscode_list_directory` - List directory contents
- `vscode_get_workspace_folders` - Get workspace information
- `vscode_run_command` - Execute VS Code commands
- `vscode_get_active_editor` - Get current editor state
- `vscode_set_editor_content` - Modify editor content
- `vscode_get_selection` - Get current text selection
- `vscode_set_selection` - Set text selection
- `vscode_show_message` - Display messages to user

#### 1.2 Tool Definitions
Each tool will have:
- MCP-compliant schema definition
- Input validation
- Error handling
- Audit logging
- Permission checking

### Phase 2: Advanced Editor Operations

#### 2.1 Language Services Integration
- `vscode_get_diagnostics` - Get language server diagnostics
- `vscode_format_document` - Format current document
- `vscode_format_selection` - Format selected text
- `vscode_find_references` - Find symbol references
- `vscode_go_to_definition` - Navigate to definition
- `vscode_rename_symbol` - Rename symbols
- `vscode_code_actions` - Get available code actions

#### 2.2 Search and Navigation
- `vscode_find_in_files` - Search across workspace
- `vscode_find_symbols` - Find symbols in workspace
- `vscode_goto_line` - Navigate to specific line
- `vscode_reveal_in_explorer` - Show file in explorer

### Phase 3: Terminal and Process Management

#### 3.1 Terminal Operations
- `vscode_create_terminal` - Create new terminal
- `vscode_send_to_terminal` - Send commands to terminal
- `vscode_get_terminal_output` - Get terminal output (if possible)
- `vscode_close_terminal` - Close terminal instances

#### 3.2 Task and Process Management
- `vscode_run_task` - Execute VS Code tasks
- `vscode_get_tasks` - List available tasks
- `vscode_debug_start` - Start debugging session
- `vscode_debug_stop` - Stop debugging

### Phase 4: Git and Version Control

#### 4.1 Git Operations
- `vscode_git_status` - Get git status
- `vscode_git_commit` - Create commits
- `vscode_git_push` - Push changes
- `vscode_git_pull` - Pull changes
- `vscode_git_branch` - Branch operations
- `vscode_git_diff` - Get file differences

### Phase 5: Extension and Settings Management

#### 5.1 Configuration
- `vscode_get_settings` - Get VS Code settings
- `vscode_update_settings` - Update settings
- `vscode_get_extensions` - List installed extensions
- `vscode_install_extension` - Install extensions (if permitted)

## Security and Safety

### Permission Model
```elixir
defmodule AgentCoordinator.VSCodePermissions do
  @moduledoc """
  Manages permissions for VS Code tool access.
  """
  
  # Permission levels:
  # :read_only - File reading, workspace inspection
  # :editor - Text editing, selections
  # :filesystem - File creation/deletion
  # :terminal - Terminal access
  # :git - Version control operations
  # :admin - Settings, extensions, system commands
end
```

### Sandboxing
- Restrict file operations to workspace folders only
- Prevent access to system files outside workspace
- Rate limiting for expensive operations
- Command whitelist for `vscode_run_command`

### Audit Logging
- Log all VS Code tool calls with:
  - Timestamp
  - Agent ID
  - Tool name and parameters
  - Result summary
  - Permission level used

## Integration Points

### 1. UnifiedMCPServer Enhancement
**File**: `lib/agent_coordinator/unified_mcp_server.ex`

Add VS Code tools to the tool discovery and routing:

```elixir
defp get_all_tools(state) do
  # Existing external MCP server tools
  external_tools = get_external_tools(state)
  
  # New VS Code tools
  vscode_tools = VSCodeToolProvider.get_tools()
  
  external_tools ++ vscode_tools
end

defp route_tool_call(tool_name, args, context, state) do
  case tool_name do
    "vscode_" <> _rest ->
      VSCodeToolProvider.handle_tool_call(tool_name, args, context)
    _ ->
      # Route to external MCP servers
      route_to_external_server(tool_name, args, context, state)
  end
end
```

### 2. Task Coordination
VS Code tools will participate in the same task coordination system:
- Task creation and assignment
- File locking (prevent conflicts)
- Cross-agent coordination
- Priority management

### 3. Agent Capabilities
Agents can declare VS Code tool capabilities:
```elixir
capabilities: [
  "coding", 
  "analysis", 
  "vscode_editing",
  "vscode_terminal", 
  "vscode_git"
]
```

## Usage Examples

### Example 1: File Analysis and Editing
```json
{
  "tool": "vscode_read_file",
  "args": {"path": "src/main.rs"}
}
// Agent reads file, analyzes it

{
  "tool": "vscode_get_diagnostics", 
  "args": {"file": "src/main.rs"}
}
// Agent gets compiler errors

{
  "tool": "vscode_set_editor_content",
  "args": {
    "file": "src/main.rs",
    "content": "// Fixed code here",
    "range": {"start": 10, "end": 15}
  }
}
// Agent fixes the issues
```

### Example 2: Cross-Tool Workflow
```json
// 1. Agent searches documentation using Context7
{"tool": "mcp_context7_get-library-docs", "args": {"libraryID": "/rust/std"}}

// 2. Agent analyzes current code using VS Code
{"tool": "vscode_get_active_editor", "args": {}}

// 3. Agent applies documentation insights to code
{"tool": "vscode_format_document", "args": {}}
{"tool": "vscode_set_editor_content", "args": {...}}

// 4. Agent commits changes using VS Code Git
{"tool": "vscode_git_commit", "args": {"message": "Applied best practices from docs"}}
```

## Benefits

1. **Unified Tool Access**: Agents access both external services and VS Code features through same interface
2. **Enhanced Capabilities**: Complex workflows combining external data with direct IDE manipulation
3. **Consistent Coordination**: Same task management for all tool types
4. **Security**: Controlled access to powerful VS Code features
5. **Extensibility**: Easy to add new VS Code capabilities as needs arise

## Implementation Timeline

- **Week 1**: Phase 1 - Core file and editor operations
- **Week 2**: Phase 2 - Language services and navigation  
- **Week 3**: Phase 3 - Terminal and task management
- **Week 4**: Phase 4 - Git integration
- **Week 5**: Phase 5 - Settings and extension management
- **Week 6**: Testing, documentation, security review

## Testing Strategy

1. **Unit Tests**: Each VS Code tool function
2. **Integration Tests**: Tool coordination and routing
3. **Security Tests**: Permission enforcement and sandboxing
4. **Performance Tests**: Rate limiting and resource usage
5. **User Acceptance**: Real workflow testing with multiple agents

## Future Enhancements

- **Extension-specific Tools**: Tools for specific VS Code extensions
- **Collaborative Features**: Multi-agent editing coordination
- **AI-Enhanced Operations**: Intelligent code suggestions and fixes
- **Remote Development**: Support for remote VS Code scenarios
- **Custom Tool Creation**: Framework for users to create their own VS Code tools

---

## Notes

This implementation transforms the Agent Coordinator from a simple MCP proxy into a comprehensive development environment orchestrator, enabling sophisticated AI-assisted development workflows.