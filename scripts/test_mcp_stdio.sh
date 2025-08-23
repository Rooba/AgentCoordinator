#!/bin/bash

# Test script for MCP server stdio interface

echo "🧪 Testing AgentCoordinator MCP Server via stdio"
echo "================================================"

# Start the MCP server in background
./mcp_launcher.sh &
MCP_PID=$!

# Give it time to start
sleep 3

# Function to send MCP request and get response
send_mcp_request() {
    local request="$1"
    echo "📤 Sending: $request"
    echo "$request" | nc localhost 12345 2>/dev/null || echo "$request" >&${MCP_PID}
    sleep 1
}

# Test 1: Get tools list
echo -e "\n1️⃣ Testing tools/list..."
TOOLS_REQUEST='{"jsonrpc":"2.0","id":1,"method":"tools/list"}'
send_mcp_request "$TOOLS_REQUEST"

# Test 2: Register agent
echo -e "\n2️⃣ Testing register_agent..."
REGISTER_REQUEST='{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"register_agent","arguments":{"name":"TestAgent","capabilities":["coding","testing"]}}}'
send_mcp_request "$REGISTER_REQUEST"

# Test 3: Create task
echo -e "\n3️⃣ Testing create_task..."
TASK_REQUEST='{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"create_task","arguments":{"title":"Test Task","description":"A test task","priority":"medium","required_capabilities":["coding"]}}}'
send_mcp_request "$TASK_REQUEST"

# Test 4: Get task board
echo -e "\n4️⃣ Testing get_task_board..."
BOARD_REQUEST='{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"get_task_board","arguments":{}}}'
send_mcp_request "$BOARD_REQUEST"

# Clean up
sleep 2
kill $MCP_PID 2>/dev/null
echo -e "\n✅ MCP server test completed"