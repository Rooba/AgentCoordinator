defmodule AgentCoordinator.InterfaceManager do
  @moduledoc """
  Centralized manager for multiple MCP interface modes.

  This module coordinates between different interface types:
  - STDIO interface (for local MCP clients like VSCode)
  - HTTP REST interface (for remote API access)
  - WebSocket interface (for real-time web clients)

  Responsibilities:
  - Start/stop interface servers based on configuration
  - Coordinate session state across interfaces
  - Apply appropriate tool filtering per interface
  - Monitor interface health and restart if needed
  - Provide unified metrics and monitoring
  """

  use GenServer
  require Logger
  alias AgentCoordinator.{HttpInterface, ToolFilter}

  defstruct [
    :config,
    :interfaces,
    :stdio_handler,
    :session_registry,
    :metrics
  ]

  @interface_types [:stdio, :http, :websocket]

  # Client API

  @doc """
  Start the interface manager with configuration.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Get current interface status.
  """
  def get_status do
    GenServer.call(__MODULE__, :get_status)
  end

  @doc """
  Start a specific interface type.
  """
  def start_interface(interface_type, opts \\ []) do
    GenServer.call(__MODULE__, {:start_interface, interface_type, opts})
  end

  @doc """
  Stop a specific interface type.
  """
  def stop_interface(interface_type) do
    GenServer.call(__MODULE__, {:stop_interface, interface_type})
  end

  @doc """
  Restart an interface.
  """
  def restart_interface(interface_type) do
    GenServer.call(__MODULE__, {:restart_interface, interface_type})
  end

  @doc """
  Get metrics for all interfaces.
  """
  def get_metrics do
    GenServer.call(__MODULE__, :get_metrics)
  end

  @doc """
  Register a session across interfaces.
  """
  def register_session(session_id, interface_type, session_info) do
    GenServer.cast(__MODULE__, {:register_session, session_id, interface_type, session_info})
  end

  @doc """
  Unregister a session.
  """
  def unregister_session(session_id) do
    GenServer.cast(__MODULE__, {:unregister_session, session_id})
  end

  # Server callbacks

  @impl GenServer
  def init(opts) do
    # Load configuration
    config = load_interface_config(opts)

    state = %__MODULE__{
      config: config,
      interfaces: %{},
      stdio_handler: nil,
      session_registry: %{},
      metrics: initialize_metrics()
    }

    Logger.info("Interface Manager starting with config: #{inspect(config.enabled_interfaces)}")

    # Start enabled interfaces
    {:ok, state, {:continue, :start_interfaces}}
  end

  @impl GenServer
  def handle_continue(:start_interfaces, state) do
    # Start each enabled interface
    updated_state = Enum.reduce(state.config.enabled_interfaces, state, fn interface_type, acc ->
      case start_interface_server(interface_type, state.config, acc) do
        {:ok, interface_info} ->
          Logger.info("Started #{interface_type} interface")
          %{acc | interfaces: Map.put(acc.interfaces, interface_type, interface_info)}

        {:error, reason} ->
          Logger.error("Failed to start #{interface_type} interface: #{reason}")
          acc
      end
    end)

    {:noreply, updated_state}
  end

  @impl GenServer
  def handle_call(:get_status, _from, state) do
    status = %{
      enabled_interfaces: state.config.enabled_interfaces,
      running_interfaces: Map.keys(state.interfaces),
      active_sessions: map_size(state.session_registry),
      config: %{
        stdio: state.config.stdio,
        http: state.config.http,
        websocket: state.config.websocket
      },
      uptime: get_uptime(),
      metrics: state.metrics
    }

    {:reply, status, state}
  end

  @impl GenServer
  def handle_call({:start_interface, interface_type, opts}, _from, state) do
    if interface_type in @interface_types do
      case start_interface_server(interface_type, state.config, state, opts) do
        {:ok, interface_info} ->
          updated_interfaces = Map.put(state.interfaces, interface_type, interface_info)
          updated_state = %{state | interfaces: updated_interfaces}

          Logger.info("Started #{interface_type} interface on demand")
          {:reply, {:ok, interface_info}, updated_state}

        {:error, reason} ->
          Logger.error("Failed to start #{interface_type} interface: #{reason}")
          {:reply, {:error, reason}, state}
      end
    else
      {:reply, {:error, "Unknown interface type: #{interface_type}"}, state}
    end
  end

  @impl GenServer
  def handle_call({:stop_interface, interface_type}, _from, state) do
    case Map.get(state.interfaces, interface_type) do
      nil ->
        {:reply, {:error, "Interface not running: #{interface_type}"}, state}

      interface_info ->
        case stop_interface_server(interface_type, interface_info) do
          :ok ->
            updated_interfaces = Map.delete(state.interfaces, interface_type)
            updated_state = %{state | interfaces: updated_interfaces}

            Logger.info("Stopped #{interface_type} interface")
            {:reply, :ok, updated_state}

          {:error, reason} ->
            Logger.error("Failed to stop #{interface_type} interface: #{reason}")
            {:reply, {:error, reason}, state}
        end
    end
  end

  @impl GenServer
  def handle_call({:restart_interface, interface_type}, _from, state) do
    case Map.get(state.interfaces, interface_type) do
      nil ->
        {:reply, {:error, "Interface not running: #{interface_type}"}, state}

      interface_info ->
        # Stop the interface
        case stop_interface_server(interface_type, interface_info) do
          :ok ->
            # Start it again
            case start_interface_server(interface_type, state.config, state) do
              {:ok, new_interface_info} ->
                updated_interfaces = Map.put(state.interfaces, interface_type, new_interface_info)
                updated_state = %{state | interfaces: updated_interfaces}

                Logger.info("Restarted #{interface_type} interface")
                {:reply, {:ok, new_interface_info}, updated_state}

              {:error, reason} ->
                # Remove from running interfaces since it failed to restart
                updated_interfaces = Map.delete(state.interfaces, interface_type)
                updated_state = %{state | interfaces: updated_interfaces}

                Logger.error("Failed to restart #{interface_type} interface: #{reason}")
                {:reply, {:error, reason}, updated_state}
            end

          {:error, reason} ->
            Logger.error("Failed to stop #{interface_type} interface for restart: #{reason}")
            {:reply, {:error, reason}, state}
        end
    end
  end

  @impl GenServer
  def handle_call(:get_metrics, _from, state) do
    # Collect metrics from all running interfaces
    interface_metrics = Enum.map(state.interfaces, fn {interface_type, interface_info} ->
      {interface_type, get_interface_metrics(interface_type, interface_info)}
    end) |> Enum.into(%{})

    metrics = %{
      interfaces: interface_metrics,
      sessions: %{
        total: map_size(state.session_registry),
        by_interface: get_sessions_by_interface(state.session_registry)
      },
      uptime: get_uptime(),
      timestamp: DateTime.utc_now()
    }

    {:reply, metrics, state}
  end

  @impl GenServer
  def handle_cast({:register_session, session_id, interface_type, session_info}, state) do
    session_data = %{
      interface_type: interface_type,
      info: session_info,
      registered_at: DateTime.utc_now(),
      last_activity: DateTime.utc_now()
    }

    updated_registry = Map.put(state.session_registry, session_id, session_data)
    updated_state = %{state | session_registry: updated_registry}

    Logger.debug("Registered session #{session_id} for #{interface_type}")
    {:noreply, updated_state}
  end

  @impl GenServer
  def handle_cast({:unregister_session, session_id}, state) do
    case Map.get(state.session_registry, session_id) do
      nil ->
        Logger.debug("Attempted to unregister unknown session: #{session_id}")
        {:noreply, state}

      _session_data ->
        updated_registry = Map.delete(state.session_registry, session_id)
        updated_state = %{state | session_registry: updated_registry}

        Logger.debug("Unregistered session #{session_id}")
        {:noreply, updated_state}
    end
  end

  @impl GenServer
  def handle_info({:DOWN, _ref, :process, pid, reason}, state) do
    # Handle interface process crashes
    case find_interface_by_pid(pid, state.interfaces) do
      {interface_type, _interface_info} ->
        Logger.error("#{interface_type} interface crashed: #{inspect(reason)}")

        # Remove from running interfaces
        updated_interfaces = Map.delete(state.interfaces, interface_type)
        updated_state = %{state | interfaces: updated_interfaces}

        # Optionally restart if configured
        if should_auto_restart?(interface_type, state.config) do
          Logger.info("Auto-restarting #{interface_type} interface")
          Process.send_after(self(), {:restart_interface, interface_type}, 5000)
        end

        {:noreply, updated_state}

      nil ->
        Logger.debug("Unknown process died: #{inspect(pid)}")
        {:noreply, state}
    end
  end

  @impl GenServer
  def handle_info({:restart_interface, interface_type}, state) do
    case start_interface_server(interface_type, state.config, state) do
      {:ok, interface_info} ->
        updated_interfaces = Map.put(state.interfaces, interface_type, interface_info)
        updated_state = %{state | interfaces: updated_interfaces}

        Logger.info("Auto-restarted #{interface_type} interface")
        {:noreply, updated_state}

      {:error, reason} ->
        Logger.error("Failed to auto-restart #{interface_type} interface: #{reason}")
        {:noreply, state}
    end
  end

  @impl GenServer
  def handle_info(message, state) do
    Logger.debug("Interface Manager received unexpected message: #{inspect(message)}")
    {:noreply, state}
  end

  # Private helper functions

  defp load_interface_config(opts) do
    # Load from application config and override with opts
    base_config = Application.get_env(:agent_coordinator, :interfaces, %{})

    # Default configuration
    default_config = %{
      enabled_interfaces: [:stdio],
      stdio: %{
        enabled: true,
        handle_stdio: true
      },
      http: %{
        enabled: false,
        port: 8080,
        host: "localhost",
        cors_enabled: true
      },
      websocket: %{
        enabled: false,
        port: 8081,
        host: "localhost"
      },
      auto_restart: %{
        stdio: false,
        http: true,
        websocket: true
      }
    }

    # Merge configurations
    config = deep_merge(default_config, base_config)
    config = deep_merge(config, Enum.into(opts, %{}))

    # Determine enabled interfaces from environment or config
    enabled = determine_enabled_interfaces(config)

    # Update individual interface enabled flags based on environment
    config = update_interface_enabled_flags(config, enabled)

    %{config | enabled_interfaces: enabled}
  end

  defp determine_enabled_interfaces(config) do
    # Check environment variables
    interface_mode = System.get_env("MCP_INTERFACE_MODE", "stdio")

    case interface_mode do
      "stdio" -> [:stdio]
      "http" -> [:http]
      "websocket" -> [:websocket]
      "all" -> [:stdio, :http, :websocket]
      "remote" -> [:http, :websocket]
      _ ->
        # Check for comma-separated list
        if String.contains?(interface_mode, ",") do
          interface_mode
          |> String.split(",")
          |> Enum.map(&String.trim/1)
          |> Enum.map(&String.to_atom/1)
          |> Enum.filter(&(&1 in @interface_types))
        else
          # Fall back to config
          Map.get(config, :enabled_interfaces, [:stdio])
        end
    end
  end

  defp update_interface_enabled_flags(config, enabled_interfaces) do
    # Update individual interface enabled flags based on which interfaces are enabled
    config
    |> update_in([:stdio, :enabled], fn _ -> :stdio in enabled_interfaces end)
    |> update_in([:http, :enabled], fn _ -> :http in enabled_interfaces end)
    |> update_in([:websocket, :enabled], fn _ -> :websocket in enabled_interfaces end)
    # Also update ports from environment if set
    |> update_http_config_from_env()
  end

  defp update_http_config_from_env(config) do
    config = case System.get_env("MCP_HTTP_PORT") do
      nil -> config
      port_str ->
        case Integer.parse(port_str) do
          {port, ""} -> put_in(config, [:http, :port], port)
          _ -> config
        end
    end

    case System.get_env("MCP_HTTP_HOST") do
      nil -> config
      host -> put_in(config, [:http, :host], host)
    end
  end

  # Declare defaults once
  defp start_interface_server(type, config, state, opts \\ %{})

  defp start_interface_server(:stdio, config, state, _opts) do
    if config.stdio.enabled and config.stdio.handle_stdio do
      # Start stdio handler
      stdio_handler = spawn_link(fn -> handle_stdio_loop(state) end)

      interface_info = %{
        type: :stdio,
        pid: stdio_handler,
        started_at: DateTime.utc_now(),
        config: config.stdio
      }

      {:ok, interface_info}
    else
      {:error, "STDIO interface not enabled"}
    end
  end

  defp start_interface_server(:http, config, _state, opts) do
    if config.http.enabled do
      http_opts = [
        port: Map.get(opts, :port, config.http.port),
        host: Map.get(opts, :host, config.http.host)
      ]

      case HttpInterface.start_link(http_opts) do
        {:ok, pid} ->
          # Monitor the process
          ref = Process.monitor(pid)

          interface_info = %{
            type: :http,
            pid: pid,
            monitor_ref: ref,
            started_at: DateTime.utc_now(),
            config: Map.merge(config.http, Enum.into(opts, %{})),
            port: http_opts[:port]
          }

          {:ok, interface_info}

        {:error, reason} ->
          {:error, reason}
      end
    else
      {:error, "HTTP interface not enabled"}
    end
  end

  defp start_interface_server(:websocket, config, _state, _opts) do
    if config.websocket.enabled do
      # WebSocket is handled by the HTTP server, so just mark it as enabled
      interface_info = %{
        type: :websocket,
        pid: :embedded,  # Embedded in HTTP server
        started_at: DateTime.utc_now(),
        config: config.websocket
      }

      {:ok, interface_info}
    else
      {:error, "WebSocket interface not enabled"}
    end
  end

  defp start_interface_server(unknown_type, _config, _state, _opts) do
    {:error, "Unknown interface type: #{unknown_type}"}
  end

  defp stop_interface_server(:stdio, interface_info) do
    if Process.alive?(interface_info.pid) do
      Process.exit(interface_info.pid, :shutdown)
      :ok
    else
      :ok
    end
  end

  defp stop_interface_server(:http, interface_info) do
    if Process.alive?(interface_info.pid) do
      Process.exit(interface_info.pid, :shutdown)
      :ok
    else
      :ok
    end
  end

  defp stop_interface_server(:websocket, _interface_info) do
    # WebSocket is embedded in HTTP server, so nothing to stop separately
    :ok
  end

  defp stop_interface_server(_type, _interface_info) do
    {:error, "Unknown interface type"}
  end

  defp handle_stdio_loop(state) do
    # Handle MCP JSON-RPC messages from STDIO
    case IO.read(:stdio, :line) do
      :eof ->
        Logger.info("STDIO interface shutting down (EOF)")
        exit(:normal)

      {:error, reason} ->
        Logger.error("STDIO error: #{inspect(reason)}")
        exit({:error, reason})

      line ->
        handle_stdio_message(String.trim(line), state)
        handle_stdio_loop(state)
    end
  end

  defp handle_stdio_message("", _state), do: :ok

  defp handle_stdio_message(json_line, _state) do
    try do
      request = Jason.decode!(json_line)

      # Create local client context for stdio
      _client_context = ToolFilter.local_context()

      # Process through MCP server with full tool access
      response = AgentCoordinator.MCPServer.handle_mcp_request(request)

      # Send response
      IO.puts(Jason.encode!(response))
    rescue
      e in Jason.DecodeError ->
        error_response = %{
          "jsonrpc" => "2.0",
          "id" => nil,
          "error" => %{
            "code" => -32700,
            "message" => "Parse error: #{Exception.message(e)}"
          }
        }
        IO.puts(Jason.encode!(error_response))

      e ->
        # Try to get the ID from the malformed request
        id = try do
          partial = Jason.decode!(json_line)
          Map.get(partial, "id")
        rescue
          _ -> nil
        end

        error_response = %{
          "jsonrpc" => "2.0",
          "id" => id,
          "error" => %{
            "code" => -32603,
            "message" => "Internal error: #{Exception.message(e)}"
          }
        }
        IO.puts(Jason.encode!(error_response))
    end
  end

  defp get_interface_metrics(:stdio, interface_info) do
    %{
      type: :stdio,
      status: if(Process.alive?(interface_info.pid), do: :running, else: :stopped),
      uptime: DateTime.diff(DateTime.utc_now(), interface_info.started_at, :second),
      pid: interface_info.pid
    }
  end

  defp get_interface_metrics(:http, interface_info) do
    %{
      type: :http,
      status: if(Process.alive?(interface_info.pid), do: :running, else: :stopped),
      uptime: DateTime.diff(DateTime.utc_now(), interface_info.started_at, :second),
      port: interface_info.port,
      pid: interface_info.pid
    }
  end

  defp get_interface_metrics(:websocket, interface_info) do
    %{
      type: :websocket,
      status: :running,  # Embedded in HTTP server
      uptime: DateTime.diff(DateTime.utc_now(), interface_info.started_at, :second),
      embedded: true
    }
  end

  defp get_sessions_by_interface(session_registry) do
    Enum.reduce(session_registry, %{}, fn {_session_id, session_data}, acc ->
      interface_type = session_data.interface_type
      count = Map.get(acc, interface_type, 0)
      Map.put(acc, interface_type, count + 1)
    end)
  end

  defp find_interface_by_pid(pid, interfaces) do
    Enum.find(interfaces, fn {_type, interface_info} ->
      interface_info.pid == pid
    end)
  end

  defp should_auto_restart?(interface_type, config) do
    Map.get(config.auto_restart, interface_type, false)
  end

  defp initialize_metrics do
    %{
      started_at: DateTime.utc_now(),
      requests_total: 0,
      errors_total: 0,
      sessions_total: 0
    }
  end

  defp get_uptime do
    {uptime_ms, _} = :erlang.statistics(:wall_clock)
    div(uptime_ms, 1000)
  end

  # Deep merge helper for configuration
  defp deep_merge(left, right) when is_map(left) and is_map(right) do
    Map.merge(left, right, fn _key, left_val, right_val ->
      deep_merge(left_val, right_val)
    end)
  end

  defp deep_merge(_left, right), do: right
end
