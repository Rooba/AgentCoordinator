defmodule AgentCoordinator.Persistence do
  @moduledoc """
  Persistent storage for tasks and events using NATS JetStream.
  Provides configurable retention policies and event replay capabilities.
  """

  use GenServer

  defstruct [
    :nats_conn,
    :stream_name,
    :retention_policy
  ]

  @stream_config %{
    "name" => "AGENT_COORDINATION",
    "subjects" => ["agent.>", "task.>", "codebase.>", "cross-codebase.>"],
    "storage" => "file",
    "max_msgs" => 10_000_000,
    # 10GB
    "max_bytes" => 10_000_000_000,
    # 30 days in nanoseconds
    "max_age" => 30 * 24 * 60 * 60 * 1_000_000_000,
    # 1MB
    "max_msg_size" => 1_000_000,
    "retention" => "limits",
    "discard" => "old"
  }

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def store_event(subject, data) do
    GenServer.cast(__MODULE__, {:store_event, subject, data})
  end

  def get_agent_history(agent_id, opts \\ []) do
    GenServer.call(__MODULE__, {:get_agent_history, agent_id, opts})
  end

  def get_task_history(task_id, opts \\ []) do
    GenServer.call(__MODULE__, {:get_task_history, task_id, opts})
  end

  def replay_events(subject_filter, opts \\ []) do
    GenServer.call(__MODULE__, {:replay_events, subject_filter, opts})
  end

  def get_system_stats do
    GenServer.call(__MODULE__, :get_system_stats)
  end

  # Server callbacks

  def init(opts) do
    nats_config = Keyword.get(opts, :nats, [])
    retention_policy = Keyword.get(opts, :retention_policy, :default)

    # Only connect to NATS if config is provided
    nats_conn =
      case nats_config do
        [] ->
          nil

        config ->
          case Gnat.start_link(config) do
            {:ok, conn} -> conn
            {:error, _reason} -> nil
          end
      end

    # Only create stream if we have a connection
    if nats_conn do
      create_or_update_stream(nats_conn)
    end

    state = %__MODULE__{
      nats_conn: nats_conn,
      stream_name: @stream_config["name"],
      retention_policy: retention_policy
    }

    {:ok, state}
  end

  def handle_cast({:store_event, subject, data}, state) do
    enriched_data = enrich_event_data(data)
    message = Jason.encode!(enriched_data)

    # Only publish if we have a NATS connection
    if state.nats_conn do
      case Gnat.pub(state.nats_conn, subject, message, headers: event_headers()) do
        :ok ->
          :ok
      end
    end

    {:noreply, state}
  end

  def handle_call({:get_agent_history, agent_id, opts}, _from, state) do
    case state.nats_conn do
      nil ->
        {:reply, [], state}

      conn ->
        subject_filter = "agent.*.#{agent_id}"
        limit = Keyword.get(opts, :limit, 100)

        events = fetch_events(conn, subject_filter, limit)
        {:reply, events, state}
    end
  end

  def handle_call({:get_task_history, task_id, opts}, _from, state) do
    case state.nats_conn do
      nil ->
        {:reply, [], state}

      conn ->
        subject_filter = "task.*"
        limit = Keyword.get(opts, :limit, 100)

        events =
          fetch_events(conn, subject_filter, limit)
          |> Enum.filter(fn event ->
            case Map.get(event, "task") do
              %{"id" => ^task_id} -> true
              _ -> false
            end
          end)

        {:reply, events, state}
    end
  end

  def handle_call({:replay_events, subject_filter, opts}, _from, state) do
    case state.nats_conn do
      nil ->
        {:reply, [], state}

      conn ->
        limit = Keyword.get(opts, :limit, 1000)
        start_time = Keyword.get(opts, :start_time)

        events = fetch_events(conn, subject_filter, limit, start_time)
        {:reply, events, state}
    end
  end

  def handle_call(:get_system_stats, _from, state) do
    stats =
      case state.nats_conn do
        nil -> %{connected: false}
        conn -> get_stream_info(conn, state.stream_name) || %{connected: true}
      end

    {:reply, stats, state}
  end

  # Private helpers

  defp create_or_update_stream(conn) do
    # Check if stream exists
    case get_stream_info(conn, @stream_config["name"]) do
      nil ->
        # Create new stream
        create_stream(conn, @stream_config)

      _existing ->
        # Update existing stream if needed
        update_stream(conn, @stream_config)
    end
  end

  defp create_stream(conn, config) do
    request = %{
      "type" => "io.nats.jetstream.api.v1.stream_create_request",
      "config" => config
    }

    case Gnat.request(conn, "$JS.API.STREAM.CREATE.#{config["name"]}", Jason.encode!(request)) do
      {:ok, response} ->
        case Jason.decode!(response.body) do
          %{"error" => error} ->
            IO.puts("Failed to create stream: #{inspect(error)}")
            {:error, error}

          result ->
            IO.puts("Stream created successfully")
            {:ok, result}
        end

      {:error, reason} ->
        IO.puts("Failed to create stream: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp update_stream(_conn, _config) do
    # For simplicity, we'll just ensure the stream exists
    # In production, you might want more sophisticated update logic
    :ok
  end

  defp get_stream_info(conn, stream_name) do
    case Gnat.request(conn, "$JS.API.STREAM.INFO.#{stream_name}", "") do
      {:ok, response} ->
        case Jason.decode!(response.body) do
          %{"error" => _} -> nil
          info -> info
        end

      {:error, _} ->
        nil
    end
  end

  defp fetch_events(_conn, _subject_filter, _limit, start_time \\ nil) do
    # Create a consumer to fetch messages
    _consumer_config = %{
      "durable_name" => "temp_#{:rand.uniform(10000)}",
      "deliver_policy" => if(start_time, do: "by_start_time", else: "all"),
      "opt_start_time" => start_time,
      "max_deliver" => 1,
      "ack_policy" => "explicit"
    }

    # This is a simplified implementation
    # In production, you'd use proper JetStream consumer APIs
    # Return empty for now - would implement full JetStream integration
    []
  end

  defp enrich_event_data(data) do
    Map.merge(data, %{
      "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601(),
      "version" => "1.0"
    })
  end

  defp event_headers do
    [
      {"content-type", "application/json"},
      {"source", "agent-coordinator"}
    ]
  end
end
