defmodule SquadsWeb.API.SquadController do
  @moduledoc """
  API controller for squad management.

  Provides endpoints to create, update, and delete squads within a project.
  """
  use SquadsWeb, :controller

  alias Squads.Squads, as: SquadsContext
  alias Squads.Projects
  alias Squads.Agents

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
          squad = SquadsContext.get_squad_with_agents(squad.id) || squad

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
            updated_squad = SquadsContext.get_squad_with_agents(updated_squad.id) || updated_squad
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

  @doc """
  Send a message to a connected squad.

  POST /api/squads/:id/message
  Body: {
    "to_squad_id": "uuid",
    "subject": "Hello",
    "body": "Message content",
    "sender_name": "Optional sender name"
  }
  """
  def message(conn, %{"squad_id" => sender_squad_id, "to_squad_id" => target_squad_id} = params) do
    # 1. Verify connection
    connections = SquadsContext.list_connections_for_squad(sender_squad_id)

    is_connected =
      Enum.any?(connections, fn c ->
        (c.from_squad_id == sender_squad_id && c.to_squad_id == target_squad_id) ||
          (c.from_squad_id == target_squad_id && c.to_squad_id == sender_squad_id)
      end)

    if !is_connected do
      conn
      |> put_status(:forbidden)
      |> json(%{error: "not_connected", message: "Squads are not connected"})
    else
      # 2. Get target squad details (for project_id)
      target_squad = SquadsContext.get_squad!(target_squad_id)
      sender_squad = SquadsContext.get_squad!(sender_squad_id)

      # 3. Get target agents
      target_agents = Agents.list_agents_for_squad(target_squad_id)
      recipient_ids = Enum.map(target_agents, & &1.id)

      if recipient_ids == [] do
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "no_recipients", message: "Target squad has no agents"})
      else
        # 4. Send message
        # We create the thread in the TARGET squad's project context
        sender_name = params["sender_name"] || "Squad #{sender_squad.name}"

        mail_params = %{
          project_id: target_squad.project_id,
          subject: params["subject"],
          body_md: params["body"],
          to: recipient_ids,
          author_name: sender_name,
          importance: "normal",
          kind: "text"
        }

        case Squads.Mail.send_message(mail_params) do
          {:ok, message} ->
            conn
            |> put_status(:created)
            |> render(:message_sent, message: message)

          {:error, _reason} ->
            conn
            |> put_status(:unprocessable_entity)
            |> json(%{error: "send_failed", message: "Failed to send message"})
        end
      end
    end
  end

  # Helper functions

  defp with_project(project_id, fun) do
    case Ecto.UUID.cast(project_id) do
      {:ok, uuid} ->
        case Projects.get_project(uuid) do
          nil -> {:error, :not_found}
          project -> fun.(project)
        end

      :error ->
        {:error, :not_found}
    end
  end

  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
