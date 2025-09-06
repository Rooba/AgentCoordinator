#!/usr/bin/env elixir

# Quick test script for the enhanced MCP session management
# This tests the new session token authentication flow

Mix.install([
  {:jason, "~> 1.4"},
  {:httpoison, "~> 2.0"}
])

defmodule SessionManagementTest do
  @base_url "http://localhost:4000"

  def run_test do
    IO.puts("🔧 Testing Enhanced MCP Session Management")
    IO.puts("=" <> String.duplicate("=", 50))

    # Step 1: Register an agent to get a session token
    IO.puts("\n1️⃣  Registering agent to get session token...")

    register_payload = %{
      "jsonrpc" => "2.0",
      "id" => "test_001",
      "method" => "agents/register",
      "params" => %{
        "name" => "Test Agent Blue Koala",
        "capabilities" => ["coding", "testing"],
        "codebase_id" => "test_codebase",
        "workspace_path" => "/tmp/test"
      }
    }

    case post_mcp_request("/mcp/request", register_payload) do
      {:ok, %{"result" => result}} ->
        session_token = Map.get(result, "session_token")
        expires_at = Map.get(result, "expires_at")

        IO.puts("✅ Agent registered successfully!")
        IO.puts("   Session Token: #{String.slice(session_token || "nil", 0, 20)}...")
        IO.puts("   Expires At: #{expires_at}")

        if session_token do
          test_authenticated_request(session_token)
        else
          IO.puts("❌ No session token returned!")
        end

      {:ok, %{"error" => error}} ->
        IO.puts("❌ Registration failed: #{inspect(error)}")

      {:error, reason} ->
        IO.puts("❌ Request failed: #{reason}")
    end

    # Step 2: Test MCP protocol headers
    IO.puts("\n2️⃣  Testing MCP protocol headers...")
    test_protocol_headers()

    IO.puts("\n🎉 Session management test completed!")
  end

  defp test_authenticated_request(session_token) do
    IO.puts("\n🔐 Testing authenticated request with session token...")

    # Try to call a tool that requires authentication
    tool_payload = %{
      "jsonrpc" => "2.0",
      "id" => "test_002",
      "method" => "tools/call",
      "params" => %{
        "name" => "get_task_board",
        "arguments" => %{"agent_id" => "Test Agent Blue Koala"}
      }
    }

    headers = [
      {"Content-Type", "application/json"},
      {"Mcp-Session-Id", session_token}
    ]

    case HTTPoison.post("#{@base_url}/mcp/request", Jason.encode!(tool_payload), headers) do
      {:ok, %HTTPoison.Response{status_code: 200, headers: response_headers, body: body}} ->
        IO.puts("✅ Authenticated request successful!")

        # Check for MCP protocol headers
        mcp_version = get_header_value(response_headers, "mcp-protocol-version")
        IO.puts("   MCP Protocol Version: #{mcp_version || "Not found"}")

        # Parse response
        case Jason.decode(body) do
          {:ok, %{"result" => _result}} ->
            IO.puts("   ✅ Valid MCP response received")
          {:ok, %{"error" => error}} ->
            IO.puts("   ⚠️  MCP error: #{inspect(error)}")
          _ ->
            IO.puts("   ❌ Invalid response format")
        end

      {:ok, %HTTPoison.Response{status_code: status_code, body: body}} ->
        IO.puts("❌ Request failed with status #{status_code}")
        case Jason.decode(body) do
          {:ok, parsed} -> IO.puts("   Error: #{inspect(parsed)}")
          _ -> IO.puts("   Body: #{body}")
        end

      {:error, reason} ->
        IO.puts("❌ HTTP request failed: #{inspect(reason)}")
    end
  end

  defp test_protocol_headers do
    case HTTPoison.get("#{@base_url}/health") do
      {:ok, %HTTPoison.Response{headers: headers}} ->
        mcp_version = get_header_value(headers, "mcp-protocol-version")
        server_header = get_header_value(headers, "server")

        IO.puts("✅ Protocol headers check:")
        IO.puts("   MCP-Protocol-Version: #{mcp_version || "❌ Missing"}")
        IO.puts("   Server: #{server_header || "❌ Missing"}")

      {:error, reason} ->
        IO.puts("❌ Failed to test headers: #{inspect(reason)}")
    end
  end

  defp post_mcp_request(endpoint, payload) do
    headers = [{"Content-Type", "application/json"}]

    case HTTPoison.post("#{@base_url}#{endpoint}", Jason.encode!(payload), headers) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        Jason.decode(body)

      {:ok, %HTTPoison.Response{status_code: status_code, body: body}} ->
        {:error, "HTTP #{status_code}: #{body}"}

      {:error, reason} ->
        {:error, inspect(reason)}
    end
  end

  defp get_header_value(headers, header_name) do
    headers
    |> Enum.find(fn {name, _value} ->
      String.downcase(name) == String.downcase(header_name)
    end)
    |> case do
      {_name, value} -> value
      nil -> nil
    end
  end
end

# Run the test
SessionManagementTest.run_test()
