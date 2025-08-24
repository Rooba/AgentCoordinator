defmodule AgentCoordinator.MCPServerManager do
  @moduledoc """
  Manages external MCP servers as internal clients.

  This module starts, monitors, and communicates with external MCP servers,
  acting as a client to each while presenting their tools through the
  unified Agent Coordinator interface.
  """

  use GenServer
  require Logger

  defstruct [
    :servers,
    :server_processes,
    :tool_registry,
    :config
  ]

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Get all tools from all managed servers plus Agent Coordinator tools
  """
  def get_unified_tools do
    GenServer.call(__MODULE__, :get_unified_tools, 60_000)
  end

  @doc """
  Route a tool call to the appropriate server
  """
  def route_tool_call(tool_name, arguments, agent_context) do
    GenServer.call(__MODULE__, {:route_tool_call, tool_name, arguments, agent_context}, 60_000)
  end

  @doc """
  Get status of all managed servers
  """
  def get_server_status do
    GenServer.call(__MODULE__, :get_server_status, 15_000)
  end

  @doc """
  Restart a specific server
  """
  def restart_server(server_name) do
    GenServer.call(__MODULE__, {:restart_server, server_name}, 30_000)
  end

  @doc """
  Refresh tool registry by re-discovering tools from all servers
  """
  def refresh_tools do
    GenServer.call(__MODULE__, :refresh_tools, 60_000)
  end

  # Server callbacks

  def init(opts) do
    config = load_server_config(opts)

    state = %__MODULE__{
      servers: %{},
      server_processes: %{},
      tool_registry: %{},
      config: config
    }

    # Start all configured servers
    {:ok, state, {:continue, :start_servers}}
  end

  def handle_continue(:start_servers, state) do
    Logger.info("Starting external MCP servers...")

    new_state =
      Enum.reduce(state.config.servers, state, fn {name, config}, acc ->
        case start_server(name, config) do
          {:ok, server_info} ->
            Logger.info("Started MCP server: #{name}")

            %{
              acc
              | servers: Map.put(acc.servers, name, server_info),
                server_processes: Map.put(acc.server_processes, name, server_info.pid)
            }

          {:error, reason} ->
            Logger.error("Failed to start MCP server #{name}: #{reason}")
            acc
        end
      end)

    # Build initial tool registry
    updated_state = refresh_tool_registry(new_state)

    {:noreply, updated_state}
  end

  def handle_call(:get_unified_tools, _from, state) do
    # Combine Agent Coordinator tools with external server tools
    coordinator_tools = get_coordinator_tools()
    external_tools = Map.values(state.tool_registry) |> List.flatten()

    all_tools = coordinator_tools ++ external_tools

    {:reply, all_tools, state}
  end

  def handle_call({:route_tool_call, tool_name, arguments, agent_context}, _from, state) do
    case find_tool_server(tool_name, state) do
      {:coordinator, _} ->
        # Route to Agent Coordinator's own tools
        result = handle_coordinator_tool(tool_name, arguments, agent_context)
        {:reply, result, state}

      {:external, server_name} ->
        # Route to external server
        result = call_external_tool(server_name, tool_name, arguments, agent_context, state)
        {:reply, result, state}

      :not_found ->
        error_result = %{
          "error" => %{
            "code" => -32601,
            "message" => "Tool not found: #{tool_name}"
          }
        }

        {:reply, error_result, state}
    end
  end

  def handle_call(:get_server_status, _from, state) do
    status =
      Enum.map(state.servers, fn {name, server_info} ->
        {name,
         %{
           status: if(Process.alive?(server_info.pid), do: :running, else: :stopped),
           pid: server_info.pid,
           tools_count: length(Map.get(state.tool_registry, name, [])),
           started_at: server_info.started_at
         }}
      end)
      |> Map.new()

    {:reply, status, state}
  end

  def handle_call({:restart_server, server_name}, _from, state) do
    case Map.get(state.servers, server_name) do
      nil ->
        {:reply, {:error, "Server not found"}, state}

      server_info ->
        # Stop existing server
        if Process.alive?(server_info.pid) do
          Process.exit(server_info.pid, :kill)
        end

        # Start new server
        server_config = Map.get(state.config.servers, server_name)

        case start_server(server_name, server_config) do
          {:ok, new_server_info} ->
            new_state = %{
              state
              | servers: Map.put(state.servers, server_name, new_server_info),
                server_processes:
                  Map.put(state.server_processes, server_name, new_server_info.pid)
            }

            updated_state = refresh_tool_registry(new_state)
            {:reply, {:ok, new_server_info}, updated_state}

          {:error, reason} ->
            {:reply, {:error, reason}, state}
        end
    end
  end

  def handle_call(:refresh_tools, _from, state) do
    # Re-discover tools from all running servers
    updated_state = rediscover_all_tools(state)

    all_tools = get_coordinator_tools() ++ (Map.values(updated_state.tool_registry) |> List.flatten())

    Logger.info("Refreshed tool registry: found #{length(all_tools)} total tools")

    {:reply, {:ok, length(all_tools)}, updated_state}
  end

  def handle_info({:DOWN, _ref, :port, port, reason}, state) do
    # Handle server port death
    case find_server_by_port(port, state.servers) do
      {server_name, server_info} ->
        Logger.warning("MCP server #{server_name} port died: #{reason}")

        # Cleanup PID file and kill external process
        if server_info.pid_file_path do
          cleanup_pid_file(server_info.pid_file_path)
        end
        if server_info.os_pid do
          kill_external_process(server_info.os_pid)
        end

        # Remove from state
        new_state = %{
          state
          | servers: Map.delete(state.servers, server_name),
            server_processes: Map.delete(state.server_processes, server_name),
            tool_registry: Map.delete(state.tool_registry, server_name)
        }

        # Attempt restart if configured
        if should_auto_restart?(server_name, state.config) do
          Logger.info("Auto-restarting MCP server: #{server_name}")
          Process.send_after(self(), {:restart_server, server_name}, 1000)
        end

        {:noreply, new_state}

      nil ->
        {:noreply, state}
    end
  end

  def handle_info({:restart_server, server_name}, state) do
    server_config = Map.get(state.config.servers, server_name)

    case start_server(server_name, server_config) do
      {:ok, server_info} ->
        Logger.info("Auto-restarted MCP server: #{server_name}")

        new_state = %{
          state
          | servers: Map.put(state.servers, server_name, server_info),
            server_processes: Map.put(state.server_processes, server_name, server_info.pid)
        }

        updated_state = refresh_tool_registry(new_state)
        {:noreply, updated_state}

      {:error, reason} ->
        Logger.error("Failed to auto-restart MCP server #{server_name}: #{reason}")
        {:noreply, state}
    end
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end

  # Private functions

  defp load_server_config(opts) do
    # Allow override from opts or config file
    config_file = Keyword.get(opts, :config_file, "mcp_servers.json")

    if File.exists?(config_file) do
      try do
        case Jason.decode!(File.read!(config_file)) do
          %{"servers" => servers} = full_config ->
            # Convert string types to atoms and normalize server configs
            normalized_servers =
              Enum.into(servers, %{}, fn {name, config} ->
                normalized_config =
                  config
                  |> Map.update("type", :stdio, fn
                    "stdio" -> :stdio
                    "http" -> :http
                    type when is_atom(type) -> type
                    type -> String.to_existing_atom(type)
                  end)
                  |> Enum.into(%{}, fn
                    {"type", type} -> {:type, type}
                    {key, value} -> {String.to_atom(key), value}
                  end)

                {name, normalized_config}
              end)

            base_config = %{servers: normalized_servers}

            # Add any additional config from the JSON file
            case Map.get(full_config, "config") do
              nil -> base_config
              additional_config ->
                Map.merge(base_config, %{config: additional_config})
            end

          _ ->
            Logger.warning("Invalid config file format in #{config_file}, using defaults")
            get_default_config()
        end
      rescue
        e ->
          Logger.warning("Failed to load config file #{config_file}: #{Exception.message(e)}, using defaults")
          get_default_config()
      end
    else
      Logger.warning("Config file #{config_file} not found, using defaults")
      get_default_config()
    end
  end

  defp get_default_config do
    %{
      servers: %{
        "mcp_context7" => %{
          type: :stdio,
          command: "uvx",
          args: ["mcp-server-context7"],
          auto_restart: true,
          description: "Context7 library documentation server"
        },
        "mcp_figma" => %{
          type: :stdio,
          command: "npx",
          args: ["-y", "@figma/mcp-server-figma"],
          auto_restart: true,
          description: "Figma design integration server"
        },
        "mcp_filesystem" => %{
          type: :stdio,
          command: "npx",
          args: ["-y", "@modelcontextprotocol/server-filesystem", "/home/ra"],
          auto_restart: true,
          description: "Filesystem operations server with heartbeat coverage"
        },
        "mcp_firebase" => %{
          type: :stdio,
          command: "npx",
          args: ["-y", "@firebase/mcp-server"],
          auto_restart: true,
          description: "Firebase integration server"
        },
        "mcp_memory" => %{
          type: :stdio,
          command: "npx",
          args: ["-y", "@modelcontextprotocol/server-memory"],
          auto_restart: true,
          description: "Memory and knowledge graph server"
        },
        "mcp_sequentialthi" => %{
          type: :stdio,
          command: "npx",
          args: ["-y", "@modelcontextprotocol/server-sequential-thinking"],
          auto_restart: true,
          description: "Sequential thinking and reasoning server"
        }
      }
    }
  end

  defp start_server(name, %{type: :stdio} = config) do
    case start_stdio_server(name, config) do
      {:ok, os_pid, port, pid_file_path} ->
        # Monitor the port (not the OS PID)
        port_ref = Port.monitor(port)

        server_info = %{
          name: name,
          type: :stdio,
          pid: port,  # Use port as the "pid" for process tracking
          os_pid: os_pid,
          port: port,
          pid_file_path: pid_file_path,
          port_ref: port_ref,
          started_at: DateTime.utc_now(),
          tools: []
        }

        # Initialize the server and get tools
        case initialize_server(server_info) do
          {:ok, tools} ->
            {:ok, %{server_info | tools: tools}}

          {:error, reason} ->
            # Cleanup on initialization failure
            cleanup_pid_file(pid_file_path)
            kill_external_process(os_pid)
            # Only close port if it's still open
            if Port.info(port) do
              Port.close(port)
            end
            {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp start_server(name, %{type: :http} = config) do
    # For HTTP servers, we don't spawn processes - just store connection info
    server_info = %{
      name: name,
      type: :http,
      url: Map.get(config, :url),
      pid: nil,  # No process to track for HTTP
      os_pid: nil,
      port: nil,
      pid_file_path: nil,
      port_ref: nil,
      started_at: DateTime.utc_now(),
      tools: []
    }

    # For HTTP servers, we can try to get tools but don't need process management
    case initialize_http_server(server_info) do
      {:ok, tools} ->
        {:ok, %{server_info | tools: tools}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp start_stdio_server(name, config) do
    command = Map.get(config, :command, "npx")
    args = Map.get(config, :args, [])
    env = Map.get(config, :env, %{})

    # Convert env map to list format expected by Port.open
    env_list = Enum.map(env, fn {key, value} -> {String.to_charlist(key), String.to_charlist(value)} end)

    port_options = [
      :binary,
      :stream,
      {:env, env_list},
      :exit_status,
      :hide
    ]

    try do
      port = Port.open({:spawn_executable, System.find_executable(command)},
                       [{:args, args} | port_options])

      # Get the OS PID of the spawned process
      {:os_pid, os_pid} = Port.info(port, :os_pid)

      # Create PID file for cleanup
      pid_file_path = create_pid_file(name, os_pid)

      Logger.info("Started MCP server #{name} with OS PID #{os_pid}")

      {:ok, os_pid, port, pid_file_path}
    rescue
      e ->
        Logger.error("Failed to start stdio server #{name}: #{Exception.message(e)}")
        {:error, Exception.message(e)}
    end
  end

  defp create_pid_file(server_name, os_pid) do
    pid_dir = Path.join(System.tmp_dir(), "mcp_servers")
    File.mkdir_p!(pid_dir)

    pid_file_path = Path.join(pid_dir, "#{server_name}.pid")
    File.write!(pid_file_path, to_string(os_pid))

    pid_file_path
  end

  defp cleanup_pid_file(pid_file_path) do
    if File.exists?(pid_file_path) do
      File.rm(pid_file_path)
    end
  end

  defp kill_external_process(os_pid) when is_integer(os_pid) do
    try do
      case System.cmd("kill", ["-TERM", to_string(os_pid)]) do
        {_, 0} ->
          Logger.info("Successfully terminated process #{os_pid}")
          :ok
        {_, _} ->
          # Try force kill
          case System.cmd("kill", ["-KILL", to_string(os_pid)]) do
            {_, 0} ->
              Logger.info("Force killed process #{os_pid}")
              :ok
            {_, _} ->
              Logger.warning("Failed to kill process #{os_pid}")
              :error
          end
      end
    rescue
      _ -> :error
    end
  end

  defp find_server_by_port(port, servers) do
    Enum.find(servers, fn {_name, server_info} ->
      server_info.port == port
    end)
  end

  defp initialize_server(server_info) do
    # Send initialize request
    init_request = %{
      "jsonrpc" => "2.0",
      "id" => 1,
      "method" => "initialize",
      "params" => %{
        "protocolVersion" => "2024-11-05",
        "capabilities" => %{},
        "clientInfo" => %{
          "name" => "agent-coordinator",
          "version" => "0.1.0"
        }
      }
    }

    with {:ok, _init_response} <- send_server_request(server_info, init_request),
         {:ok, tools_response} <- get_server_tools(server_info) do
      {:ok, tools_response}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp initialize_http_server(server_info) do
    # For HTTP servers, we would make HTTP requests instead of using ports
    # For now, return empty tools list as we need to implement HTTP client logic
    Logger.warning("HTTP server support not fully implemented yet for #{server_info.name}")
    {:ok, []}
  rescue
    e ->
      {:error, "HTTP server initialization failed: #{Exception.message(e)}"}
  end

  defp get_server_tools(server_info) do
    tools_request = %{
      "jsonrpc" => "2.0",
      "id" => 2,
      "method" => "tools/list"
    }

    case send_server_request(server_info, tools_request) do
      {:ok, %{"result" => %{"tools" => tools}}} ->
        {:ok, tools}

      {:ok, unexpected} ->
        Logger.warning(
          "Unexpected tools response from #{server_info.name}: #{inspect(unexpected)}"
        )

        {:ok, []}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp send_server_request(server_info, request) do
    request_json = Jason.encode!(request) <> "\n"

    Port.command(server_info.port, request_json)

    # Collect full response by reading multiple lines if needed
    response_data = collect_response(server_info.port, "", 30_000)

    cond do
      # Check if we got any response data
      response_data == "" ->
        {:error, "No response received from server #{server_info.name}"}
        
      # Try to decode JSON response
      true ->
        case Jason.decode(response_data) do
          {:ok, response} -> {:ok, response}
          {:error, %Jason.DecodeError{} = error} ->
            Logger.error("JSON decode error for server #{server_info.name}: #{Exception.message(error)}")
            Logger.debug("Raw response data: #{inspect(response_data)}")
            {:error, "JSON decode error: #{Exception.message(error)}"}
          {:error, reason} ->
            {:error, "JSON decode error: #{inspect(reason)}"}
        end
    end
  end

  defp collect_response(port, acc, timeout) do
    receive do
      {^port, {:data, data}} ->
        # Accumulate binary data
        new_acc = acc <> data
        
        # Try to extract complete JSON messages from the accumulated data
        case extract_json_messages(new_acc) do
          {json_message, _remaining} when json_message != nil ->
            # We found a complete JSON message, return it
            json_message
            
          {nil, remaining} ->
            # No complete JSON message yet, continue collecting
            collect_response(port, remaining, timeout)
        end

      {^port, {:exit_status, status}} ->
        Logger.error("Server exited with status: #{status}")
        acc

    after
      timeout ->
        Logger.error("Server request timeout after #{timeout}ms")
        acc
    end
  end

  # Extract complete JSON messages from accumulated binary data
  defp extract_json_messages(data) do
    lines = String.split(data, "\n", trim: false)
    
    # Process each line to find JSON messages and skip log messages
    {json_lines, _remaining_data} = extract_json_from_lines(lines, [])
    
    case json_lines do
      [] ->
        # No complete JSON found, return the last partial line if any
        last_line = List.last(lines) || ""
        if String.trim(last_line) != "" and not String.ends_with?(data, "\n") do
          {nil, last_line}
        else
          {nil, ""}
        end
        
      _ ->
        # Join all JSON lines and try to parse
        json_data = Enum.join(json_lines, "\n")
        
        case Jason.decode(json_data) do
          {:ok, _} ->
            # Valid JSON found
            {json_data, ""}
            
          {:error, _} ->
            # Invalid JSON, might be incomplete
            {nil, data}
        end
    end
  end

  defp extract_json_from_lines([], acc), do: {Enum.reverse(acc), ""}
  
  defp extract_json_from_lines([line], acc) do
    # This is the last line, it might be incomplete
    trimmed = String.trim(line)
    
    cond do
      trimmed == "" ->
        {Enum.reverse(acc), ""}
        
      # Skip log messages
      Regex.match?(~r/^\d{4}-\d{2}-\d{2}\s+\d{2}:\d{2}:\d{2}/, trimmed) ->
        {Enum.reverse(acc), ""}
        
      Regex.match?(~r/^\d{2}:\d{2}:\d{2}\.\d+\s+\[(info|warning|error|debug)\]/, trimmed) ->
        {Enum.reverse(acc), ""}
        
      # Check if this looks like JSON
      String.starts_with?(trimmed, ["{"]) ->
        {Enum.reverse([line | acc]), ""}
        
      true ->
        # Non-JSON line, might be incomplete
        {Enum.reverse(acc), line}
    end
  end
  
  defp extract_json_from_lines([line | rest], acc) do
    trimmed = String.trim(line)
    
    cond do
      trimmed == "" ->
        extract_json_from_lines(rest, acc)
        
      # Skip log messages
      Regex.match?(~r/^\d{4}-\d{2}-\d{2}\s+\d{2}:\d{2}:\d{2}/, trimmed) ->
        Logger.debug("Skipping log message from MCP server: #{trimmed}")
        extract_json_from_lines(rest, acc)
        
      Regex.match?(~r/^\d{2}:\d{2}:\d{2}\.\d+\s+\[(info|warning|error|debug)\]/, trimmed) ->
        Logger.debug("Skipping log message from MCP server: #{trimmed}")
        extract_json_from_lines(rest, acc)
        
      # Check if this looks like JSON
      String.starts_with?(trimmed, ["{"]) ->
        extract_json_from_lines(rest, [line | acc])
        
      true ->
        # Skip non-JSON lines
        Logger.debug("Skipping non-JSON line from MCP server: #{trimmed}")
        extract_json_from_lines(rest, acc)
    end
  end

  defp refresh_tool_registry(state) do
    new_registry =
      Enum.reduce(state.servers, %{}, fn {name, server_info}, acc ->
        tools = Map.get(server_info, :tools, [])
        Map.put(acc, name, tools)
      end)

    %{state | tool_registry: new_registry}
  end

  defp rediscover_all_tools(state) do
    # Re-query all running servers for their current tools
    updated_servers =
      Enum.reduce(state.servers, state.servers, fn {name, server_info}, acc ->
        # Check if server is alive (handle both PID and Port)
        server_alive = case server_info.pid do
          nil -> false
          pid when is_pid(pid) -> Process.alive?(pid)
          port when is_port(port) -> Port.info(port) != nil
          _ -> false
        end

        if server_alive do
          case get_server_tools(server_info) do
            {:ok, new_tools} ->
              Logger.debug("Rediscovered #{length(new_tools)} tools from #{name}")
              Map.put(acc, name, %{server_info | tools: new_tools})

            {:error, reason} ->
              Logger.warning("Failed to rediscover tools from #{name}: #{inspect(reason)}")
              acc
          end
        else
          Logger.warning("Server #{name} is not alive, skipping tool rediscovery")
          acc
        end
      end)

    # Update state with new server info and refresh tool registry
    new_state = %{state | servers: updated_servers}
    refresh_tool_registry(new_state)
  end

  defp find_tool_server(tool_name, state) do
    # Check all tool registries (both coordinator and external servers)
    # Start with coordinator tools
    coordinator_tools = get_coordinator_tools()
    if Enum.any?(coordinator_tools, fn tool -> tool["name"] == tool_name end) do
      {:coordinator, tool_name}
    else
      # Check external servers
      case find_external_tool_server(tool_name, state.tool_registry) do
        nil -> :not_found
        server_name -> {:external, server_name}
      end
    end
  end

  defp find_external_tool_server(tool_name, tool_registry) do
    Enum.find_value(tool_registry, fn {server_name, tools} ->
      if Enum.any?(tools, fn tool -> tool["name"] == tool_name end) do
        server_name
      else
        nil
      end
    end)
  end

  defp get_coordinator_tools do
    # Get Agent Coordinator native tools
    coordinator_native_tools = [
      %{
        "name" => "register_agent",
        "description" => "Register a new agent with the coordination system",
        "inputSchema" => %{
          "type" => "object",
          "properties" => %{
            "name" => %{"type" => "string"},
            "capabilities" => %{
              "type" => "array",
              "items" => %{"type" => "string"}
            },
            "metadata" => %{
              "type" => "object",
              "description" => "Optional metadata about the agent (e.g., client_type, session_id)"
            }
          },
          "required" => ["name", "capabilities"]
        }
      },
      %{
        "name" => "create_task",
        "description" => "Create a new task in the coordination system",
        "inputSchema" => %{
          "type" => "object",
          "properties" => %{
            "title" => %{"type" => "string"},
            "description" => %{"type" => "string"},
            "priority" => %{"type" => "string", "enum" => ["low", "normal", "high", "urgent"]},
            "required_capabilities" => %{
              "type" => "array",
              "items" => %{"type" => "string"}
            },
            "file_paths" => %{
              "type" => "array",
              "items" => %{"type" => "string"}
            }
          },
          "required" => ["title", "description"]
        }
      },
      %{
        "name" => "get_next_task",
        "description" => "Get the next task for an agent",
        "inputSchema" => %{
          "type" => "object",
          "properties" => %{
            "agent_id" => %{"type" => "string"}
          },
          "required" => ["agent_id"]
        }
      },
      %{
        "name" => "complete_task",
        "description" => "Mark current task as completed",
        "inputSchema" => %{
          "type" => "object",
          "properties" => %{
            "agent_id" => %{"type" => "string"}
          },
          "required" => ["agent_id"]
        }
      },
      %{
        "name" => "get_task_board",
        "description" => "Get overview of all agents and their current tasks",
        "inputSchema" => %{
          "type" => "object",
          "properties" => %{}
        }
      },
      %{
        "name" => "heartbeat",
        "description" => "Send heartbeat to maintain agent status",
        "inputSchema" => %{
          "type" => "object",
          "properties" => %{
            "agent_id" => %{"type" => "string"}
          },
          "required" => ["agent_id"]
        }
      }
    ]

    # Get VS Code tools only if VS Code functionality is available
    vscode_tools = try do
      if Code.ensure_loaded?(AgentCoordinator.VSCodeToolProvider) do
        AgentCoordinator.VSCodeToolProvider.get_tools()
      else
        Logger.debug("VS Code tools not available - module not loaded")
        []
      end
    rescue
      _ ->
        Logger.debug("VS Code tools not available - error loading")
        []
    end

    # Combine all coordinator tools
    coordinator_native_tools ++ vscode_tools
  end

  # Removed get_coordinator_tool_names - now using dynamic tool discovery

  defp handle_coordinator_tool(tool_name, arguments, agent_context) do
    # Route to existing Agent Coordinator functionality or VS Code tools
    case tool_name do
      "register_agent" ->
        opts = case arguments["metadata"] do
          nil -> []
          metadata -> [metadata: metadata]
        end

        AgentCoordinator.TaskRegistry.register_agent(
          arguments["name"],
          arguments["capabilities"],
          opts
        )

      "create_task" ->
        AgentCoordinator.TaskRegistry.create_task(
          arguments["title"],
          arguments["description"],
          Map.take(arguments, ["priority", "required_capabilities", "file_paths"])
        )

      "get_next_task" ->
        AgentCoordinator.TaskRegistry.get_next_task(arguments["agent_id"])

      "complete_task" ->
        AgentCoordinator.TaskRegistry.complete_task(arguments["agent_id"])

      "get_task_board" ->
        AgentCoordinator.TaskRegistry.get_task_board()

      "heartbeat" ->
        AgentCoordinator.TaskRegistry.heartbeat_agent(arguments["agent_id"])

      # VS Code tools - route to VS Code Tool Provider
      "vscode_" <> _rest ->
        AgentCoordinator.VSCodeToolProvider.handle_tool_call(tool_name, arguments, agent_context)

      _ ->
        %{"error" => %{"code" => -32601, "message" => "Unknown coordinator tool: #{tool_name}"}}
    end
  end

  defp call_external_tool(server_name, tool_name, arguments, agent_context, state) do
    case Map.get(state.servers, server_name) do
      nil ->
        %{"error" => %{"code" => -32603, "message" => "Server not available: #{server_name}"}}

      server_info ->
        # Send heartbeat before tool call if agent context available
        if agent_context && agent_context.agent_id do
          AgentCoordinator.TaskRegistry.heartbeat_agent(agent_context.agent_id)

          # Auto-create/update current task for this tool usage
          update_current_task(agent_context.agent_id, tool_name, arguments)
        end

        # Make the actual tool call
        tool_request = %{
          "jsonrpc" => "2.0",
          "id" => System.unique_integer([:positive]),
          "method" => "tools/call",
          "params" => %{
            "name" => tool_name,
            "arguments" => arguments
          }
        }

        result =
          case send_server_request(server_info, tool_request) do
            {:ok, response} ->
              # Send heartbeat after successful tool call
              if agent_context && agent_context.agent_id do
                AgentCoordinator.TaskRegistry.heartbeat_agent(agent_context.agent_id)
              end

              response

            {:error, reason} ->
              %{"error" => %{"code" => -32603, "message" => reason}}
          end

        result
    end
  end

  defp update_current_task(agent_id, tool_name, arguments) do
    # Create a descriptive task title based on the tool being used
    task_title = generate_task_title(tool_name, arguments)
    task_description = generate_task_description(tool_name, arguments)

    # Check if agent has current task, if not create one
    case AgentCoordinator.TaskRegistry.get_agent_current_task(agent_id) do
      nil ->
        # Create new auto-task
        AgentCoordinator.TaskRegistry.create_task(
          task_title,
          task_description,
          %{
            priority: "normal",
            auto_generated: true,
            tool_name: tool_name,
            assigned_agent: agent_id
          }
        )

        # Auto-assign to this agent
        case AgentCoordinator.TaskRegistry.get_next_task(agent_id) do
          {:ok, _task} -> :ok
          _ -> :ok
        end

      existing_task ->
        # Update existing task with latest activity
        AgentCoordinator.TaskRegistry.update_task_activity(
          existing_task.id,
          tool_name,
          arguments
        )
    end
  end

  defp generate_task_title(tool_name, arguments) do
    case tool_name do
      "read_file" ->
        "Reading file: #{Path.basename(arguments["path"] || "unknown")}"

      "write_file" ->
        "Writing file: #{Path.basename(arguments["path"] || "unknown")}"

      "list_directory" ->
        "Exploring directory: #{Path.basename(arguments["path"] || "unknown")}"

      "mcp_context7_get-library-docs" ->
        "Researching: #{arguments["context7CompatibleLibraryID"] || "library"}"

      "mcp_figma_get_code" ->
        "Generating Figma code: #{arguments["nodeId"] || "component"}"

      "mcp_firebase_firestore_get_documents" ->
        "Fetching Firestore documents"

      "mcp_memory_search_nodes" ->
        "Searching memory: #{arguments["query"] || "query"}"

      "mcp_sequentialthi_sequentialthinking" ->
        "Thinking through problem"

      _ ->
        "Using tool: #{tool_name}"
    end
  end

  defp generate_task_description(tool_name, arguments) do
    case tool_name do
      "read_file" ->
        "Reading and analyzing file content from #{arguments["path"]}"

      "write_file" ->
        "Creating or updating file at #{arguments["path"]}"

      "list_directory" ->
        "Exploring directory structure at #{arguments["path"]}"

      "mcp_context7_get-library-docs" ->
        "Researching documentation for #{arguments["context7CompatibleLibraryID"]} library"

      "mcp_figma_get_code" ->
        "Generating code for Figma component #{arguments["nodeId"]}"

      "mcp_firebase_firestore_get_documents" ->
        "Retrieving documents from Firestore: #{inspect(arguments["paths"])}"

      "mcp_memory_search_nodes" ->
        "Searching knowledge graph for: #{arguments["query"]}"

      "mcp_sequentialthi_sequentialthinking" ->
        "Using sequential thinking to solve complex problem"

      _ ->
        "Executing #{tool_name} with arguments: #{inspect(arguments)}"
    end
  end

  defp should_auto_restart?(server_name, config) do
    server_config = Map.get(config.servers, server_name, %{})
    Map.get(server_config, :auto_restart, false)
  end
end
