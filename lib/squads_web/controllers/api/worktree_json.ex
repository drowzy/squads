defmodule SquadsWeb.API.WorktreeJSON do
  def index(%{worktrees: worktrees}) do
    %{data: for(w <- worktrees, do: data(w))}
  end

  def show(%{path: path}) do
    %{data: %{path: path}}
  end

  defp data(worktree) do
    %{
      name: worktree.name,
      path: worktree.path
    }
  end
end
