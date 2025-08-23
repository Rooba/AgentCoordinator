# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Initial repository structure cleanup
- Organized scripts into dedicated directories
- Enhanced documentation
- GitHub Actions CI/CD workflow
- Development and testing dependencies

### Changed

- Moved demo files to `examples/` directory
- Moved utility scripts to `scripts/` directory
- Updated project metadata in mix.exs
- Enhanced .gitignore for better coverage

## [0.1.0] - 2025-08-22

### Features

- Initial release of AgentCoordinator
- Distributed task coordination system for AI agents
- NATS-based messaging and persistence
- MCP (Model Context Protocol) server integration
- Task registry with agent-specific inboxes
- File-level conflict resolution
- Real-time agent communication
- Event sourcing with configurable retention
- Fault-tolerant supervision trees
- Command-line interface for task management
- VS Code integration setup scripts
- Comprehensive examples and documentation

### Core Features

- Agent registration and capability management
- Task creation, assignment, and completion
- Task board visualization
- Heartbeat monitoring for agent health
- Persistent task state with NATS JetStream
- MCP tools for external agent integration

### Development Tools

- Setup scripts for NATS and VS Code configuration
- Example MCP client implementations
- Test scripts for various scenarios
- Demo workflows for testing functionality
