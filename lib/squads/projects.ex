defmodule Squads.Projects do
  @moduledoc """
  Context module for managing projects.

  Provides functions for initializing, creating, and querying projects.
  """

  import Ecto.Query, warn: false

  alias Squads.Repo
  alias Squads.Projects.Project
  alias Squads.Config.ProjectConfig
  alias Squads.OpenCode.Config, as: OpenCodeConfig

  @doc """
  Initializes a new project at the given path.

  Creates:
  - `.squads/config.json` with project configuration
  - `opencode.json` with default OpenCode settings (MCPs, custom commands)

  Returns `{:ok, project}` on success, `{:error, reason}` on failure.
  """
  @spec init(String.t(), String.t(), map()) :: {:ok, Project.t()} | {:error, term()}
  def init(path, name, config_overrides \\ %{}) do
    with :ok <- validate_path(path),
         config <- ProjectConfig.new(name, config_overrides),
         :ok <- ProjectConfig.save(path, config),
         {:ok, _} <- OpenCodeConfig.init(path),
         {:ok, project} <- create_project(%{path: path, name: name, config: config}) do
      {:ok, project}
    end
  end

  @doc """
  Returns the project for a given path, if it exists.
  """
  @spec get_by_path(String.t()) :: Project.t() | nil
  def get_by_path(path) do
    Repo.get_by(Project, path: path)
  end

  @doc """
  Returns all projects.
  """
  @spec list_projects() :: [Project.t()]
  def list_projects do
    Repo.all(Project)
  end

  @doc """
  Gets a project by ID.
  """
  @spec get_project(Ecto.UUID.t()) :: Project.t() | nil
  def get_project(id) do
    Repo.get(Project, id)
  end

  @doc """
  Fetches a project by ID with a tuple result.
  """
  @spec fetch_project(Ecto.UUID.t()) :: {:ok, Project.t()} | {:error, :not_found}
  def fetch_project(id) do
    case get_project(id) do
      nil -> {:error, :not_found}
      project -> {:ok, project}
    end
  end

  @doc """
  Creates a project record in the database.
  """
  @spec create_project(map()) :: {:ok, Project.t()} | {:error, Ecto.Changeset.t()}
  def create_project(attrs) do
    %Project{}
    |> Project.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a project.
  """
  @spec update_project(Project.t(), map()) :: {:ok, Project.t()} | {:error, Ecto.Changeset.t()}
  def update_project(%Project{} = project, attrs) do
    project
    |> Project.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a project.
  """
  @spec delete_project(Project.t()) :: {:ok, Project.t()} | {:error, Ecto.Changeset.t()}
  def delete_project(%Project{} = project) do
    Repo.delete(project)
  end

  @doc """
  Checks if a path has been initialized as a Squads project.
  """
  @spec initialized?(String.t()) :: boolean()
  def initialized?(path) do
    config_path = ProjectConfig.config_path(path)
    File.exists?(config_path)
  end

  @doc """
  Loads the config for a project from its `.squads/config.json` file.
  """
  @spec load_config(String.t()) :: {:ok, map()} | {:error, String.t()}
  def load_config(path) do
    ProjectConfig.load(path)
  end

  @doc """
  Syncs a project's database record with its config file.

  Useful after manual config edits.
  """
  @spec sync_config(Project.t()) :: {:ok, Project.t()} | {:error, term()}
  def sync_config(%Project{} = project) do
    case ProjectConfig.load(project.path) do
      {:ok, config} ->
        update_project(project, %{config: config, name: config["name"] || project.name})

      {:error, _} = error ->
        error
    end
  end

  # Private functions

  defp validate_path(path) do
    cond do
      not String.starts_with?(path, "/") ->
        {:error, "path must be absolute"}

      not File.dir?(path) ->
        {:error, "path does not exist or is not a directory"}

      true ->
        :ok
    end
  end
end
