defmodule AgentCoordinator.ToolFilter do
  @moduledoc """
  Intelligent tool filtering system that adapts available tools based on client context.

  This module determines which tools should be available to different types of clients:
  - Local clients: Full tool access including filesystem and VSCode tools
  - Remote clients: Limited to agent coordination and safe remote tools
  - Web clients: Browser-safe tools only

  Tool filtering is based on:
  - Tool capabilities and requirements
  - Client connection type (local/remote)
  - Security considerations
  - Tool metadata annotations
  """

  require Logger

  @doc """
  Context information about the client connection.
  """
  defstruct [
    :connection_type,  # :local, :remote, :web
    :client_info,      # Client identification
    :capabilities,     # Client declared capabilities
    :security_level,   # :trusted, :sandboxed, :restricted
    :origin,          # For web clients, the origin domain
    :user_agent       # Client user agent string
  ]

  @type client_context :: %__MODULE__{
    connection_type: :local | :remote | :web,
    client_info: map(),
    capabilities: [String.t()],
    security_level: :trusted | :sandboxed | :restricted,
    origin: String.t() | nil,
    user_agent: String.t() | nil
  }

  # Tool name patterns that indicate local-only functionality (defined as function to avoid compilation issues)
  defp local_only_patterns do
    [
      ~r/^(read_file|write_file|create_file|delete_file)/,
      ~r/^(list_dir|search_files|move_file)/,
      ~r/^vscode_/,
      ~r/^(run_in_terminal|get_terminal)/,
      ~r/filesystem/,
      ~r/directory/
    ]
  end

  # Tools that are always safe for remote access
  @always_safe_tools [
    # Agent coordination tools
    "register_agent",
    "create_task",
    "get_next_task",
    "complete_task",
    "get_task_board",
    "get_detailed_task_board",
    "get_agent_task_history",
    "heartbeat",
    "unregister_agent",
    "register_task_set",
    "create_agent_task",
    "create_cross_codebase_task",
    "list_codebases",
    "register_codebase",
    "get_codebase_status",
    "add_codebase_dependency",

    # Memory and knowledge graph (safe for remote)
    "create_entities",
    "create_relations",
    "read_graph",
    "search_nodes",
    "open_nodes",
    "add_observations",
    "delete_entities",
    "delete_relations",
    "delete_observations",

    # Sequential thinking (safe for remote)
    "sequentialthinking",

    # Library documentation (safe for remote)
    "get-library-docs",
    "resolve-library-id"
  ]

  @doc """
  Filter tools based on client context.

  Returns a filtered list of tools appropriate for the client's context.
  """
  @spec filter_tools([map()], client_context()) :: [map()]
  def filter_tools(tools, %__MODULE__{} = context) do
    tools
    |> Enum.filter(&should_include_tool?(&1, context))
    |> maybe_annotate_tools(context)
  end

  @doc """
  Determine if a tool should be included for the given client context.
  """
  @spec should_include_tool?(map(), client_context()) :: boolean()
  def should_include_tool?(tool, context) do
    tool_name = Map.get(tool, "name", "")

    cond do
      # Always include safe tools
      tool_name in @always_safe_tools ->
        true

      # Local clients get everything
      context.connection_type == :local ->
        true

      # Remote/web clients get filtered access
      context.connection_type in [:remote, :web] ->
        not is_local_only_tool?(tool, context)

      # Default to restrictive
      true ->
        tool_name in @always_safe_tools
    end
  end

  @doc """
  Detect client context from connection information.
  """
  @spec detect_client_context(map()) :: client_context()
  def detect_client_context(connection_info) do
    connection_type = determine_connection_type(connection_info)
    security_level = determine_security_level(connection_type, connection_info)

    %__MODULE__{
      connection_type: connection_type,
      client_info: Map.get(connection_info, :client_info, %{}),
      capabilities: Map.get(connection_info, :capabilities, []),
      security_level: security_level,
      origin: Map.get(connection_info, :origin),
      user_agent: Map.get(connection_info, :user_agent)
    }
  end

  @doc """
  Create a local client context (for stdio and direct connections).
  """
  @spec local_context() :: client_context()
  def local_context do
    %__MODULE__{
      connection_type: :local,
      client_info: %{type: "local_stdio"},
      capabilities: ["full_access"],
      security_level: :trusted,
      origin: nil,
      user_agent: "agent-coordinator-local"
    }
  end

  @doc """
  Create a remote client context.
  """
  @spec remote_context(map()) :: client_context()
  def remote_context(opts \\ %{}) do
    %__MODULE__{
      connection_type: :remote,
      client_info: Map.get(opts, :client_info, %{type: "remote_http"}),
      capabilities: Map.get(opts, :capabilities, ["coordination"]),
      security_level: :sandboxed,
      origin: Map.get(opts, :origin),
      user_agent: Map.get(opts, :user_agent, "unknown")
    }
  end

  @doc """
  Get tool filtering statistics for monitoring.
  """
  @spec get_filter_stats([map()], client_context()) :: map()
  def get_filter_stats(original_tools, context) do
    filtered_tools = filter_tools(original_tools, context)

    %{
      original_count: length(original_tools),
      filtered_count: length(filtered_tools),
      removed_count: length(original_tools) - length(filtered_tools),
      connection_type: context.connection_type,
      security_level: context.security_level,
      filtered_at: DateTime.utc_now()
    }
  end

  # Private helpers

  defp is_local_only_tool?(tool, _context) do
    tool_name = Map.get(tool, "name", "")
    description = Map.get(tool, "description", "")

    # Check against known local-only tool names
    name_is_local = tool_name in get_local_only_tool_names() or
                   Enum.any?(local_only_patterns(), &Regex.match?(&1, tool_name))

    # Check description for local-only indicators
    description_is_local = String.contains?(String.downcase(description),
      ["filesystem", "file system", "vscode", "terminal", "local file", "directory"])

    # Check tool schema for local-only parameters
    schema_is_local = has_local_only_parameters?(tool)

    name_is_local or description_is_local or schema_is_local
  end

  defp get_local_only_tool_names do
    [
      # Filesystem tools
      "read_file", "write_file", "create_file", "delete_file",
      "list_directory", "search_files", "move_file", "get_file_info",
      "list_allowed_directories", "directory_tree", "edit_file",
      "read_text_file", "read_multiple_files", "read_media_file",

      # VSCode tools
      "vscode_create_file", "vscode_write_file", "vscode_read_file",
      "vscode_delete_file", "vscode_list_directory", "vscode_get_active_editor",
      "vscode_set_editor_content", "vscode_get_selection", "vscode_set_selection",
      "vscode_show_message", "vscode_run_command", "vscode_get_workspace_folders",

      # Terminal/process tools
      "run_in_terminal", "get_terminal_output", "terminal_last_command",
      "terminal_selection"
    ]
  end

  defp has_local_only_parameters?(tool) do
    schema = Map.get(tool, "inputSchema", %{})
    properties = Map.get(schema, "properties", %{})

    # Look for file path parameters or other local indicators
    Enum.any?(properties, fn {param_name, param_schema} ->
      param_name in ["path", "filePath", "file_path", "directory", "workspace_path"] or
      String.contains?(Map.get(param_schema, "description", ""),
        ["file path", "directory", "workspace", "local"])
    end)
  end

  defp determine_connection_type(connection_info) do
    cond do
      Map.get(connection_info, :transport) == :stdio -> :local
      Map.get(connection_info, :transport) == :websocket -> :web
      Map.get(connection_info, :transport) == :http -> :remote
      Map.get(connection_info, :remote_ip) == "127.0.0.1" -> :local
      Map.get(connection_info, :remote_ip) == "::1" -> :local
      Map.has_key?(connection_info, :remote_ip) -> :remote
      true -> :local  # Default to local for stdio
    end
  end

  defp determine_security_level(connection_type, connection_info) do
    case connection_type do
      :local -> :trusted
      :remote ->
        if Map.get(connection_info, :secure, false) do
          :sandboxed
        else
          :restricted
        end
      :web -> :sandboxed
    end
  end

  defp maybe_annotate_tools(tools, context) do
    # Add context information to tools if needed
    if context.connection_type == :remote do
      Enum.map(tools, fn tool ->
        Map.put(tool, "_filtered_for", "remote_client")
      end)
    else
      tools
    end
  end

end
