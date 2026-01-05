defmodule SquadsWeb.API.WorktreeController do
  use SquadsWeb, :controller

  alias Squads.Worktrees

  action_fallback SquadsWeb.FallbackController

  def index(conn, %{"project_id" => project_id}) do
    with {:ok, uuid} <- Ecto.UUID.cast(project_id),
         worktrees when is_list(worktrees) <- Worktrees.list_worktrees(uuid) do
      render(conn, :index, worktrees: worktrees)
    end
  end

  def create(conn, %{"project_id" => project_id, "agent_id" => agent_id, "ticket_id" => ticket_id}) do
    with {:ok, path} <- Worktrees.ensure_worktree(project_id, agent_id, ticket_id) do
      conn
      |> put_status(:created)
      |> render(:show, path: path)
    end
  end

  def delete(conn, %{"project_id" => project_id, "id" => name}) do
    with {:ok, :removed} <- Worktrees.remove_worktree(project_id, name) do
      send_resp(conn, :no_content, "")
    end
  end
end
