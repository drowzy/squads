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
    path = Path.join([project.path, ".squads", "worktrees", name])
    branch = "squads/#{name}"

    with {_, 0} <- System.cmd("git", ["worktree", "remove", "--force", path], cd: project.path),
         {_, 0} <- System.cmd("git", ["branch", "-D", branch], cd: project.path) do
      {:ok, :removed}
    else
      {err, _} -> {:error, err}
    end
  end
end
