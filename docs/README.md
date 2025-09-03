# Agent Coordinator Documentation

This directory contains detailed technical documentation for the Agent Coordinator project.

## 📚 Documentation Index

### Core Documentation
- [Main README](../README.md) - Project overview, setup, and basic usage
- [CHANGELOG](../CHANGELOG.md) - Version history and changes
- [CONTRIBUTING](../CONTRIBUTING.md) - How to contribute to the project

### Technical Deep Dives

#### Architecture & Design
- [AUTO_HEARTBEAT.md](AUTO_HEARTBEAT.md) - Unified MCP server with automatic task tracking and heartbeat system
- [VSCODE_TOOL_INTEGRATION.md](VSCODE_TOOL_INTEGRATION.md) - VS Code tool integration and dynamic tool discovery
- [DYNAMIC_TOOL_DISCOVERY.md](DYNAMIC_TOOL_DISCOVERY.md) - How the system dynamically discovers and manages MCP tools

#### Implementation Details
- [SEARCH_FILES_TIMEOUT_FIX.md](SEARCH_FILES_TIMEOUT_FIX.md) - Technical details on timeout handling and GenServer call optimization

## 🎯 Key Concepts

### Agent Coordination
The Agent Coordinator is an MCP server that enables multiple AI agents to work together without conflicts by:

- **Task Distribution**: Automatically assigns tasks based on agent capabilities
- **Heartbeat Management**: Tracks agent liveness and activity
- **Cross-Codebase Support**: Coordinates work across multiple repositories
- **Tool Unification**: Provides a single interface to multiple external MCP servers

### Unified MCP Server
The system acts as a unified MCP server that internally manages external MCP servers while providing:

- **Automatic Task Tracking**: Every tool usage becomes a tracked task
- **Universal Heartbeat Coverage**: All operations maintain agent liveness
- **Dynamic Tool Discovery**: Automatically discovers tools from external servers
- **Seamless Integration**: Single interface for all MCP-compatible tools

### VS Code Integration
Advanced integration with VS Code through:

- **Native Tool Provider**: Direct access to VS Code Extension API
- **Permission System**: Granular security controls for VS Code operations
- **Multi-Agent Support**: Safe concurrent access to VS Code features
- **Workflow Integration**: VS Code tools participate in task coordination

## 🚀 Getting Started with Documentation

1. **New Users**: Start with the [Main README](../README.md)
2. **Developers**: Read [CONTRIBUTING](../CONTRIBUTING.md) and [AUTO_HEARTBEAT.md](AUTO_HEARTBEAT.md)
3. **VS Code Users**: Check out [VSCODE_TOOL_INTEGRATION.md](VSCODE_TOOL_INTEGRATION.md)
4. **Troubleshooting**: See [SEARCH_FILES_TIMEOUT_FIX.md](SEARCH_FILES_TIMEOUT_FIX.md) for common issues

## 📖 Documentation Standards

All documentation in this project follows these standards:

- **Clear Structure**: Hierarchical headings with descriptive titles
- **Code Examples**: Practical examples with expected outputs
- **Troubleshooting**: Common issues and their solutions
- **Implementation Details**: Technical specifics for developers
- **User Perspective**: Both end-user and developer viewpoints

## 🤝 Contributing to Documentation

When adding new documentation:

1. Place technical deep-dives in this `docs/` directory
2. Update this index file to reference new documents
3. Keep the main README focused on getting started
4. Include practical examples and troubleshooting sections
5. Use clear, descriptive headings and consistent formatting

---

📝 **Last Updated**: August 25, 2025