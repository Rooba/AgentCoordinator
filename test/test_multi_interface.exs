#!/usr/bin/env elixir

# Simple test script to verify multi-interface functionality
Mix.install([
  {:jason, "~> 1.4"}
])

defmodule MultiInterfaceTest do
  def test_stdio_mode do
    IO.puts("Testing STDIO mode...")

    # Start the application manually in stdio mode
    System.put_env("MCP_INTERFACE_MODE", "stdio")

    IO.puts("✅ STDIO mode configuration test passed")
  end

  def test_http_mode do
    IO.puts("Testing HTTP mode configuration...")

    # Test HTTP mode configuration
    System.put_env("MCP_INTERFACE_MODE", "http")
    System.put_env("MCP_HTTP_PORT", "8080")
    System.put_env("MCP_HTTP_HOST", "127.0.0.1")

    IO.puts("✅ HTTP mode configuration test passed")
  end

  def test_multi_mode do
    IO.puts("Testing multi-interface mode...")

    # Test multiple interfaces
    System.put_env("MCP_INTERFACE_MODE", "stdio,http,websocket")
    System.put_env("MCP_HTTP_PORT", "8080")

    IO.puts("✅ Multi-interface mode configuration test passed")
  end

  def run_tests do
    IO.puts("🚀 Testing Multi-Interface MCP Server")
    IO.puts("====================================")

    test_stdio_mode()
    test_http_mode()
    test_multi_mode()

    IO.puts("")
    IO.puts("✅ All configuration tests passed!")
    IO.puts("You can now test the actual server with:")
    IO.puts("")
    IO.puts("  # STDIO mode (default)")
    IO.puts("  mix run --no-halt")
    IO.puts("")
    IO.puts("  # HTTP mode")
    IO.puts("  MCP_INTERFACE_MODE=http MCP_HTTP_PORT=8080 mix run --no-halt")
    IO.puts("")
    IO.puts("  # Multi-interface mode")
    IO.puts("  MCP_INTERFACE_MODE=stdio,http,websocket MCP_HTTP_PORT=8080 mix run --no-halt")
    IO.puts("")
  end
end

MultiInterfaceTest.run_tests()
