defmodule AgentCoordinator.SessionManager do
  @moduledoc """
  Session management for MCP agents with token-based authentication.

  Implements MCP-compliant session management where:
  1. Agents register and receive session tokens
  2. Session tokens must be included in Mcp-Session-Id headers
  3. Session tokens are cryptographically secure and time-limited
  4. Sessions are tied to specific agent IDs
  """

  use GenServer
  require Logger

  defstruct [
    :sessions,
    :config
  ]

  @session_expiry_minutes 60
  @cleanup_interval_minutes 5

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Generate a new session token for an agent.
  Returns {:ok, session_token} or {:error, reason}
  """
  def create_session(agent_id, metadata \\ %{}) do
    GenServer.call(__MODULE__, {:create_session, agent_id, metadata})
  end

  @doc """
  Validate a session token and return agent information.
  Returns {:ok, agent_id, metadata} or {:error, reason}
  """
  def validate_session(session_token) do
    GenServer.call(__MODULE__, {:validate_session, session_token})
  end

  @doc """
  Invalidate a session token.
  """
  def invalidate_session(session_token) do
    GenServer.call(__MODULE__, {:invalidate_session, session_token})
  end

  @doc """
  Get all active sessions for an agent.
  """
  def get_agent_sessions(agent_id) do
    GenServer.call(__MODULE__, {:get_agent_sessions, agent_id})
  end

  @doc """
  Clean up expired sessions.
  """
  def cleanup_expired_sessions do
    GenServer.cast(__MODULE__, :cleanup_expired)
  end

  # Server implementation

  @impl GenServer
  def init(opts) do
    # Start periodic cleanup
    schedule_cleanup()

    state = %__MODULE__{
      sessions: %{},
      config: %{
        expiry_minutes: Keyword.get(opts, :expiry_minutes, @session_expiry_minutes),
        cleanup_interval: Keyword.get(opts, :cleanup_interval, @cleanup_interval_minutes)
      }
    }

    IO.puts(:stderr, "SessionManager started with #{state.config.expiry_minutes}min expiry")
    {:ok, state}
  end

  @impl GenServer
  def handle_call({:create_session, agent_id, metadata}, _from, state) do
    session_token = generate_session_token()
    expires_at = DateTime.add(DateTime.utc_now(), state.config.expiry_minutes, :minute)

    session_data = %{
      agent_id: agent_id,
      token: session_token,
      created_at: DateTime.utc_now(),
      expires_at: expires_at,
      metadata: metadata,
      last_activity: DateTime.utc_now()
    }

    new_sessions = Map.put(state.sessions, session_token, session_data)
    new_state = %{state | sessions: new_sessions}

    IO.puts(:stderr, "Created session #{session_token} for agent #{agent_id}")
    {:reply, {:ok, session_token}, new_state}
  end

  @impl GenServer
  def handle_call({:validate_session, session_token}, _from, state) do
    case Map.get(state.sessions, session_token) do
      nil ->
        {:reply, {:error, :session_not_found}, state}

      session_data ->
        if DateTime.compare(DateTime.utc_now(), session_data.expires_at) == :gt do
          # Session expired, remove it
          new_sessions = Map.delete(state.sessions, session_token)
          new_state = %{state | sessions: new_sessions}
          {:reply, {:error, :session_expired}, new_state}
        else
          # Session valid, update last activity
          updated_session = %{session_data | last_activity: DateTime.utc_now()}
          new_sessions = Map.put(state.sessions, session_token, updated_session)
          new_state = %{state | sessions: new_sessions}

          result = {:ok, session_data.agent_id, session_data.metadata}
          {:reply, result, new_state}
        end
    end
  end

  @impl GenServer
  def handle_call({:invalidate_session, session_token}, _from, state) do
    case Map.get(state.sessions, session_token) do
      nil ->
        {:reply, {:error, :session_not_found}, state}

      session_data ->
        new_sessions = Map.delete(state.sessions, session_token)
        new_state = %{state | sessions: new_sessions}
        IO.puts(:stderr, "Invalidated session #{session_token} for agent #{session_data.agent_id}")
        {:reply, :ok, new_state}
    end
  end

  @impl GenServer
  def handle_call({:get_agent_sessions, agent_id}, _from, state) do
    agent_sessions =
      state.sessions
      |> Enum.filter(fn {_token, session} -> session.agent_id == agent_id end)
      |> Enum.map(fn {token, session} -> {token, session} end)

    {:reply, agent_sessions, state}
  end

  @impl GenServer
  def handle_cast(:cleanup_expired, state) do
    now = DateTime.utc_now()

    {expired_sessions, active_sessions} =
      Enum.split_with(state.sessions, fn {_token, session} ->
        DateTime.compare(now, session.expires_at) == :gt
      end)

    if length(expired_sessions) > 0 do
      IO.puts(:stderr, "Cleaned up #{length(expired_sessions)} expired sessions")
    end

    new_state = %{state | sessions: Map.new(active_sessions)}
    schedule_cleanup()
    {:noreply, new_state}
  end

  @impl GenServer
  def handle_info(:cleanup_expired, state) do
    handle_cast(:cleanup_expired, state)
  end

  # Private functions

  defp generate_session_token do
    # Generate cryptographically secure session token
    # Format: "mcp_" + base64url(32 random bytes) + "_" + timestamp
    random_bytes = :crypto.strong_rand_bytes(32)
    timestamp = DateTime.utc_now() |> DateTime.to_unix()

    token_body = Base.url_encode64(random_bytes, padding: false)
    "mcp_#{token_body}_#{timestamp}"
  end

  defp schedule_cleanup do
    Process.send_after(self(), :cleanup_expired, @cleanup_interval_minutes * 60 * 1000)
  end
end
