defmodule AgentCoordinator.CodebaseIdentifier do
  @moduledoc """
  Smart codebase identification system that works across local and remote scenarios.

  Generates canonical codebase identifiers using multiple strategies:
  1. Git repository detection (preferred)
  2. Local folder name fallback
  3. Remote workspace mapping
  4. Custom identifier override
  """

  require Logger

  @type codebase_info :: %{
    canonical_id: String.t(),
    display_name: String.t(),
    workspace_path: String.t(),
    repository_url: String.t() | nil,
    git_remote: String.t() | nil,
    branch: String.t() | nil,
    commit_hash: String.t() | nil,
    identification_method: :git_remote | :git_local | :folder_name | :custom
  }

  @doc """
  Identify a codebase from a workspace path, generating a canonical ID.

  Priority order:
  1. Git remote URL (most reliable for distributed teams)
  2. Git local repository info
  3. Folder name (fallback for non-git projects)
  4. Custom override from metadata

  ## Examples

      # Git repository with remote
      iex> identify_codebase("/home/user/my-project")
      %{
        canonical_id: "github.com/owner/my-project",
        display_name: "my-project",
        workspace_path: "/home/user/my-project",
        repository_url: "https://github.com/owner/my-project.git",
        git_remote: "origin",
        branch: "main",
        identification_method: :git_remote
      }

      # Local folder (no git)
      iex> identify_codebase("/home/user/local-project")
      %{
        canonical_id: "local:/home/user/local-project",
        display_name: "local-project",
        workspace_path: "/home/user/local-project",
        repository_url: nil,
        identification_method: :folder_name
      }
  """
  def identify_codebase(workspace_path, opts \\ [])
  def identify_codebase(nil, opts) do
    custom_id = Keyword.get(opts, :custom_id, "default")
    build_custom_codebase_info(nil, custom_id)
  end
  
  def identify_codebase(workspace_path, opts) do
    custom_id = Keyword.get(opts, :custom_id)

    cond do
      custom_id ->
        build_custom_codebase_info(workspace_path, custom_id)

      git_repository?(workspace_path) ->
        identify_git_codebase(workspace_path)

      true ->
        identify_folder_codebase(workspace_path)
    end
  end

  @doc """
  Normalize different codebase references to canonical IDs.
  Handles cases where agents specify different local paths for same repository.
  """
  def normalize_codebase_reference(codebase_ref, workspace_path) do
    case codebase_ref do
      # Already canonical
      id when is_binary(id) ->
        if String.contains?(id, ".com/") or String.starts_with?(id, "local:") do
          id
        else
          # Folder name - try to resolve to canonical
          case identify_codebase(workspace_path) do
            %{canonical_id: canonical_id} -> canonical_id
            _ -> "local:#{id}"
          end
        end

      _ ->
        # Fallback to folder-based ID
        Path.basename(workspace_path || "/unknown")
    end
  end

  @doc """
  Check if two workspace paths refer to the same codebase.
  Useful for detecting when agents from different machines work on same project.
  """
  def same_codebase?(workspace_path1, workspace_path2) do
    info1 = identify_codebase(workspace_path1)
    info2 = identify_codebase(workspace_path2)

    info1.canonical_id == info2.canonical_id
  end

  # Private functions

  defp build_custom_codebase_info(workspace_path, custom_id) do
    %{
      canonical_id: custom_id,
      display_name: custom_id,
      workspace_path: workspace_path,
      repository_url: nil,
      git_remote: nil,
      branch: nil,
      commit_hash: nil,
      identification_method: :custom
    }
  end

  defp identify_git_codebase(workspace_path) do
    with {:ok, git_info} <- get_git_info(workspace_path) do
      canonical_id = case git_info.remote_url do
        nil ->
          # Local git repo without remote
          "git-local:#{git_info.repo_name}"

        remote_url ->
          # Extract canonical identifier from remote URL
          extract_canonical_from_remote(remote_url)
      end

      %{
        canonical_id: canonical_id,
        display_name: git_info.repo_name,
        workspace_path: workspace_path,
        repository_url: git_info.remote_url,
        git_remote: git_info.remote_name,
        branch: git_info.branch,
        commit_hash: git_info.commit_hash,
        identification_method: if(git_info.remote_url, do: :git_remote, else: :git_local)
      }
    else
      _ ->
        identify_folder_codebase(workspace_path)
    end
  end

  defp identify_folder_codebase(workspace_path) when is_nil(workspace_path) do
    %{
      canonical_id: "default",
      display_name: "default",
      workspace_path: nil,
      repository_url: nil,
      git_remote: nil,
      branch: nil,
      commit_hash: nil,
      identification_method: :folder_name
    }
  end
  
  defp identify_folder_codebase(workspace_path) do
    folder_name = Path.basename(workspace_path)

    %{
      canonical_id: "local:#{workspace_path}",
      display_name: folder_name,
      workspace_path: workspace_path,
      repository_url: nil,
      git_remote: nil,
      branch: nil,
      commit_hash: nil,
      identification_method: :folder_name
    }
  end

  defp git_repository?(workspace_path) when is_nil(workspace_path), do: false
  defp git_repository?(workspace_path) do
    File.exists?(Path.join(workspace_path, ".git"))
  end

  defp get_git_info(workspace_path) do
    try do
      # Get repository name
      repo_name = Path.basename(workspace_path)

      # Get current branch
      {branch, 0} = System.cmd("git", ["branch", "--show-current"], cd: workspace_path)
      branch = String.trim(branch)

      # Get current commit
      {commit_hash, 0} = System.cmd("git", ["rev-parse", "HEAD"], cd: workspace_path)
      commit_hash = String.trim(commit_hash)

      # Try to get remote URL
      {remote_info, _remote_result_use_me?} = case System.cmd("git", ["remote", "-v"], cd: workspace_path) do
        {output, 0} when output != "" ->
          # Parse remote output to extract origin URL
          lines = String.split(String.trim(output), "\n")
          origin_line = Enum.find(lines, fn line ->
            String.starts_with?(line, "origin") and String.contains?(line, "(fetch)")
          end)

          case origin_line do
            nil -> {nil, :no_origin}
            line ->
              # Extract URL from "origin <url> (fetch)"
              url = line
                    |> String.split()
                    |> Enum.at(1)
              {url, :ok}
          end

        _ -> {nil, :no_remotes}
      end

      git_info = %{
        repo_name: repo_name,
        branch: branch,
        commit_hash: commit_hash,
        remote_url: remote_info,
        remote_name: if(remote_info, do: "origin", else: nil)
      }

      {:ok, git_info}
    rescue
      _ -> {:error, :git_command_failed}
    end
  end

  defp extract_canonical_from_remote(remote_url) do
    cond do
      # GitHub HTTPS
      String.contains?(remote_url, "github.com") ->
        extract_github_id(remote_url)

      # GitLab HTTPS
      String.contains?(remote_url, "gitlab.com") ->
        extract_gitlab_id(remote_url)

      # SSH format
      String.contains?(remote_url, "@") and String.contains?(remote_url, ":") ->
        extract_ssh_id(remote_url)

      # Other HTTPS
      String.starts_with?(remote_url, "https://") ->
        extract_https_id(remote_url)

      true ->
        # Fallback - use raw URL
        "remote:#{remote_url}"
    end
  end

  defp extract_github_id(url) do
    # Extract "owner/repo" from various GitHub URL formats
    regex = ~r/github\.com[\/:]([^\/]+)\/([^\/\.]+)/

    case Regex.run(regex, url) do
      [_, owner, repo] ->
        "github.com/#{owner}/#{repo}"
      _ ->
        "github.com/unknown"
    end
  end

  defp extract_gitlab_id(url) do
    # Similar logic for GitLab
    regex = ~r/gitlab\.com[\/:]([^\/]+)\/([^\/\.]+)/

    case Regex.run(regex, url) do
      [_, owner, repo] ->
        "gitlab.com/#{owner}/#{repo}"
      _ ->
        "gitlab.com/unknown"
    end
  end

  defp extract_ssh_id(url) do
    # SSH format: git@host:owner/repo.git
    case String.split(url, ":") do
      [host_part, path_part] ->
        host = String.replace(host_part, ~r/.*@/, "")
        path = String.replace(path_part, ".git", "")
        "#{host}/#{path}"

      _ ->
        "ssh:#{url}"
    end
  end

  defp extract_https_id(url) do
    # Extract from general HTTPS URLs
    uri = URI.parse(url)
    host = uri.host
    path = String.replace(uri.path || "", ~r/^\//, "")
    path = String.replace(path, ".git", "")

    if host && path != "" do
      "#{host}/#{path}"
    else
      "https:#{url}"
    end
  end
end
