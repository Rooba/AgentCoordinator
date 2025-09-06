---
applyTo: '**'
---
- You must always use the agent-coordinator mcp server, this will allow you to coordinate your work with other agents that may be actively working on the same codebase as you.
- All MCP tool calls which would alter anythings state should be done through the agent-coordinator, even vscode internal tool calls. Searches are fine to not be done through the agent coordinator. The core reason for running them through the agent-coordinator is for the heartbeat.
- Always make sure you append at least 2 random words onto the end of your agent name when registering / sending metadata, eg: `GitHub Copilot Silver Banana`, `GitHub Copilot Yellow Koala`, `GitHub Copilot Olive Llama`, this will assure that not agents have overlapping names and get tracked as the same agent (hopefully)
- Always check the task board when given new user input which will require making any changes to files.
- Always populate your own task board with your task set so other agents may be informed of your planned tasks, and in turn you will be able to see other agents' agendas.
- Once you are coming to an end of your current query, and you will be passing the turn to wait for user input, you must unregister yourself as an agent, and upon the followup you should re-register and follow through with the same registration flow.
