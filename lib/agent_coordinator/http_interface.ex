defmodule AgentCoordinator.HttpInterface do
  @moduledoc """
  HTTP and WebSocket interface for the Agent Coordinator MCP server.

  This module provides:
  - HTTP REST API for MCP requests
  - WebSocket support for real-time communication
  - Remote client detection and tool filtering
  - CORS support for web clients
  - Session management across HTTP requests
  """

  use Plug.Router
  require Logger
  alias AgentCoordinator.{MCPServer, ToolFilter, SessionManager}

  plug Plug.Logger
  plug :match
  plug Plug.Parsers, parsers: [:json], json_decoder: Jason
  plug :put_cors_headers
  plug :dispatch

  @doc """
  Start the HTTP server on the specified port.
  """
  def start_link(opts \\ []) do
    port = Keyword.get(opts, :port, 8080)

    Logger.info("Starting Agent Coordinator HTTP interface on port #{port}")

    Plug.Cowboy.http(__MODULE__, [],
      port: port,
      dispatch: cowboy_dispatch()
    )
  end

  # HTTP Routes

  get "/health" do
    send_json_response(conn, 200, %{
      status: "healthy",
      service: "agent-coordinator",
      version: AgentCoordinator.version(),
      timestamp: DateTime.utc_now()
    })
  end

  get "/mcp/capabilities" do
    context = extract_client_context(conn)

    # Get filtered tools based on client context
    all_tools = MCPServer.get_tools()
    filtered_tools = ToolFilter.filter_tools(all_tools, context)

    capabilities = %{
      protocolVersion: "2024-11-05",
      serverInfo: %{
        name: "agent-coordinator-http",
        version: AgentCoordinator.version(),
        description: "Agent Coordinator HTTP/WebSocket interface"
      },
      capabilities: %{
        tools: %{},
        coordination: %{
          automatic_task_tracking: true,
          agent_management: true,
          multi_server_proxy: true,
          heartbeat_coverage: true,
          session_tracking: true,
          tool_filtering: true
        }
      },
      tools: filtered_tools,
      context: %{
        connection_type: context.connection_type,
        security_level: context.security_level,
        tool_count: length(filtered_tools)
      }
    }

    send_json_response(conn, 200, capabilities)
  end

  get "/mcp/tools" do
    context = extract_client_context(conn)
    all_tools = MCPServer.get_tools()
    filtered_tools = ToolFilter.filter_tools(all_tools, context)

    filter_stats = ToolFilter.get_filter_stats(all_tools, context)

    response = %{
      tools: filtered_tools,
      _meta: %{
        filter_stats: filter_stats,
        context: %{
          connection_type: context.connection_type,
          security_level: context.security_level
        }
      }
    }

    send_json_response(conn, 200, response)
  end

  post "/mcp/tools/:tool_name" do
    context = extract_client_context(conn)

    # Check if tool is allowed for this client
    all_tools = MCPServer.get_tools()
    filtered_tools = ToolFilter.filter_tools(all_tools, context)

    tool_allowed = Enum.any?(filtered_tools, fn tool ->
      Map.get(tool, "name") == tool_name
    end)

    if not tool_allowed do
      send_json_response(conn, 403, %{
        error: %{
          code: -32601,
          message: "Tool not available for remote clients: #{tool_name}",
          data: %{
            available_tools: Enum.map(filtered_tools, &Map.get(&1, "name")),
            connection_type: context.connection_type
          }
        }
      })
    else
      # Execute the tool call
      args = Map.get(conn.body_params, "arguments", %{})

      # Create MCP request format
      mcp_request = %{
        "jsonrpc" => "2.0",
        "id" => Map.get(conn.body_params, "id", generate_request_id()),
        "method" => "tools/call",
        "params" => %{
          "name" => tool_name,
          "arguments" => args
        }
      }

      # Add session tracking
      mcp_request = add_session_info(mcp_request, conn, context)

      # Execute through MCP server
      case MCPServer.handle_mcp_request(mcp_request) do
        %{"result" => result} ->
          send_json_response(conn, 200, %{
            result: result,
            _meta: %{
              tool_name: tool_name,
              request_id: mcp_request["id"],
              context: context.connection_type
            }
          })

        %{"error" => error} ->
          send_json_response(conn, 400, %{error: error})

        unexpected ->
          Logger.error("Unexpected MCP response: #{inspect(unexpected)}")
          send_json_response(conn, 500, %{
            error: %{
              code: -32603,
              message: "Internal server error"
            }
          })
      end
    end
  end

  post "/mcp/request" do
    context = extract_client_context(conn)

    # Validate MCP request format
    case validate_mcp_request(conn.body_params) do
      {:ok, mcp_request} ->
        method = Map.get(mcp_request, "method")

        # Validate session for this method
        case validate_session_for_method(method, conn, context) do
          {:ok, _session_info} ->
            # Add session tracking
            enhanced_request = add_session_info(mcp_request, conn, context)

            # For tool calls, check tool filtering
            case method do
              "tools/call" ->
                tool_name = get_in(enhanced_request, ["params", "name"])
                if tool_allowed_for_context?(tool_name, context) do
                  execute_mcp_request(conn, enhanced_request, context)
                else
                  send_json_response(conn, 403, %{
                    jsonrpc: "2.0",
                    id: Map.get(enhanced_request, "id"),
                    error: %{
                      code: -32601,
                      message: "Tool not available: #{tool_name}"
                    }
                  })
                end

              "tools/list" ->
                # Override tools/list to return filtered tools
                handle_filtered_tools_list(conn, enhanced_request, context)

              _ ->
                # Other methods pass through normally
                execute_mcp_request(conn, enhanced_request, context)
            end

          {:error, auth_error} ->
            send_json_response(conn, 401, %{
              jsonrpc: "2.0",
              id: Map.get(mcp_request, "id"),
              error: auth_error
            })
        end

      {:error, reason} ->
        send_json_response(conn, 400, %{
          jsonrpc: "2.0",
          id: Map.get(conn.body_params, "id"),
          error: %{
            code: -32700,
            message: "Invalid request: #{reason}"
          }
        })
    end
  end

  get "/mcp/ws" do
    conn
    |> WebSockAdapter.upgrade(AgentCoordinator.WebSocketHandler, %{}, timeout: 60_000)
  end

  get "/agents" do
    context = extract_client_context(conn)

    # Only allow agent status for authorized clients
    case context.security_level do
      level when level in [:trusted, :sandboxed] ->
        mcp_request = %{
          "jsonrpc" => "2.0",
          "id" => generate_request_id(),
          "method" => "tools/call",
          "params" => %{
            "name" => "get_task_board",
            "arguments" => %{"agent_id" => "http_interface"}
          }
        }

        case MCPServer.handle_mcp_request(mcp_request) do
          %{"result" => %{"content" => [%{"text" => text}]}} ->
            data = Jason.decode!(text)
            send_json_response(conn, 200, data)

          %{"error" => error} ->
            send_json_response(conn, 500, %{error: error})
        end

      _ ->
        send_json_response(conn, 403, %{
          error: "Insufficient privileges to view agent status"
        })
    end
  end

  # Server-Sent Events (SSE) endpoint for real-time MCP streaming.
  # Implements MCP Streamable HTTP transport for live updates.
  get "/mcp/stream" do
    context = extract_client_context(conn)

    # Validate session for SSE stream
    case validate_session_for_method("stream/subscribe", conn, context) do
      {:ok, session_info} ->
        # Set up SSE headers
        conn = conn
        |> put_resp_content_type("text/event-stream")
        |> put_mcp_headers()
        |> put_resp_header("cache-control", "no-cache")
        |> put_resp_header("connection", "keep-alive")
        |> put_resp_header("access-control-allow-credentials", "true")
        |> send_chunked(200)

        # Send initial connection event
        {:ok, conn} = chunk(conn, format_sse_event("connected", %{
          session_id: Map.get(session_info, :agent_id, "anonymous"),
          protocol_version: "2025-06-18",
          timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
        }))

        # Start streaming loop
        stream_mcp_events(conn, session_info, context)

      {:error, auth_error} ->
        send_json_response(conn, 401, auth_error)
    end
  end

  defp stream_mcp_events(conn, session_info, context) do
    # This is a basic implementation - in production you'd want to:
    # 1. Subscribe to a GenServer/PubSub for real-time events
    # 2. Handle client disconnections gracefully
    # 3. Implement proper backpressure

    # Send periodic heartbeat for now
    try do
      :timer.sleep(1000)
      {:ok, conn} = chunk(conn, format_sse_event("heartbeat", %{
        timestamp: DateTime.utc_now() |> DateTime.to_iso8601(),
        session_id: Map.get(session_info, :agent_id, "anonymous")
      }))

      # Continue streaming (this would be event-driven in production)
      stream_mcp_events(conn, session_info, context)
    rescue
      # Client disconnected
      _ ->
        Logger.info("SSE client disconnected")
        conn
    end
  end

  defp format_sse_event(event_type, data) do
    "event: #{event_type}\ndata: #{Jason.encode!(data)}\n\n"
  end

  # Catch-all for unmatched routes
  match _ do
    send_json_response(conn, 404, %{
      error: "Not found",
      available_endpoints: [
        "GET /health",
        "GET /mcp/capabilities",
        "GET /mcp/tools",
        "POST /mcp/tools/:tool_name",
        "POST /mcp/request",
        "GET /mcp/stream (SSE)",
        "GET /mcp/ws",
        "GET /agents"
      ]
    })
  end

  # Private helper functions

  defp cowboy_dispatch do
    [
      {:_, [
        {"/mcp/ws", AgentCoordinator.WebSocketHandler, []},
        {:_, Plug.Cowboy.Handler, {__MODULE__, []}}
      ]}
    ]
  end

  defp extract_client_context(conn) do
    remote_ip = get_remote_ip(conn)
    user_agent = get_req_header(conn, "user-agent") |> List.first()
    origin = get_req_header(conn, "origin") |> List.first()

    connection_info = %{
      transport: :http,
      remote_ip: remote_ip,
      user_agent: user_agent,
      origin: origin,
      secure: conn.scheme == :https,
      headers: conn.req_headers
    }

    ToolFilter.detect_client_context(connection_info)
  end

  defp get_remote_ip(conn) do
    # Check for forwarded headers first (for reverse proxies)
    forwarded_for = get_req_header(conn, "x-forwarded-for") |> List.first()
    real_ip = get_req_header(conn, "x-real-ip") |> List.first()

    cond do
      forwarded_for ->
        forwarded_for |> String.split(",") |> List.first() |> String.trim()
      real_ip ->
        real_ip
      true ->
        conn.remote_ip |> :inet.ntoa() |> to_string()
    end
  end

  defp put_cors_headers(conn, _opts) do
    # Validate origin for enhanced security
    origin = get_req_header(conn, "origin") |> List.first()
    allowed_origin = validate_origin(origin)

    conn
    |> put_resp_header("access-control-allow-origin", allowed_origin)
    |> put_resp_header("access-control-allow-methods", "GET, POST, OPTIONS")
    |> put_resp_header("access-control-allow-headers", "content-type, authorization, mcp-session-id, mcp-protocol-version, x-session-id")
    |> put_resp_header("access-control-expose-headers", "mcp-protocol-version, server")
    |> put_resp_header("access-control-max-age", "86400")
  end

  defp validate_origin(nil), do: "*"  # No origin header (direct API calls)
  defp validate_origin(origin) do
    # Allow localhost and development origins
    case URI.parse(origin) do
      %URI{host: host} when host in ["localhost", "127.0.0.1", "::1"] -> origin
      %URI{host: host} when is_binary(host) ->
        # Allow HTTPS origins and known development domains
        if String.starts_with?(origin, "https://") or
           String.contains?(host, ["localhost", "127.0.0.1", "dev", "local"]) do
          origin
        else
          # For production, be more restrictive
          Logger.warning("Potentially unsafe origin: #{origin}")
          "*"  # Fallback for now, could be more restrictive
        end
      _ -> "*"
    end
  end

  defp send_json_response(conn, status, data) do
    conn
    |> put_resp_content_type("application/json")
    |> put_mcp_headers()
    |> send_resp(status, Jason.encode!(data))
  end

  defp put_mcp_headers(conn) do
    conn
    |> put_resp_header("mcp-protocol-version", "2025-06-18")
    |> put_resp_header("server", "AgentCoordinator/1.0")
  end

  defp validate_mcp_request(params) when is_map(params) do
    required_fields = ["jsonrpc", "method"]

    missing_fields = Enum.filter(required_fields, fn field ->
      not Map.has_key?(params, field)
    end)

    cond do
      not Enum.empty?(missing_fields) ->
        {:error, "Missing required fields: #{Enum.join(missing_fields, ", ")}"}

      Map.get(params, "jsonrpc") != "2.0" ->
        {:error, "Invalid jsonrpc version, must be '2.0'"}

      not is_binary(Map.get(params, "method")) ->
        {:error, "Method must be a string"}

      true ->
        {:ok, params}
    end
  end

  defp validate_mcp_request(_), do: {:error, "Request must be a JSON object"}

  defp add_session_info(mcp_request, conn, context) do
    # Extract and validate MCP session token
    {session_id, session_info} = get_session_info(conn)

    # Add context metadata to request params
    enhanced_params = Map.get(mcp_request, "params", %{})
    |> Map.put("_session_id", session_id)
    |> Map.put("_session_info", session_info)
    |> Map.put("_client_context", %{
      connection_type: context.connection_type,
      security_level: context.security_level,
      remote_ip: get_remote_ip(conn),
      user_agent: context.user_agent
    })

    Map.put(mcp_request, "params", enhanced_params)
  end

  defp get_session_info(conn) do
    # Check for MCP-Session-Id header (MCP compliant)
    case get_req_header(conn, "mcp-session-id") do
      [session_token] when byte_size(session_token) > 0 ->
        case SessionManager.validate_session(session_token) do
          {:ok, session_info} ->
            {session_info.agent_id, %{
              token: session_token,
              agent_id: session_info.agent_id,
              capabilities: session_info.capabilities,
              expires_at: session_info.expires_at,
              validated: true
            }}
          {:error, reason} ->
            Logger.warning("Invalid MCP session token: #{reason}")
            # Fall back to generating anonymous session
            anonymous_id = "http_anonymous_" <> (:crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower))
            {anonymous_id, %{validated: false, reason: reason}}
        end

      [] ->
        # Check legacy X-Session-Id header for backward compatibility
        case get_req_header(conn, "x-session-id") do
          [session_id] when byte_size(session_id) > 0 ->
            {session_id, %{validated: false, legacy: true}}
          _ ->
            # No session header, generate anonymous session
            anonymous_id = "http_anonymous_" <> (:crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower))
            {anonymous_id, %{validated: false, anonymous: true}}
        end
    end
  end

  defp require_authenticated_session(conn, _context) do
    {_session_id, session_info} = get_session_info(conn)

    case Map.get(session_info, :validated, false) do
      true ->
        {:ok, session_info}
      false ->
        reason = Map.get(session_info, :reason, "Session not authenticated")
        {:error, %{
          code: -32001,
          message: "Authentication required",
          data: %{reason: reason}
        }}
    end
  end

  defp validate_session_for_method(method, conn, context) do
    # Define which methods require authenticated sessions
    authenticated_methods = MapSet.new([
      "agents/register",
      "agents/unregister",
      "agents/heartbeat",
      "tasks/create",
      "tasks/complete",
      "codebase/register",
      "stream/subscribe"
    ])

    if MapSet.member?(authenticated_methods, method) do
      require_authenticated_session(conn, context)
    else
      {:ok, %{anonymous: true}}
    end
  end

  defp tool_allowed_for_context?(tool_name, context) do
    all_tools = MCPServer.get_tools()
    filtered_tools = ToolFilter.filter_tools(all_tools, context)

    Enum.any?(filtered_tools, fn tool ->
      Map.get(tool, "name") == tool_name
    end)
  end

  defp execute_mcp_request(conn, mcp_request, _context) do
    case MCPServer.handle_mcp_request(mcp_request) do
      %{"result" => _} = response ->
        send_json_response(conn, 200, response)

      %{"error" => _} = response ->
        send_json_response(conn, 400, response)

      unexpected ->
        Logger.error("Unexpected MCP response: #{inspect(unexpected)}")
        send_json_response(conn, 500, %{
          jsonrpc: "2.0",
          id: Map.get(mcp_request, "id"),
          error: %{
            code: -32603,
            message: "Internal server error"
          }
        })
    end
  end

  defp handle_filtered_tools_list(conn, mcp_request, context) do
    all_tools = MCPServer.get_tools()
    filtered_tools = ToolFilter.filter_tools(all_tools, context)

    response = %{
      "jsonrpc" => "2.0",
      "id" => Map.get(mcp_request, "id"),
      "result" => %{
        "tools" => filtered_tools,
        "_meta" => %{
          "filtered_for" => context.connection_type,
          "original_count" => length(all_tools),
          "filtered_count" => length(filtered_tools)
        }
      }
    }

    send_json_response(conn, 200, response)
  end

  defp generate_request_id do
    "http_req_" <> (:crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower))
  end
end
