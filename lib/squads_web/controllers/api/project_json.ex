defmodule SquadsWeb.API.ProjectJSON do
  @moduledoc """
  JSON rendering for project resources.
  """

  alias Squads.Projects.Project
  alias Squads.Squads.Squad

  def index(%{projects: projects}) do
    %{data: Enum.map(projects, &project_data/1)}
  end

  def show(%{project: project}) do
    %{data: project_data(project)}
  end

  def squads(%{squads: squads}) do
    %{data: Enum.map(squads, &squad_data/1)}
  end

  defp project_data(%Project{} = project) do
    %{
      id: project.id,
      path: project.path,
      name: project.name,
      config: project.config,
      inserted_at: project.inserted_at,
      updated_at: project.updated_at
    }
  end

  defp squad_data(%Squad{} = squad) do
    %{
      id: squad.id,
      name: squad.name,
      description: squad.description,
      project_id: squad.project_id,
      inserted_at: squad.inserted_at,
      updated_at: squad.updated_at
    }
  end
end
