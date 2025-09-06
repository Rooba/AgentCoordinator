defmodule AgentCoordinator.ActivityTracker do
  @moduledoc """
  Tracks agent activities based on tool calls and infers human-readable activity descriptions.
  """

  alias AgentCoordinator.{Agent, TaskRegistry}

  @doc """
  Infer activity description and files from tool name and arguments.
  Returns {activity_description, files_list}.
  """
  def infer_activity(tool_name, args) do
    case tool_name do
      # File operations
      "read_file" ->
        file_path = extract_file_path(args)
        {"Reading #{Path.basename(file_path || "file")}", [file_path]}

      "read_text_file" ->
        file_path = extract_file_path(args)
        {"Reading #{Path.basename(file_path || "file")}", [file_path]}

      "read_multiple_files" ->
        files = Map.get(args, "paths", [])
        file_names = Enum.map(files, &Path.basename/1)
        {"Reading #{length(files)} files: #{Enum.join(file_names, ", ")}", files}

      "write_file" ->
        file_path = extract_file_path(args)
        {"Writing #{Path.basename(file_path || "file")}", [file_path]}

      "edit_file" ->
        file_path = extract_file_path(args)
        {"Editing #{Path.basename(file_path || "file")}", [file_path]}

      "create_file" ->
        file_path = extract_file_path(args)
        {"Creating #{Path.basename(file_path || "file")}", [file_path]}

      "move_file" ->
        source = Map.get(args, "source")
        dest = Map.get(args, "destination")
        files = [source, dest] |> Enum.filter(&(&1))
        {"Moving #{Path.basename(source || "file")} to #{Path.basename(dest || "destination")}", files}

      # VS Code operations
      "vscode_read_file" ->
        file_path = extract_file_path(args)
        {"Reading #{Path.basename(file_path || "file")} in VS Code", [file_path]}

      "vscode_write_file" ->
        file_path = extract_file_path(args)
        {"Writing #{Path.basename(file_path || "file")} in VS Code", [file_path]}

      "vscode_set_editor_content" ->
        file_path = Map.get(args, "file_path")
        if file_path do
          {"Editing #{Path.basename(file_path)} in VS Code", [file_path]}
        else
          {"Editing active file in VS Code", []}
        end

      "vscode_get_active_editor" ->
        {"Viewing active editor in VS Code", []}

      "vscode_get_selection" ->
        {"Viewing text selection in VS Code", []}

      # Directory operations
      "list_directory" ->
        path = extract_file_path(args)
        {"Browsing directory #{Path.basename(path || ".")}", []}

      "list_directory_with_sizes" ->
        path = extract_file_path(args)
        {"Browsing directory #{Path.basename(path || ".")} with sizes", []}

      "directory_tree" ->
        path = extract_file_path(args)
        {"Exploring directory tree for #{Path.basename(path || ".")}", []}

      "create_directory" ->
        path = extract_file_path(args)
        {"Creating directory #{Path.basename(path || "directory")}", []}

      # Search operations
      "search_files" ->
        pattern = Map.get(args, "pattern", "files")
        {"Searching for #{pattern}", []}

      "grep_search" ->
        query = Map.get(args, "query", "text")
        {"Searching for '#{query}' in files", []}

      "semantic_search" ->
        query = Map.get(args, "query", "content")
        {"Semantic search for '#{query}'", []}

      # Thinking operations
      "sequentialthinking" ->
        thought = Map.get(args, "thought", "")
        thought_summary = String.slice(thought, 0, 50) |> String.trim()
        {"Sequential thinking: #{thought_summary}...", []}

      # Terminal operations
      "run_in_terminal" ->
        command = Map.get(args, "command", "command")
        command_summary = String.slice(command, 0, 30) |> String.trim()
        {"Running: #{command_summary}...", []}

      "get_terminal_output" ->
        {"Checking terminal output", []}

      # Test operations
      "runTests" ->
        files = Map.get(args, "files", [])
        if files != [] do
          file_names = Enum.map(files, &Path.basename/1)
          {"Running tests in #{Enum.join(file_names, ", ")}", files}
        else
          {"Running all tests", []}
        end

      # Task management
      "create_task" ->
        title = Map.get(args, "title", "task")
        {"Creating task: #{title}", []}

      "get_next_task" ->
        {"Getting next task", []}

      "complete_task" ->
        {"Completing current task", []}

      # Knowledge operations
      "create_entities" ->
        entities = Map.get(args, "entities", [])
        count = length(entities)
        {"Creating #{count} knowledge entities", []}

      "create_relations" ->
        relations = Map.get(args, "relations", [])
        count = length(relations)
        {"Creating #{count} knowledge relations", []}

      "search_nodes" ->
        query = Map.get(args, "query", "nodes")
        {"Searching knowledge graph for '#{query}'", []}

      "read_graph" ->
        {"Reading knowledge graph", []}

      # HTTP/Web operations
      "fetch_webpage" ->
        urls = Map.get(args, "urls", [])
        if urls != [] do
          {"Fetching #{length(urls)} webpages", []}
        else
          {"Fetching webpage", []}
        end

      # Development operations
      "get_errors" ->
        files = Map.get(args, "filePaths", [])
        if files != [] do
          file_names = Enum.map(files, &Path.basename/1)
          {"Checking errors in #{Enum.join(file_names, ", ")}", files}
        else
          {"Checking all errors", []}
        end

      "list_code_usages" ->
        symbol = Map.get(args, "symbolName", "symbol")
        {"Finding usages of #{symbol}", []}

      # Elixir-specific operations
      "elixir-definition" ->
        symbol = Map.get(args, "symbol", "symbol")
        {"Finding definition of #{symbol}", []}

      "elixir-docs" ->
        modules = Map.get(args, "modules", [])
        if modules != [] do
          {"Getting docs for #{Enum.join(modules, ", ")}", []}
        else
          {"Getting Elixir documentation", []}
        end

      "elixir-environment" ->
        location = Map.get(args, "location", "code")
        {"Analyzing Elixir environment at #{location}", []}

      # Python operations  
      "pylanceRunCodeSnippet" ->
        {"Running Python code snippet", []}

      "pylanceFileSyntaxErrors" ->
        file_uri = Map.get(args, "fileUri")
        if file_uri do
          file_path = uri_to_path(file_uri)
          {"Checking syntax errors in #{Path.basename(file_path)}", [file_path]}
        else
          {"Checking Python syntax errors", []}
        end

      # Default cases
      tool_name when is_binary(tool_name) ->
        cond do
          String.starts_with?(tool_name, "vscode_") ->
            action = String.replace(tool_name, "vscode_", "") |> String.replace("_", " ")
            {"VS Code: #{action}", []}

          String.starts_with?(tool_name, "elixir-") ->
            action = String.replace(tool_name, "elixir-", "") |> String.replace("-", " ")
            {"Elixir: #{action}", []}

          String.starts_with?(tool_name, "pylance") ->
            action = String.replace(tool_name, "pylance", "") |> humanize_string()
            {"Python: #{action}", []}

          String.contains?(tool_name, "_") ->
            action = String.replace(tool_name, "_", " ") |> String.capitalize()
            {action, []}

          true ->
            {String.capitalize(tool_name), []}
        end

      _ ->
        {"Unknown activity", []}
    end
  end

  @doc """
  Update an agent's activity based on a tool call.
  """
  def update_agent_activity(agent_id, tool_name, args) do
    {activity, files} = infer_activity(tool_name, args)
    
    case TaskRegistry.get_agent(agent_id) do
      {:ok, agent} ->
        updated_agent = Agent.update_activity(agent, activity, files)
        # Update the agent in the registry
        TaskRegistry.update_agent(agent_id, updated_agent)

      {:error, _} ->
        # Agent not found, ignore
        :ok
    end
  end

  @doc """
  Clear an agent's activity (e.g., when they go idle).
  """
  def clear_agent_activity(agent_id) do
    case TaskRegistry.get_agent(agent_id) do
      {:ok, agent} ->
        updated_agent = Agent.clear_activity(agent)
        TaskRegistry.update_agent(agent_id, updated_agent)

      {:error, _} ->
        :ok
    end
  end

  # Private helper functions

  defp extract_file_path(args) do
    # Try various common parameter names for file paths
    args["path"] || args["filePath"] || args["file_path"] || 
    args["source"] || args["destination"] || args["fileUri"] |> uri_to_path()
  end

  defp uri_to_path(nil), do: nil
  defp uri_to_path(uri) when is_binary(uri) do
    if String.starts_with?(uri, "file://") do
      String.replace_prefix(uri, "file://", "")
    else
      uri
    end
  end

  defp humanize_string(str) do
    str
    |> String.split(~r/[A-Z]/)
    |> Enum.map(&String.downcase/1)
    |> Enum.filter(&(&1 != ""))
    |> Enum.join(" ")
    |> String.capitalize()
  end
end