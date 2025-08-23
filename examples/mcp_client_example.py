#!/usr/bin/env python3
"""
AgentCoordinator MCP Client Example

This script demonstrates how to connect to and interact with the
AgentCoordinator MCP server programmatically.
"""

import json
import subprocess
import sys
import uuid
from typing import Dict, Any, Optional

class AgentCoordinatorMCP:
    def __init__(self, launcher_path: str = "./scripts/mcp_launcher.sh"):
        self.launcher_path = launcher_path
        self.process = None

    def start(self):
        """Start the MCP server process"""
        try:
            self.process = subprocess.Popen(
                [self.launcher_path],
                stdin=subprocess.PIPE,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                bufsize=0
            )
            print("🚀 MCP server started")
            return True
        except Exception as e:
            print(f"❌ Failed to start MCP server: {e}")
            return False

    def stop(self):
        """Stop the MCP server process"""
        if self.process:
            self.process.terminate()
            self.process.wait()
            print("🛑 MCP server stopped")

    def send_request(self, method: str, params: Optional[Dict[str, Any]] = None) -> Dict[str, Any]:
        """Send a JSON-RPC request to the MCP server"""
        if not self.process:
            raise RuntimeError("MCP server not started")

        request = {
            "jsonrpc": "2.0",
            "id": str(uuid.uuid4()),
            "method": method
        }

        if params:
            request["params"] = params

        # Send request
        request_json = json.dumps(request) + "\n"
        self.process.stdin.write(request_json)
        self.process.stdin.flush()

        # Read response
        response_line = self.process.stdout.readline()
        if not response_line:
            raise RuntimeError("No response from MCP server")

        return json.loads(response_line.strip())

    def get_tools(self) -> Dict[str, Any]:
        """Get list of available tools"""
        return self.send_request("tools/list")

    def register_agent(self, name: str, capabilities: list) -> Dict[str, Any]:
        """Register a new agent"""
        return self.send_request("tools/call", {
            "name": "register_agent",
            "arguments": {
                "name": name,
                "capabilities": capabilities
            }
        })

    def create_task(self, title: str, description: str, priority: str = "normal",
                   required_capabilities: list = None) -> Dict[str, Any]:
        """Create a new task"""
        args = {
            "title": title,
            "description": description,
            "priority": priority
        }
        if required_capabilities:
            args["required_capabilities"] = required_capabilities

        return self.send_request("tools/call", {
            "name": "create_task",
            "arguments": args
        })

    def get_next_task(self, agent_id: str) -> Dict[str, Any]:
        """Get next task for an agent"""
        return self.send_request("tools/call", {
            "name": "get_next_task",
            "arguments": {"agent_id": agent_id}
        })

    def complete_task(self, agent_id: str, result: str) -> Dict[str, Any]:
        """Complete current task"""
        return self.send_request("tools/call", {
            "name": "complete_task",
            "arguments": {
                "agent_id": agent_id,
                "result": result
            }
        })

    def get_task_board(self) -> Dict[str, Any]:
        """Get task board overview"""
        return self.send_request("tools/call", {
            "name": "get_task_board",
            "arguments": {}
        })

    def heartbeat(self, agent_id: str) -> Dict[str, Any]:
        """Send agent heartbeat"""
        return self.send_request("tools/call", {
            "name": "heartbeat",
            "arguments": {"agent_id": agent_id}
        })

def demo():
    """Demonstrate MCP client functionality"""
    print("🎯 AgentCoordinator MCP Client Demo")
    print("=" * 50)

    client = AgentCoordinatorMCP()

    try:
        # Start server
        if not client.start():
            return

        # Wait for server to be ready
        import time
        time.sleep(2)

        # Get tools
        print("\n📋 Available tools:")
        tools_response = client.get_tools()
        if "result" in tools_response:
            for tool in tools_response["result"]["tools"]:
                print(f"  - {tool['name']}: {tool['description']}")

        # Register agent
        print("\n👤 Registering agent...")
        register_response = client.register_agent("PythonAgent", ["coding", "testing"])
        if "result" in register_response:
            content = register_response["result"]["content"][0]["text"]
            agent_data = json.loads(content)
            agent_id = agent_data["agent_id"]
            print(f"✅ Agent registered: {agent_id}")

            # Create task
            print("\n📝 Creating task...")
            task_response = client.create_task(
                "Python Script",
                "Write a Python script for data processing",
                "high",
                ["coding"]
            )
            if "result" in task_response:
                content = task_response["result"]["content"][0]["text"]
                task_data = json.loads(content)
                print(f"✅ Task created: {task_data['task_id']}")

            # Get task board
            print("\n📊 Task board:")
            board_response = client.get_task_board()
            if "result" in board_response:
                content = board_response["result"]["content"][0]["text"]
                board_data = json.loads(content)
                for agent in board_data["agents"]:
                    print(f"  📱 {agent['name']}: {agent['status']}")
                    print(f"     Capabilities: {', '.join(agent['capabilities'])}")
                    print(f"     Pending: {agent['pending_tasks']}, Completed: {agent['completed_tasks']}")

    except Exception as e:
        print(f"❌ Error: {e}")
    finally:
        client.stop()

if __name__ == "__main__":
    demo()