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
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]}
    }
  end

  def start_link(_opts) do
    # This module is now just a facade, but we keep the GenServer structure if we want 
    # to maintain the singleton-facade pattern or we can just make it a plain module.
    # For compatibility with Squads.Application, we'll make it a simple Supervisor or Task.
    # Actually, the easiest is to just let it be a plain module and remove it from application.ex children.
    # But to minimize changes to application.ex, we can make it a :ignore worker.
    # Or even better, just remove it from application.ex and call it as a module.
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
        path = project_path || get_project_path(project_id)
        Status.set(path, :running)
        {:ok, url}

      {:error, :not_running} ->
        path = project_path || get_project_path(project_id)

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
    Repo.get!(Project, project_id).path
  end
end
