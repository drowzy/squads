defmodule SquadsWeb.API.BoardController do
  use SquadsWeb, :controller

  alias Squads.Beads.Adapter

  def index(conn, _params) do
    case Adapter.list_issues() do
      {:ok, tickets} ->
        json(conn, %{data: tickets})

      {:error, detail} ->
        conn
        |> put_status(:internal_server_error)
        |> json(%{error: "Failed to list tickets", detail: detail})
    end
  end

  def show(conn, %{"id" => id}) do
    case Adapter.show_issue(id) do
      {:ok, ticket} ->
        json(conn, %{data: ticket})

      {:error, detail} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Ticket not found", detail: detail})
    end
  end
end
