defmodule SquadsWeb.API.SquadConnectionController do
  use SquadsWeb, :controller

  alias Squads.Squads
  alias Squads.Squads.SquadConnection

  action_fallback SquadsWeb.FallbackController

  def index(conn, %{"squad_id" => squad_id}) do
    connections = Squads.list_connections_for_squad(squad_id)
    render(conn, :index, connections: connections)
  end

  def index(conn, %{"project_id" => project_id}) do
    connections = Squads.list_connections_for_project(project_id)
    render(conn, :index, connections: connections)
  end

  def create(conn, %{"squad_connection" => connection_params}) do
    # Remove pattern match on %SquadConnection{} struct
    with {:ok, connection} <- Squads.create_connection(connection_params) do
      conn
      |> put_status(:created)
      |> render(:show, connection: connection)
    end
  end

  def delete(conn, %{"id" => id}) do
    # Remove pattern match on %SquadConnection{} struct
    with connection when not is_nil(connection) <- Squads.get_connection(id),
         {:ok, _deleted} <- Squads.delete_connection(connection) do
      send_resp(conn, :no_content, "")
    else
      nil -> {:error, :not_found}
      error -> error
    end
  end
end
