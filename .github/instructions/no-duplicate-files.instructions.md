---
applyTo: '**'
---

# No Duplicate Files Policy

## Critical Rule: NO DUPLICATE FILES

**NEVER** create files with adjectives or verbs that duplicate existing functionality:
- ❌ `enhanced_mcp_server.ex` when `mcp_server.ex` exists
- ❌ `unified_mcp_server.ex` when `mcp_server.ex` exists
- ❌ `mcp_server_manager.ex` when `mcp_server.ex` exists
- ❌ `new_config.ex` when `config.ex` exists
- ❌ `improved_task_registry.ex` when `task_registry.ex` exists

## What To Do Instead

1. **BEFORE** making changes that might create a new file:
   ```bash
   git add . && git commit -m "Save current state before refactoring"
   ```

2. **MODIFY** the existing file directly instead of creating a "new" version

3. **IF** you need to completely rewrite a file:
   - Make the changes directly to the original file
   - Don't create `*_new.*` or `enhanced_*.*` versions

## Why This Rule Exists

When you create duplicate files:
- Future sessions can't tell which file is "real"
- The codebase becomes inconsistent and confusing
- Multiple implementations cause bugs and maintenance nightmares
- Even YOU get confused about which file to edit next time

## The Human Is Right

The human specifically said: "I fucking hate it when you do this retarded shit and recreate the same file with some adjective/verb but leave the original"

**Listen to them.** They prefer file replacement over duplicates.

## Implementation

- Always check if a file with similar functionality exists before creating a new one
- Use `git add . && git commit` before potentially destructive changes
- Replace, don't duplicate
- Keep the codebase clean and consistent

**This rule is more important than any specific feature request.**