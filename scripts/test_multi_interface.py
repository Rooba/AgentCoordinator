#!/usr/bin/env python3
"""
Test script for Agent Coordinator Multi-Interface MCP Server.

This script tests:
1. HTTP interface with tool filtering
2. WebSocket interface with real-time communication
3. Tool filtering based on client context
4. Agent registration and coordination
"""

import json
import requests
import websocket
import asyncio
import time
from concurrent.futures import ThreadPoolExecutor

BASE_URL = "http://localhost:8080"
WS_URL = "ws://localhost:8080/mcp/ws"

def test_http_interface():
    """Test HTTP interface and tool filtering."""
    print("\n=== Testing HTTP Interface ===")
    
    # Test health endpoint
    try:
        response = requests.get(f"{BASE_URL}/health")
        print(f"Health check: {response.status_code}")
        if response.status_code == 200:
            print(f"Health data: {response.json()}")
    except Exception as e:
        print(f"Health check failed: {e}")
        return False
    
    # Test capabilities endpoint
    try:
        response = requests.get(f"{BASE_URL}/mcp/capabilities")
        print(f"Capabilities: {response.status_code}")
        if response.status_code == 200:
            caps = response.json()
            print(f"Tools available: {len(caps.get('tools', []))}")
            print(f"Connection type: {caps.get('context', {}).get('connection_type')}")
            print(f"Security level: {caps.get('context', {}).get('security_level')}")
            
            # Check that local-only tools are filtered out
            tool_names = [tool.get('name') for tool in caps.get('tools', [])]
            local_tools = ['read_file', 'vscode_create_file', 'run_in_terminal']
            filtered_out = [tool for tool in local_tools if tool not in tool_names]
            print(f"Local tools filtered out: {filtered_out}")
    except Exception as e:
        print(f"Capabilities test failed: {e}")
        return False
    
    # Test tool list endpoint
    try:
        response = requests.get(f"{BASE_URL}/mcp/tools")
        print(f"Tools list: {response.status_code}")
        if response.status_code == 200:
            tools = response.json()
            print(f"Filter stats: {tools.get('_meta', {}).get('filter_stats')}")
    except Exception as e:
        print(f"Tools list test failed: {e}")
        return False
    
    # Test agent registration
    try:
        register_data = {
            "arguments": {
                "name": "Test Agent HTTP",
                "capabilities": ["testing", "analysis"]
            }
        }
        response = requests.post(f"{BASE_URL}/mcp/tools/register_agent", 
                               json=register_data,
                               headers={"Content-Type": "application/json"})
        print(f"Agent registration: {response.status_code}")
        if response.status_code == 200:
            result = response.json()
            print(f"Registration result: {result.get('result')}")
            return result.get('result', {}).get('agent_id')
    except Exception as e:
        print(f"Agent registration failed: {e}")
        return False
    
    return True

def test_websocket_interface():
    """Test WebSocket interface with real-time communication."""
    print("\n=== Testing WebSocket Interface ===")
    
    messages_received = []
    
    def on_message(ws, message):
        print(f"Received: {message}")
        messages_received.append(json.loads(message))
    
    def on_error(ws, error):
        print(f"WebSocket error: {error}")
    
    def on_close(ws, close_status_code, close_msg):
        print("WebSocket connection closed")
    
    def on_open(ws):
        print("WebSocket connection opened")
        
        # Send initialize message
        init_msg = {
            "jsonrpc": "2.0",
            "id": 1,
            "method": "initialize",
            "params": {
                "protocolVersion": "2024-11-05",
                "clientInfo": {
                    "name": "test-websocket-client",
                    "version": "1.0.0"
                },
                "capabilities": ["coordination"]
            }
        }
        ws.send(json.dumps(init_msg))
        
        # Wait a bit then request tools list
        time.sleep(0.5)
        tools_msg = {
            "jsonrpc": "2.0", 
            "id": 2,
            "method": "tools/list"
        }
        ws.send(json.dumps(tools_msg))
        
        # Register an agent
        time.sleep(0.5)
        register_msg = {
            "jsonrpc": "2.0",
            "id": 3,
            "method": "tools/call",
            "params": {
                "name": "register_agent",
                "arguments": {
                    "name": "Test Agent WebSocket",
                    "capabilities": ["testing", "websocket"]
                }
            }
        }
        ws.send(json.dumps(register_msg))
        
        # Close after a delay
        time.sleep(2)
        ws.close()
    
    try:
        ws = websocket.WebSocketApp(WS_URL,
                                  on_open=on_open,
                                  on_message=on_message,
                                  on_error=on_error,
                                  on_close=on_close)
        ws.run_forever()
        
        print(f"Messages received: {len(messages_received)}")
        for i, msg in enumerate(messages_received):
            print(f"Message {i+1}: {msg.get('result', {}).get('_meta', 'No meta')}")
        
        return len(messages_received) > 0
    except Exception as e:
        print(f"WebSocket test failed: {e}")
        return False

