defmodule AgentCoordinator.VSCodePermissions do
  @moduledoc """
  Manages permissions for VS Code tool access.

  Provides fine-grained permission control for agents accessing VS Code tools,
  ensuring security and preventing unauthorized operations.
  """

  require Logger

  @permission_levels %{
    read_only: 1,
    editor: 2,
    filesystem: 3,
    terminal: 4,
    git: 5,
    admin: 6
  }

  @tool_permissions %{
    # File Operations (filesystem level)
    "vscode_read_file" => :read_only,
    "vscode_write_file" => :filesystem,
    "vscode_create_file" => :filesystem,
    "vscode_delete_file" => :filesystem,
    "vscode_list_directory" => :read_only,
    "vscode_get_workspace_folders" => :read_only,

    # Editor Operations
    "vscode_get_active_editor" => :read_only,
    "vscode_set_editor_content" => :editor,
    "vscode_get_selection" => :read_only,
    "vscode_set_selection" => :editor,

    # Command Operations (varies by command)
    # Default to admin, will check specific commands
    "vscode_run_command" => :admin,

    # User Communication
    "vscode_show_message" => :read_only
  }

  @whitelisted_commands [
    # Safe editor commands
    "editor.action.formatDocument",
    "editor.action.formatSelection",
    "editor.action.organizeImports",
    "editor.fold",
    "editor.unfold",
    "editor.toggleFold",

    # Safe navigation commands
    "workbench.action.navigateBack",
    "workbench.action.navigateForward",
    "workbench.action.gotoLine",
    "workbench.action.quickOpen",
    "workbench.action.showCommands",

    # Safe file operations
    "workbench.action.files.save",
    "workbench.action.files.saveAll",
    "workbench.explorer.refreshExplorer",

    # Language service operations
    "editor.action.goToDeclaration",
    "editor.action.goToDefinition",
    "editor.action.goToReferences",
    "editor.action.rename",
    "editor.action.quickFix"
  ]

  @doc """
  Check if an agent has permission to use a specific VS Code tool.

  Returns {:ok, permission_level} if allowed, {:error, reason} if denied.
  """
  def check_permission(context, tool_name, args) do
    agent_id = context[:agent_id] || "unknown"

    # Get required permission level for this tool
    required_level = get_required_permission(tool_name, args)

    # Get agent's permission level
    agent_level = get_agent_permission_level(agent_id)

    # Check if agent has sufficient permissions
    if permission_sufficient?(agent_level, required_level) do
      # Additional checks for specific tools
      case additional_checks(tool_name, args, context) do
        :ok ->
          {:ok, required_level}

        {:error, reason} ->
          {:error, reason}
      end
    else
      {:error, "Insufficient permissions. Required: #{required_level}, Agent has: #{agent_level}"}
    end
  end

  @doc """
  Get an agent's permission level based on their capabilities and trust level.
  """
  def get_agent_permission_level(agent_id) do
    # For now, default to filesystem level for GitHub Copilot
    # In a real implementation, this would check:
    # - Agent registration data
    # - Trust scores
    # - Capability declarations
    # - User-configured permissions

    case agent_id do
      "github_copilot_session" -> :filesystem
      # Other registered agents
      id when is_binary(id) and byte_size(id) > 0 -> :editor
      # Unknown agents
      _ -> :read_only
    end
  end

  @doc """
  Update an agent's permission level (for administrative purposes).
  """
  def set_agent_permission_level(agent_id, level)
      when level in [:read_only, :editor, :filesystem, :terminal, :git, :admin] do
    # This would persist to a database or configuration store
    IO.puts(:stderr, "Setting permission level for agent #{agent_id} to #{level}")
    :ok
  end

  # Private functions

  defp get_required_permission(tool_name, args) do
    case Map.get(@tool_permissions, tool_name) do
      # Unknown tools require admin by default
      nil ->
        :admin

      :admin when tool_name == "vscode_run_command" ->
        # Special handling for run_command - check specific command
        command = args["command"]

        if command in @whitelisted_commands do
          # Whitelisted commands only need editor level
          :editor
        else
          # Unknown commands need admin
          :admin
        end

      level ->
        level
    end
  end

  defp permission_sufficient?(agent_level, required_level) do
    agent_numeric = Map.get(@permission_levels, agent_level, 0)
    required_numeric = Map.get(@permission_levels, required_level, 999)
    agent_numeric >= required_numeric
  end

  defp additional_checks(tool_name, args, context) do
    case tool_name do
      tool when tool in ["vscode_write_file", "vscode_create_file", "vscode_delete_file"] ->
        check_workspace_bounds(args["path"], context)

      "vscode_run_command" ->
        check_command_safety(args["command"], args["args"])

      _ ->
        :ok
    end
  end

  defp check_workspace_bounds(path, _context) when is_binary(path) do
    # Ensure file operations are within workspace bounds
    # This is a simplified check - real implementation would use VS Code workspace API

    forbidden_patterns = [
      # System directories
      "/etc/",
      "/bin/",
      "/usr/",
      "/var/",
      "/tmp/",
      # User sensitive areas
      "/.ssh/",
      "/.config/",
      "/home/",
      "~",
      # Relative path traversal
      "../",
      "..\\"
    ]

    if Enum.any?(forbidden_patterns, fn pattern -> String.contains?(path, pattern) end) do
      {:error, "Path outside workspace bounds or accessing sensitive directories"}
    else
      :ok
    end
  end

  defp check_workspace_bounds(_path, _context), do: {:error, "Invalid path format"}

  defp check_command_safety(command, _args) when is_binary(command) do
    cond do
      command in @whitelisted_commands ->
        :ok

      String.starts_with?(command, "extension.") ->
        {:error, "Extension commands not allowed for security"}

      String.contains?(command, "terminal") ->
        {:error, "Terminal commands require terminal permission level"}

      String.contains?(command, "git") ->
        {:error, "Git commands require git permission level"}

      true ->
        {:error, "Command '#{command}' not in whitelist"}
    end
  end

  defp check_command_safety(_command, _args), do: {:error, "Invalid command format"}

  @doc """
  Get summary of permission levels and their capabilities.
  """
  def get_permission_info do
    %{
      levels: %{
        read_only: "File reading, workspace inspection, message display",
        editor: "Text editing, selections, safe editor commands",
        filesystem: "File creation/deletion, directory operations",
        terminal: "Terminal access and command execution",
        git: "Version control operations",
        admin: "Settings, extensions, unrestricted commands"
      },
      tool_requirements: @tool_permissions,
      whitelisted_commands: @whitelisted_commands
    }
  end
end
