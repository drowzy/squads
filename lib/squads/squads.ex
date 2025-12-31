defmodule Squads.Squads do
  @moduledoc """
  Context module for managing squads.
  """

  import Ecto.Query, warn: false

  alias Squads.Repo
  alias Squads.Squads.Squad

  @doc """
  Lists all squads for a project.
  """
  @spec list_squads_for_project(Ecto.UUID.t()) :: [Squad.t()]
  def list_squads_for_project(project_id) do
    Squad
    |> where([s], s.project_id == ^project_id)
    |> Repo.all()
  end

  @doc """
  Gets a squad by ID.
  """
  @spec get_squad(Ecto.UUID.t()) :: Squad.t() | nil
  def get_squad(id) do
    Repo.get(Squad, id)
  end

  @doc """
  Gets a squad by ID, raising if not found.
  """
  @spec get_squad!(Ecto.UUID.t()) :: Squad.t()
  def get_squad!(id) do
    Repo.get!(Squad, id)
  end

  @doc """
  Lists all squads for a project with agents preloaded.
  """
  def list_squads_with_agents(project_id) do
    list_squads_for_project(project_id) |> Repo.preload(:agents)
  end

  @doc """
  Gets a squad by ID with agents preloaded.
  """
  def get_squad_with_agents(id) do
    case get_squad(id) do
      nil -> nil
      squad -> Repo.preload(squad, :agents)
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
end
