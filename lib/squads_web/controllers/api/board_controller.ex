defmodule SquadsWeb.API.BoardController do
  use SquadsWeb, :controller

  def index(conn, _params) do
    # Fallback/Global board functionality is tricky without a project context for Beads.
    # We might want to remove this or make it just return an empty list if no project is active.
    # For now, let's return an empty list to avoid 500 errors when no project is selected.
    json(conn, %{data: []})
  end

  def show(conn, %{"id" => _id}) do
    # Similarly, showing a specific ticket without project context is difficult with the current Adapter.
    conn
    |> put_status(:not_found)
    |> json(%{error: "Ticket not found", detail: "Global ticket lookup not supported"})
  end
end
