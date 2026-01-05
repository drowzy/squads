defmodule Squads.OpenCode.Server do
  @moduledoc """
  Facade for managing per-project OpenCode servers.
  """
  require Logger

  alias Squads.Repo
  alias Squads.Projects.Project
  alias Squads.OpenCode.ProjectServer
  alias Squads.OpenCode.ProjectSupervisor
  alias Squads.OpenCode.Status

  @registry Squads.OpenCode.ServerRegistry

  def child_spec(opts) do
    # We remove the id: __MODULE__ so it doesn't get started by the supervisor
    # Or we can just return a spec that does nothing.
    # Actually, let's just make it :ignore so application.ex doesn't have to change immediately.
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]}
    }
  end

  def start_link(_opts) do
    # This module is now just a facade. Returning :ignore means the supervisor won't 
    # keep track of it, and we don't need a running process for this module.
    :ignore
  end

  @doc """
  Lists all currently running projects and their URLs.
  """
  def list_running_servers do
    Registry.select(@registry, [{{:"$1", :"$2", :"$3"}, [], [{{:"$1", :"$3"}}]}])
    |> Map.new(fn {id, url} -> {id, %{url: url, status: :running}} end)
  end

  @doc """
  Ensures an OpenCode server is running for the given project.
  Returns {:ok, base_url} or {:error, reason}.
  """
  def ensure_running(project_id, project_path \\ nil) do
    case get_url(project_id) do
      {:ok, url} ->
        if path = project_path || get_project_path(project_id) do
          Status.set(path, :running)
        end

        {:ok, url}

      {:error, :not_running} ->
        path = project_path || get_project_path(project_id)

        if is_nil(path) do
          {:error, :project_not_found}
        else
          case DynamicSupervisor.start_child(
                 ProjectSupervisor,
                 {ProjectServer, project_id: project_id, project_path: path}
               ) do
            {:ok, pid} ->
              ProjectServer.ensure_running(pid)

            {:error, {:already_started, pid}} ->
              ProjectServer.ensure_running(pid)

            {:error, reason} ->
              {:error, reason}
          end
        end

      {:error, :starting} ->
        # If it's starting, we can find the pid in the registry and wait for it
        case Registry.lookup(@registry, project_id) do
          [{pid, _}] -> ProjectServer.ensure_running(pid)
          [] -> ensure_running(project_id, project_path)
        end
    end
  end

  @doc """
  Gets the base URL for a running project server.
  """
  def get_url(project_id) do
    case Registry.lookup(@registry, project_id) do
      [{_pid, url}] when is_binary(url) -> {:ok, url}
      [{_pid, _}] -> {:error, :starting}
      [] -> {:error, :not_running}
    end
  end

  defp get_project_path(project_id) do
    case Repo.get(Project, project_id) do
      nil -> nil
      project -> project.path
    end
  end
end
