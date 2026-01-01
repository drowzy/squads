defmodule SquadsWeb.API.ProjectController do
  @moduledoc """
  API controller for project and squad metadata.
  """
  use SquadsWeb, :controller

  alias Squads.Filesystem
  alias Squads.Projects
  alias Squads.Squads

  action_fallback SquadsWeb.FallbackController

  @doc """
  Lists all projects.
  """
  def index(conn, _params) do
    projects = Projects.list_projects()
    render(conn, :index, projects: projects)
  end

  @doc """
  Shows a single project by ID.
  """
  def show(conn, %{"id" => id}) do
    with {:ok, uuid} <- Ecto.UUID.cast(id),
         project when not is_nil(project) <- Projects.get_project(uuid) do
      render(conn, :show, project: project)
    else
      :error -> {:error, :not_found}
      nil -> {:error, :not_found}
    end
  end

  @doc """
  Creates/initializes a new project.
  """
  def create(conn, %{"path" => path, "name" => name} = params) do
    config_overrides = Map.get(params, "config", %{})

    case Projects.init(path, name, config_overrides) do
      {:ok, project} ->
        conn
        |> put_status(:created)
        |> render(:show, project: project)

      {:error, reason} when is_binary(reason) ->
        {:error, :unprocessable_entity, reason}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  @doc """
  Browse filesystem directories for project selection.

  GET /api/projects/browse?path=/some/path
  Returns directories at the given path (defaults to home directory).
  """
  def browse(conn, params) do
    path = Map.get(params, "path")
    show_hidden = Map.get(params, "show_hidden", "false") == "true"

    case Filesystem.browse(path, show_hidden: show_hidden) do
      {:ok, result} ->
        json(conn, result)

      {:error, :not_a_directory} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "Not a directory", path: path})

      {:error, reason} ->
        conn
        |> put_status(:forbidden)
        |> json(%{error: "Cannot read directory", reason: to_string(reason), path: path})
    end
  end

  @doc """
  Lists squads for a project.
  """
  def squads(conn, %{"project_id" => project_id}) do
    case Projects.get_project(project_id) do
      nil ->
        {:error, :not_found}

      project ->
        squads = Squads.list_squads_for_project(project.id)
        render(conn, :squads, squads: squads)
    end
  end
end
