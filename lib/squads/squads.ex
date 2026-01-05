defmodule Squads.Squads do
  @moduledoc """
  Context module for managing squads.
  """

  import Ecto.Query, warn: false

  alias Squads.Repo
  alias Squads.Squads.Squad
  alias Squads.Squads.SquadConnection
  alias Squads.Events
  alias Squads.OpenCode.Status
  alias Squads.Projects

  @doc """
  Lists all squads for a project.
  """
  @spec list_squads_for_project(Ecto.UUID.t()) :: [Squad.t()]
  def list_squads_for_project(project_id) do
    Squad
    |> where([s], s.project_id == ^project_id)
    |> Repo.all()
    |> Repo.preload(:project)
    |> Enum.map(&populate_opencode_status/1)
  end

  @doc """
  Gets a squad by ID.
  """
  @spec get_squad(Ecto.UUID.t()) :: Squad.t() | nil
  def get_squad(id) do
    Squad
    |> Repo.get(id)
    |> Repo.preload(:project)
    |> populate_opencode_status()
  end

  defp populate_opencode_status(nil), do: nil

  defp populate_opencode_status(%Squad{project: %Squads.Projects.Project{path: path}} = squad) do
    status = Status.get(path)
    %{squad | opencode_status: status}
  end

  defp populate_opencode_status(%Squad{} = squad) do
    squad = Repo.preload(squad, :project)
    populate_opencode_status(squad)
  end

  @doc """
  Fetches a squad by ID with a tuple result.
  """
  @spec fetch_squad(Ecto.UUID.t()) :: {:ok, Squad.t()} | {:error, :not_found}
  def fetch_squad(id) do
    case get_squad(id) do
      nil -> {:error, :not_found}
      squad -> {:ok, squad}
    end
  end

  @doc """
  Lists all squads for a project with agents preloaded.
  """
  def list_squads_with_agents(project_id) do
    list_squads_for_project(project_id) |> Repo.preload([:agents, :project])
  end

  @doc """
  Gets a squad by ID with agents preloaded.
  """
  def get_squad_with_agents(id) do
    case get_squad(id) do
      nil -> nil
      squad -> Repo.preload(squad, [:agents, :project])
    end
  end

  @doc """
  Creates a squad.
  """
  @spec create_squad(map()) :: {:ok, Squad.t()} | {:error, Ecto.Changeset.t()}
  def create_squad(attrs) do
    %Squad{}
    |> Squad.changeset(attrs)
    |> Repo.insert()
    |> case do
      {:ok, squad} = result ->
        maybe_set_provisioning_status(squad.project_id)
        result

      error ->
        error
    end
  end

  defp maybe_set_provisioning_status(project_id) do
    case Projects.get_project(project_id) do
      %Projects.Project{path: path} ->
        case Status.fetch(path) do
          :error -> Status.set(path, :provisioning)
          {:ok, _status} -> :ok
        end

      _ ->
        :ok
    end
  end

  @doc """
  Updates a squad.
  """
  @spec update_squad(Squad.t(), map()) :: {:ok, Squad.t()} | {:error, Ecto.Changeset.t()}
  def update_squad(%Squad{} = squad, attrs) do
    squad
    |> Squad.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a squad.
  """
  @spec delete_squad(Squad.t()) :: {:ok, Squad.t()} | {:error, Ecto.Changeset.t()}
  def delete_squad(%Squad{} = squad) do
    Repo.delete(squad)
  end

  # Squad Connections

  @doc """
  Lists connections for a given squad.
  """
  @spec list_connections_for_squad(Ecto.UUID.t()) :: [SquadConnection.t()]
  def list_connections_for_squad(squad_id) do
    SquadConnection
    |> where([c], c.from_squad_id == ^squad_id or c.to_squad_id == ^squad_id)
    |> Repo.all()
    |> Repo.preload(from_squad: :project, to_squad: :project)
  end

  @doc """
  Lists connections for a project (connections where at least one squad belongs to the project).
  """
  @spec list_connections_for_project(Ecto.UUID.t()) :: [SquadConnection.t()]
  def list_connections_for_project(project_id) do
    squad_ids =
      Squad
      |> select([s], s.id)
      |> where([s], s.project_id == ^project_id)

    SquadConnection
    |> where([c], c.from_squad_id in subquery(squad_ids) or c.to_squad_id in subquery(squad_ids))
    |> Repo.all()
    |> Repo.preload(from_squad: :project, to_squad: :project)
  end

  @doc """
  Creates a connection between two squads.
  """
  @spec create_connection(map()) :: {:ok, SquadConnection.t()} | {:error, Ecto.Changeset.t()}
  def create_connection(attrs) do
    result =
      %SquadConnection{}
      |> SquadConnection.changeset(attrs)
      |> Repo.insert()

    case result do
      {:ok, connection} ->
        # Load squads to get project IDs for events
        connection = Repo.preload(connection, from_squad: :project, to_squad: :project)

        # Emit events for both squads' projects
        if connection.from_squad do
          Events.create_event(%{
            kind: "squad.connected",
            project_id: connection.from_squad.project_id,
            payload: %{
              connection_id: connection.id,
              from_squad_id: connection.from_squad_id,
              to_squad_id: connection.to_squad_id,
              status: connection.status
            }
          })
        end

        if connection.to_squad &&
             connection.to_squad.project_id != connection.from_squad.project_id do
          Events.create_event(%{
            kind: "squad.connected",
            project_id: connection.to_squad.project_id,
            payload: %{
              connection_id: connection.id,
              from_squad_id: connection.from_squad_id,
              to_squad_id: connection.to_squad_id,
              status: connection.status
            }
          })
        end

        {:ok, connection}

      error ->
        error
    end
  end

  @doc """
  Gets a squad connection by ID.
  """
  @spec get_connection(Ecto.UUID.t()) :: SquadConnection.t() | nil
  def get_connection(id) do
    Repo.get(SquadConnection, id)
  end

  @doc """
  Updates a squad connection.
  """
  @spec update_connection(SquadConnection.t(), map()) ::
          {:ok, SquadConnection.t()} | {:error, Ecto.Changeset.t()}
  def update_connection(%SquadConnection{} = connection, attrs) do
    connection
    |> SquadConnection.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a squad connection.
  """
  @spec delete_connection(SquadConnection.t()) ::
          {:ok, SquadConnection.t()} | {:error, Ecto.Changeset.t()}
  def delete_connection(%SquadConnection{} = connection) do
    connection = Repo.preload(connection, [:from_squad, :to_squad])

    result = Repo.delete(connection)

    case result do
      {:ok, _deleted} ->
        # Emit events for both squads' projects
        if connection.from_squad do
          Events.create_event(%{
            kind: "squad.disconnected",
            project_id: connection.from_squad.project_id,
            payload: %{
              connection_id: connection.id,
              from_squad_id: connection.from_squad_id,
              to_squad_id: connection.to_squad_id
            }
          })
        end

        if connection.to_squad &&
             connection.to_squad.project_id != connection.from_squad.project_id do
          Events.create_event(%{
            kind: "squad.disconnected",
            project_id: connection.to_squad.project_id,
            payload: %{
              connection_id: connection.id,
              from_squad_id: connection.from_squad_id,
              to_squad_id: connection.to_squad_id
            }
          })
        end

        result

      error ->
        error
    end
  end
end