def test_tool_filtering():
    """Test tool filtering functionality specifically."""
    print("\n=== Testing Tool Filtering ===")
    
    try:
        # Get tools from HTTP (remote context)
        response = requests.get(f"{BASE_URL}/mcp/tools")
        if response.status_code != 200:
            print("Failed to get tools from HTTP")
            return False
        
        remote_tools = response.json()
        tool_names = [tool.get('name') for tool in remote_tools.get('tools', [])]
        
        # Check that coordination tools are present
        coordination_tools = ['register_agent', 'create_task', 'get_task_board', 'heartbeat']
        present_coordination = [tool for tool in coordination_tools if tool in tool_names]
        print(f"Coordination tools present: {present_coordination}")
        
        # Check that local-only tools are filtered out
        local_only_tools = ['read_file', 'write_file', 'vscode_create_file', 'run_in_terminal']
        filtered_local = [tool for tool in local_only_tools if tool not in tool_names]
        print(f"Local-only tools filtered: {filtered_local}")
        
        # Check that safe remote tools are present
        safe_remote_tools = ['create_entities', 'sequentialthinking', 'get-library-docs']
        present_safe = [tool for tool in safe_remote_tools if tool in tool_names]
        print(f"Safe remote tools present: {present_safe}")
        
        # Verify filter statistics
        filter_stats = remote_tools.get('_meta', {}).get('filter_stats', {})
        print(f"Filter stats: {filter_stats}")
        
        success = (
            len(present_coordination) >= 3 and  # Most coordination tools present
            len(filtered_local) >= 2 and        # Local tools filtered
            filter_stats.get('connection_type') == 'remote'
        )
        
        return success
    except Exception as e:
        print(f"Tool filtering test failed: {e}")
        return False

def test_forbidden_tool_access():
    """Test that local-only tools are properly blocked for remote clients."""
    print("\n=== Testing Forbidden Tool Access ===")
    
    try:
        # Try to call a local-only tool
        forbidden_data = {
            "arguments": {
                "path": "/etc/passwd",
                "agent_id": "test_agent"
            }
        }
        response = requests.post(f"{BASE_URL}/mcp/tools/read_file",
                               json=forbidden_data,
                               headers={"Content-Type": "application/json"})
        
        print(f"Forbidden tool call status: {response.status_code}")
        if response.status_code == 403:
            error_data = response.json()
            print(f"Expected 403 error: {error_data.get('error', {}).get('message')}")
            return True
        else:
            print(f"Unexpected response: {response.json()}")
            return False
    except Exception as e:
        print(f"Forbidden tool test failed: {e}")
        return False

def main():
    """Run all tests."""
    print("Agent Coordinator Multi-Interface Test Suite")
    print("=" * 50)
    
    # Test results
    results = {}
    
    # HTTP Interface Test
    results['http'] = test_http_interface()
    
    # WebSocket Interface Test  
    results['websocket'] = test_websocket_interface()
    
    # Tool Filtering Test
    results['tool_filtering'] = test_tool_filtering()
    
    # Forbidden Access Test
    results['forbidden'] = test_forbidden_tool_access()
    
    # Summary
    print("\n" + "=" * 50)
    print("TEST RESULTS SUMMARY")
    print("=" * 50)
    
    for test_name, success in results.items():
        status = "✅ PASS" if success else "❌ FAIL"
        print(f"{test_name.ljust(20)}: {status}")
    
    total_tests = len(results)
    passed_tests = sum(results.values())
    print(f"\nOverall: {passed_tests}/{total_tests} tests passed")
    
    if passed_tests == total_tests:
        print("🎉 All tests passed! Multi-interface MCP server is working correctly.")
        return 0
    else:
        print("⚠️  Some tests failed. Check the implementation.")
        return 1

if __name__ == "__main__":
    exit(main())