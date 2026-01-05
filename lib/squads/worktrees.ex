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
    with %Project{} = project <- Repo.get(Project, project_id),
         %Agent{} = agent <- Repo.get(Agent, agent_id),
         %Ticket{} = ticket <- Repo.get(Ticket, ticket_id) do
      worktree_name = "#{agent.slug}-#{ticket.id}"
      worktree_path = Path.join([project.path, ".squads", "worktrees", worktree_name])
      branch_name = "squads/#{worktree_name}"

      if File.exists?(worktree_path) do
        {:ok, worktree_path}
      else
        create_worktree(project.path, branch_name, worktree_path)
      end
    else
      nil -> {:error, :not_found}
    end
  end

  defp create_worktree(repo_path, branch, path) do
    # Ensure parent dir exists
    File.mkdir_p!(Path.dirname(path))

    # Detect default branch (main or master)
    base_branch = detect_default_branch(repo_path)

    case run_git(["worktree", "add", "-b", branch, path, base_branch], repo_path) do
      {:ok, _} ->
        {:ok, path}

      {:error, output} ->
        # If branch already exists, try adding without -b
        if String.contains?(output, "already exists") do
          case run_git(["worktree", "add", path, branch], repo_path) do
            {:ok, _} -> {:ok, path}
            {:error, err} -> {:error, err}
          end
        else
          {:error, output}
        end
    end
  end

  defp run_git(args, cd, timeout \\ 30_000) do
    # For now, we use a simple timeout on System.cmd by wrapping it in a Task
    # In the future, we might use a dedicated CommandRunner behaviour.
    task =
      Task.async(fn ->
        System.cmd("git", args, cd: cd, stderr_to_stdout: true)
      end)

    case Task.yield(task, timeout) || Task.shutdown(task) do
      {:ok, {output, 0}} ->
        {:ok, output}

      {:ok, {output, _exit_code}} ->
        {:error, output}

      {:exit, reason} ->
        {:error, "Git command exited unexpectedly: #{inspect(reason)}"}

      nil ->
        {:error, "Git command timed out after #{timeout}ms"}
    end
  end

  defp detect_default_branch(repo_path) do
    case run_git(["symbolic-ref", "refs/remotes/origin/HEAD"], repo_path) do
      {:ok, output} ->
        output |> String.trim() |> Path.basename()

      _ ->
        case run_git(["branch", "--list", "main", "master"], repo_path) do
          {:ok, output} ->
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
    case Repo.get(Project, project_id) do
      nil ->
        {:error, :not_found}

      project ->
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
  end

  defp get_diff_summary(path) do
    case run_git(["diff", "--stat", "HEAD"], path) do
      {:ok, output} -> {:ok, output}
      {:error, err} -> {:error, err}
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
    case Repo.get(Project, project_id) do
      nil ->
        {:error, :not_found}

      project ->
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
  end

  @doc """
  Removes a worktree and its associated branch.
  """
  def remove_worktree(project_id, name) do
    case Repo.get(Project, project_id) do
      nil ->
        {:error, :not_found}

      project ->
        path = Path.join([project.path, ".squads", "worktrees", name]) |> Path.expand()
        branch = "squads/#{name}"

        # Ensure we are not in the worktree directory if we're calling this from somewhere else
        # but System.cmd cd should handle it.

        # Check if worktree exists in git list
        case run_git(["worktree", "list", "--porcelain"], project.path) do
          {:ok, output} ->
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
              with {:ok, _} <-
                     run_git(["worktree", "remove", "--force", path], project.path),
                   {:ok, _} <- run_git(["branch", "-D", branch], project.path) do
                {:ok, :removed}
              end
            else
              # Just try to remove branch if it exists
              run_git(["branch", "-D", branch], project.path)
              {:ok, :removed}
            end

          {:error, err} ->
            {:error, err}
        end
    end
  end

  @doc """
  Merges the worktree branch into the base branch and cleans up.
  """
  def merge_and_cleanup(project_id, name, opts \\ []) do
    case Repo.get(Project, project_id) do
      nil ->
        {:error, :not_found}

      project ->
        branch = "squads/#{name}"
        base_branch = detect_default_branch(project.path)
        strategy = Keyword.get(opts, :strategy, :merge)

        with {:ok, _} <- run_git(["checkout", base_branch], project.path),
             {:ok, _} <- perform_merge(project.path, branch, strategy),
             {:ok, _} <- remove_worktree(project_id, name) do
          {:ok, :merged_and_cleaned}
        end
    end
  end

  defp perform_merge(repo_path, branch, :merge) do
    case run_git(["merge", branch, "--no-edit"], repo_path) do
      {:ok, _} -> {:ok, :merged}
      {:error, err} -> {:error, err}
    end
  end

  defp perform_merge(repo_path, branch, :squash) do
    with {:ok, _} <- run_git(["merge", "--squash", branch], repo_path),
         {:ok, _} <- run_git(["commit", "-m", "Merge #{branch} (squash)"], repo_path) do
      {:ok, :merged}
    end
  end
end
