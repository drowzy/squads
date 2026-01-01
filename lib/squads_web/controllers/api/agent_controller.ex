defmodule SquadsWeb.API.AgentController do
  @moduledoc """
  API controller for agent management.

  Provides endpoints to create, update, and delete agents within squads.
  """
  use SquadsWeb, :controller

  alias Squads.Agents
  alias Squads.Agents.Roles
  alias Squads.Squads, as: SquadsContext

  action_fallback SquadsWeb.FallbackController

  @doc """
  List available roles, levels, and default system instructions.

  GET /api/agents/roles
  """
  def roles(conn, _params) do
    render(conn, :roles,
      roles: Roles.roles(),
      levels: Roles.levels(),
      defaults: %{role: Roles.default_role_id(), level: Roles.default_level_id()},
      system_instructions: Roles.system_instructions()
    )
  end

  @doc """
  List all agents for a squad.

  GET /api/squads/:squad_id/agents
  """
  def index(conn, %{"squad_id" => squad_id}) do
    with_squad(squad_id, fn _squad ->
      agents = Agents.list_agents_for_squad(squad_id)
      render(conn, :index, agents: agents)
    end)
  end

  @doc """
  Show a single agent.

  GET /api/agents/:id
  """
  def show(conn, %{"id" => id}) do
    case Agents.get_agent(id) do
      nil -> {:error, :not_found}
      agent -> render(conn, :show, agent: agent)
    end
  end

  @doc """
  Create a new agent in a squad.

  POST /api/squads/:squad_id/agents
  Body: {"model": "claude-sonnet-4-20250514"} - name is auto-generated
  Or: {"name": "BluePanda", "slug": "blue-panda", "model": "..."}
  """
  def create(conn, %{"squad_id" => squad_id} = params) do
    with_squad(squad_id, fn _squad ->
      case Agents.create_agent_for_squad(squad_id, params) do
        {:ok, agent} ->
          conn
          |> put_status(:created)
          |> render(:show, agent: agent)

        {:error, changeset} ->
          {:error, changeset}
      end
    end)
  end

  @doc """
  Update an existing agent.

  PATCH /api/agents/:id
  Body: {"model": "...", "status": "working", "mentor_id": "..."}
  """
  def update(conn, %{"id" => id} = params) do
    case Agents.get_agent(id) do
      nil ->
        {:error, :not_found}

      agent ->
        attrs =
          %{}
          |> maybe_put(:model, params["model"])
          |> maybe_put(:role, params["role"])
          |> maybe_put(:level, params["level"])
          |> maybe_put(:system_instruction, params["system_instruction"])
          |> maybe_put(:status, params["status"])
          |> maybe_put(:mentor_id, params["mentor_id"])

        case Agents.update_agent(agent, attrs) do
          {:ok, updated_agent} ->
            render(conn, :show, agent: updated_agent)

          {:error, changeset} ->
            {:error, changeset}
        end
    end
  end

  @doc """
  Delete an agent.

  DELETE /api/agents/:id
  """
  def delete(conn, %{"id" => id}) do
    case Agents.get_agent(id) do
      nil ->
        {:error, :not_found}

      agent ->
        case Agents.delete_agent(agent) do
          {:ok, _agent} ->
            send_resp(conn, :no_content, "")

          {:error, changeset} ->
            {:error, changeset}
        end
    end
  end

  @doc """
  Update agent status.

  PATCH /api/agents/:id/status
  Body: {"status": "working"}
  """
  def update_status(conn, %{"agent_id" => id, "status" => status}) do
    case Agents.get_agent(id) do
      nil ->
        {:error, :not_found}

      agent ->
        case Agents.update_agent(agent, %{status: status}) do
          {:ok, updated_agent} ->
            render(conn, :show, agent: updated_agent)

          {:error, changeset} ->
            {:error, changeset}
        end
    end
  end

  # Helper functions

  defp with_squad(squad_id, fun) do
    case Ecto.UUID.cast(squad_id) do
      {:ok, uuid} ->
        case SquadsContext.get_squad(uuid) do
          nil -> {:error, :not_found}
          squad -> fun.(squad)
        end

      :error ->
        {:error, :not_found}
    end
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
