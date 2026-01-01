defmodule Squads.Worktrees do
  @moduledoc """
  Manages git worktrees for agents working on specific tickets.
  """
  alias Squads.Repo
  alias Squads.Projects.Project
  alias Squads.Agents.Agent
  alias Squads.Tickets.Ticket

  @doc """
  Ensures a worktree exists for the given agent and ticket.
  Path format: <project_path>/.squads/worktrees/<agent_slug>-<ticket_id>
  """
  def ensure_worktree(project_id, agent_id, ticket_id) do
    project = Repo.get!(Project, project_id)
    agent = Repo.get!(Agent, agent_id)
    ticket = Repo.get!(Ticket, ticket_id)

    worktree_name = "#{agent.slug}-#{ticket.id}"
    worktree_path = Path.join([project.path, ".squads", "worktrees", worktree_name])
    branch_name = "squads/#{worktree_name}"

    if File.exists?(worktree_path) do
      {:ok, worktree_path}
    else
      create_worktree(project.path, branch_name, worktree_path)
    end
  end

  defp create_worktree(repo_path, branch, path) do
    # Ensure parent dir exists
    File.mkdir_p!(Path.dirname(path))

    # Detect default branch (main or master)
    base_branch = detect_default_branch(repo_path)

    case System.cmd("git", ["worktree", "add", "-b", branch, path, base_branch], cd: repo_path) do
      {_, 0} ->
        {:ok, path}

      {output, _} ->
        # If branch already exists, try adding without -b
        if String.contains?(output, "already exists") do
          case System.cmd("git", ["worktree", "add", path, branch], cd: repo_path) do
            {_, 0} -> {:ok, path}
            {err, _} -> {:error, err}
          end
        else
          {:error, output}
        end
    end
  end

  defp detect_default_branch(repo_path) do
    case System.cmd("git", ["symbolic-ref", "refs/remotes/origin/HEAD"], cd: repo_path) do
      {output, 0} ->
        output |> String.trim() |> Path.basename()

      _ ->
        case System.cmd("git", ["branch", "--list", "main", "master"], cd: repo_path) do
          {output, 0} ->
            cond do
              String.contains?(output, "main") -> "main"
              String.contains?(output, "master") -> "master"
              true -> "main"
            end

          _ ->
            "main"
        end
    end
  end

  @doc """
  Generates a PR summary artifact for a worktree.
  Includes a summary of changes (diffstat) and any recent test results.
  """
  def generate_pr_summary(project_id, name) do
    project = Repo.get!(Project, project_id)
    path = Path.join([project.path, ".squads", "worktrees", name])

    if File.exists?(path) do
      with {:ok, diff} <- get_diff_summary(path),
           {:ok, tests} <- get_test_summary(path) do
        {:ok,
         %{
           summary: diff,
           test_results: tests,
           generated_at: DateTime.utc_now()
         }}
      end
    else
      {:error, :not_found}
    end
  end

  defp get_diff_summary(path) do
    case System.cmd("git", ["diff", "--stat", "HEAD"], cd: path) do
      {output, 0} -> {:ok, output}
      {err, _} -> {:error, err}
    end
  end

  defp get_test_summary(path) do
    # Try to find a test log or run a quick test check if feasible.
    # For now, we'll look for common patterns or just return "No test data"
    # In a real scenario, we might look for .squads/test_results.json
    log_path = Path.join(path, ".squads/test_results.log")

    if File.exists?(log_path) do
      {:ok, File.read!(log_path)}
    else
      {:ok, "No recent test logs found."}
    end
  end

  @doc """
  Lists all worktrees for a project by scanning the .squads/worktrees directory.
  """
  def list_worktrees(project_id) do
    project = Repo.get!(Project, project_id)
    base_path = Path.join([project.path, ".squads", "worktrees"])

    if File.exists?(base_path) do
      File.ls!(base_path)
      |> Enum.map(fn name ->
        %{
          name: name,
          path: Path.join(base_path, name)
        }
      end)
    else
      []
    end
  end

  @doc """
  Removes a worktree and its associated branch.
  """
  def remove_worktree(project_id, name) do
    project = Repo.get!(Project, project_id)
    path = Path.join([project.path, ".squads", "worktrees", name]) |> Path.expand()
    branch = "squads/#{name}"

    # Ensure we are not in the worktree directory if we're calling this from somewhere else
    # but System.cmd cd should handle it.

    # Check if worktree exists in git list
    case System.cmd("git", ["worktree", "list", "--porcelain"], cd: project.path) do
      {output, 0} ->
        # Normalize paths in output to handle symlinks (like /var vs /private/var on macOS)
        worktrees =
          output
          |> String.split("\n", trim: true)
          |> Enum.filter(&String.starts_with?(&1, "worktree "))
          |> Enum.map(fn line ->
            line |> String.replace("worktree ", "") |> Path.expand()
          end)

        path = Path.expand(path)

        # Check for both the normalized path and the possible /private prefix
        if path in worktrees or Path.join("/private", path) in worktrees do
          with {_, 0} <-
                 System.cmd("git", ["worktree", "remove", "--force", path], cd: project.path),
               {_, 0} <- System.cmd("git", ["branch", "-D", branch], cd: project.path) do
            {:ok, :removed}
          else
            {err, _} -> {:error, err}
          end
        else
          # Just try to remove branch if it exists
          System.cmd("git", ["branch", "-D", branch], cd: project.path)
          {:ok, :removed}
        end

      {err, _} ->
        {:error, err}
    end
  end

  @doc """
  Merges the worktree branch into the base branch and cleans up.
  """
  def merge_and_cleanup(project_id, name, opts \\ []) do
    project = Repo.get!(Project, project_id)
    branch = "squads/#{name}"
    base_branch = detect_default_branch(project.path)
    strategy = Keyword.get(opts, :strategy, :merge)

    with {_, 0} <- System.cmd("git", ["checkout", base_branch], cd: project.path),
         {:ok, _} <- perform_merge(project.path, branch, strategy),
         {:ok, _} <- remove_worktree(project_id, name) do
      {:ok, :merged_and_cleaned}
    else
      {:error, reason} -> {:error, reason}
      {err, _} -> {:error, err}
    end
  end

  defp perform_merge(repo_path, branch, :merge) do
    case System.cmd("git", ["merge", branch, "--no-edit"], cd: repo_path) do
      {_, 0} -> {:ok, :merged}
      {err, _} -> {:error, err}
    end
  end

  defp perform_merge(repo_path, branch, :squash) do
    with {_, 0} <- System.cmd("git", ["merge", "--squash", branch], cd: repo_path),
         {_, 0} <- System.cmd("git", ["commit", "-m", "Merge #{branch} (squash)"], cd: repo_path) do
      {:ok, :merged}
    else
      {err, _} -> {:error, err}
    end
  end
end
