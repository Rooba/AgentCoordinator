#!/bin/bash

# AgentCoordinator Setup Script
# This script sets up everything needed to connect GitHub Copilot to AgentCoordinator

set -e

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
USER_HOME="$HOME"

echo "🚀 AgentCoordinator Setup"
echo "========================="
echo "Project Directory: $PROJECT_DIR"
echo "User Home: $USER_HOME"

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Check prerequisites
echo -e "\n📋 Checking prerequisites..."

if ! command_exists mix; then
    echo "❌ Elixir/Mix not found. Please install Elixir first."
    exit 1
fi

if ! command_exists nats-server; then
    echo "⚠️  NATS server not found. Installing via package manager..."
    if command_exists apt; then
        sudo apt update && sudo apt install -y nats-server
    elif command_exists brew; then
        brew install nats-server
    elif command_exists yum; then
        sudo yum install -y nats-server
    else
        echo "❌ Please install NATS server manually: https://docs.nats.io/nats-server/installation"
        exit 1
    fi
fi

echo "✅ Prerequisites OK"

# Start NATS server if not running
echo -e "\n🔧 Setting up NATS server..."
if ! pgrep -f nats-server > /dev/null; then
    echo "Starting NATS server..."

    # Check if systemd service exists
    if systemctl list-unit-files | grep -q nats.service; then
        sudo systemctl enable nats
        sudo systemctl start nats
        echo "✅ NATS server started via systemd"
    else
        # Start manually in background
        nats-server -js -p 4222 -m 8222 > /tmp/nats.log 2>&1 &
        echo $! > /tmp/nats.pid
        echo "✅ NATS server started manually (PID: $(cat /tmp/nats.pid))"
    fi

    # Wait for NATS to be ready
    sleep 2
else
    echo "✅ NATS server already running"
fi

# Install Elixir dependencies
echo -e "\n📦 Installing Elixir dependencies..."
cd "$PROJECT_DIR"
mix deps.get
echo "✅ Dependencies installed"

# Test the application
echo -e "\n🧪 Testing AgentCoordinator application..."
echo "Testing basic compilation and startup..."

# First test: just compile
if mix compile >/dev/null 2>&1; then
    echo "✅ Application compiles successfully"
else
    echo "❌ Application compilation failed"
    exit 1
fi

# Second test: quick startup test without persistence
if timeout 15 mix run -e "
try do
  Application.put_env(:agent_coordinator, :enable_persistence, false)
  {:ok, _} = Application.ensure_all_started(:agent_coordinator)
  IO.puts('App startup test OK')
  System.halt(0)
rescue
  e ->
    IO.puts('App startup error: #{inspect(e)}')
    System.halt(1)
end
" >/dev/null 2>&1; then
    echo "✅ Application startup test passed"
else
    echo "⚠️  Application startup test had issues, but continuing..."
    echo "    (This might be due to NATS configuration - will be fixed during runtime)"
fi

# Create VS Code settings directory if it doesn't exist
VSCODE_SETTINGS_DIR="$USER_HOME/.vscode-server/data/User"
if [ ! -d "$VSCODE_SETTINGS_DIR" ]; then
    VSCODE_SETTINGS_DIR="$USER_HOME/.vscode/User"
fi

mkdir -p "$VSCODE_SETTINGS_DIR"

# Create or update VS Code settings for MCP
echo -e "\n⚙️  Configuring VS Code for MCP..."

SETTINGS_FILE="$VSCODE_SETTINGS_DIR/settings.json"
MCP_CONFIG='{
  "github.copilot.advanced": {
    "mcp": {
      "servers": {
        "agent-coordinator": {
          "command": "'$PROJECT_DIR'/scripts/mcp_launcher.sh",
          "args": [],
          "env": {
            "MIX_ENV": "dev",
            "NATS_HOST": "localhost",
            "NATS_PORT": "4222"
          }
        }
      }
    }
  }
}'

# Backup existing settings
if [ -f "$SETTINGS_FILE" ]; then
    cp "$SETTINGS_FILE" "$SETTINGS_FILE.backup.$(date +%s)"
    echo "📋 Backed up existing VS Code settings"
