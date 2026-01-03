defmodule SquadsWeb.API.SquadConnectionJSON do
  alias Squads.Squads.SquadConnection

  @doc """
  Renders a list of squad connections.
  """
  def index(%{connections: connections}) do
    %{data: for(connection <- connections, do: data(connection))}
  end

  @doc """
  Renders a single squad connection.
  """
  def show(%{connection: connection}) do
    %{data: data(connection)}
  end

  defp data(%SquadConnection{} = connection) do
    %{
      id: connection.id,
      from_squad_id: connection.from_squad_id,
      to_squad_id: connection.to_squad_id,
      status: connection.status,
      metadata: connection.metadata,
      notes: connection.notes,
      inserted_at: connection.inserted_at,
      updated_at: connection.updated_at,
      from_squad:
        if(Ecto.assoc_loaded?(connection.from_squad),
          do: squad_data(connection.from_squad),
          else: nil
        ),
      to_squad:
        if(Ecto.assoc_loaded?(connection.to_squad),
          do: squad_data(connection.to_squad),
          else: nil
        )
    }
  end

  defp squad_data(squad) do
    %{
      id: squad.id,
      name: squad.name,
      project_id: squad.project_id
    }
  end
end
