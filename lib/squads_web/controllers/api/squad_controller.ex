defmodule SquadsWeb.API.SquadController do
  @moduledoc """
  API controller for squad management.

  Provides endpoints to create, update, and delete squads within a project.
  """
  use SquadsWeb, :controller

  alias Squads.Squads, as: SquadsContext
  alias Squads.Projects
  alias Squads.Agents
  alias Squads.Repo

  action_fallback SquadsWeb.FallbackController

  @doc """
  List all squads for a project with their agents.

  GET /api/projects/:project_id/squads
  """
  def index(conn, %{"project_id" => project_id}) do
    with_project(project_id, fn _project ->
      squads = SquadsContext.list_squads_with_agents(project_id)
      render(conn, :index, squads: squads)
    end)
  end

  @doc """
  Show a single squad with its agents.

  GET /api/squads/:id
  """
  def show(conn, %{"id" => id}) do
    case SquadsContext.get_squad_with_agents(id) do
      nil -> {:error, :not_found}
      squad -> render(conn, :show, squad: squad)
    end
  end

  @doc """
  Create a new squad.

  POST /api/projects/:project_id/squads
  Body: {"name": "Alpha Team", "description": "Backend specialists"}
  """
  def create(conn, %{"project_id" => project_id, "name" => name} = params) do
    with_project(project_id, fn _project ->
      attrs = %{
        project_id: project_id,
        name: name,
        description: params["description"]
      }

      case SquadsContext.create_squad(attrs) do
        {:ok, squad} ->
          conn
          |> put_status(:created)
          |> render(:show, squad: squad)

        {:error, changeset} ->
          {:error, changeset}
      end
    end)
  end

  @doc """
  Update an existing squad.

  PATCH /api/squads/:id
  Body: {"name": "New Name", "description": "Updated description"}
  """
  def update(conn, %{"id" => id} = params) do
    case SquadsContext.get_squad(id) do
      nil ->
        {:error, :not_found}

      squad ->
        attrs =
          %{}
          |> maybe_put(:name, params["name"])
          |> maybe_put(:description, params["description"])

        case SquadsContext.update_squad(squad, attrs) do
          {:ok, updated_squad} ->
            render(conn, :show, squad: updated_squad)

          {:error, changeset} ->
            {:error, changeset}
        end
    end
  end

  @doc """
  Delete a squad.

  DELETE /api/squads/:id
  """
  def delete(conn, %{"id" => id}) do
    case SquadsContext.get_squad(id) do
      nil ->
        {:error, :not_found}

      squad ->
        case SquadsContext.delete_squad(squad) do
          {:ok, _squad} ->
            send_resp(conn, :no_content, "")

          {:error, changeset} ->
            {:error, changeset}
        end
    end
  end

  @doc """
  List agents in a squad.

  GET /api/squads/:id/agents
  """
  def agents(conn, %{"squad_id" => squad_id}) do
    case SquadsContext.get_squad(squad_id) do
      nil ->
        {:error, :not_found}

      _squad ->
        agents = Agents.list_agents_for_squad(squad_id)
        render(conn, :agents, agents: agents)
    end
  end

  # Helper functions

  defp with_project(project_id, fun) do
    case Projects.get_project(project_id) do
      nil -> {:error, :not_found}
      project -> fun.(project)
    end
  end

  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