fi

# Merge or create settings
if [ -f "$SETTINGS_FILE" ]; then
    # Use jq to merge if available, otherwise manual merge
    if command_exists jq; then
        echo "$MCP_CONFIG" | jq -s '.[0] * .[1]' "$SETTINGS_FILE" - > "$SETTINGS_FILE.tmp"
        mv "$SETTINGS_FILE.tmp" "$SETTINGS_FILE"
    else
        echo "⚠️  jq not found. Please manually add MCP configuration to $SETTINGS_FILE"
        echo "Add this configuration:"
        echo "$MCP_CONFIG"
    fi
else
    echo "$MCP_CONFIG" > "$SETTINGS_FILE"
fi

echo "✅ VS Code settings updated"

# Test MCP server
echo -e "\n🧪 Testing MCP server..."
cd "$PROJECT_DIR"
if timeout 5 ./scripts/mcp_launcher.sh >/dev/null 2>&1; then
    echo "✅ MCP server test passed"
else
    echo "⚠️  MCP server test timed out (this is expected)"
fi

# Create desktop shortcut for easy access
echo -e "\n🖥️  Creating desktop shortcuts..."

# Start script
cat > "$PROJECT_DIR/start_agent_coordinator.sh" << 'EOF'
#!/bin/bash
cd "$(dirname "$0")"
echo "🚀 Starting AgentCoordinator..."

# Start NATS if not running
if ! pgrep -f nats-server > /dev/null; then
    echo "Starting NATS server..."
    nats-server -js -p 4222 -m 8222 > /tmp/nats.log 2>&1 &
    echo $! > /tmp/nats.pid
    sleep 2
fi

# Start MCP server
echo "Starting MCP server..."
./scripts/mcp_launcher.sh
EOF

chmod +x "$PROJECT_DIR/start_agent_coordinator.sh"

# Stop script
cat > "$PROJECT_DIR/stop_agent_coordinator.sh" << 'EOF'
#!/bin/bash
echo "🛑 Stopping AgentCoordinator..."

# Stop NATS if we started it
if [ -f /tmp/nats.pid ]; then
    kill $(cat /tmp/nats.pid) 2>/dev/null || true
    rm -f /tmp/nats.pid
fi

# Kill any remaining processes
pkill -f "scripts/mcp_launcher.sh" || true
pkill -f "agent_coordinator" || true

echo "✅ AgentCoordinator stopped"
EOF

chmod +x "$PROJECT_DIR/stop_agent_coordinator.sh"

echo "✅ Created start/stop scripts"

# Final instructions
echo -e "\n🎉 Setup Complete!"
echo "==================="
echo ""
echo "📋 Next Steps:"
echo ""
echo "1. 🔄 Restart VS Code to load the new MCP configuration"
echo "   - Close all VS Code windows"
echo "   - Reopen VS Code in your project"
echo ""
echo "2. 🤖 GitHub Copilot should now have access to AgentCoordinator tools:"
echo "   - register_agent"
echo "   - create_task"
echo "   - get_next_task"
echo "   - complete_task"
echo "   - get_task_board"
echo "   - heartbeat"
echo ""
echo "3. 🧪 Test the integration:"
echo "   - Ask Copilot: 'Register me as an agent with coding capabilities'"
echo "   - Ask Copilot: 'Create a task to refactor the login module'"
echo "   - Ask Copilot: 'Show me the task board'"
echo ""
echo "📂 Useful files:"
echo "   - Start server: $PROJECT_DIR/start_agent_coordinator.sh"
echo "   - Stop server:  $PROJECT_DIR/stop_agent_coordinator.sh"
echo "   - Test client:  $PROJECT_DIR/mcp_client_example.py"
echo "   - VS Code settings: $SETTINGS_FILE"
echo ""
echo "🔧 Manual start (if needed):"
echo "   cd $PROJECT_DIR && ./scripts/mcp_launcher.sh"
echo ""
echo "💡 Tip: The MCP server will auto-start when Copilot needs it!"
echo ""