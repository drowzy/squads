defmodule SquadsWeb.API.TicketController do
  @moduledoc """
  API controller for ticket management.

  Provides endpoints to list, query, and sync tickets from Beads.
  """
  use SquadsWeb, :controller

  alias Squads.Tickets
  alias Squads.Projects

  action_fallback SquadsWeb.FallbackController

  @doc """
  List all tickets for a project.

  GET /api/projects/:project_id/tickets
  GET /api/projects/:project_id/tickets?status=open
  GET /api/projects/:project_id/tickets?issue_type=feature
  GET /api/projects/:project_id/tickets?priority=1
  """
  def index(conn, %{"project_id" => project_id} = params) do
    with_project(project_id, fn _project ->
      opts =
        []
        |> maybe_add(:status, params["status"])
        |> maybe_add(:issue_type, params["issue_type"])
        |> maybe_add(:priority, parse_int(params["priority"]))
        |> maybe_add(:assignee_id, params["assignee_id"])

      tickets = Tickets.list_tickets(project_id, opts)
      render(conn, :index, tickets: tickets)
    end)
  end

  @doc """
  Get a specific ticket.

  GET /api/tickets/:id
  """
  def show(conn, %{"id" => id}) do
    case Tickets.get_ticket(id) do
      nil -> {:error, :not_found}
      ticket -> render(conn, :show, ticket: ticket)
    end
  end

  @doc """
  Get a ticket by Beads ID.

  GET /api/projects/:project_id/tickets/beads/:beads_id
  """
  def show_by_beads_id(conn, %{"project_id" => project_id, "beads_id" => beads_id}) do
    with_project(project_id, fn _project ->
      case Tickets.get_ticket_by_beads_id(project_id, beads_id) do
        nil -> {:error, :not_found}
        ticket -> render(conn, :show, ticket: ticket)
      end
    end)
  end

  @doc """
  Create a new ticket via Beads CLI.

  POST /api/projects/:project_id/tickets
  Body: {
    "title": "Fix the bug",
    "issue_type": "bug",
    "priority": 1,
    "parent_beads_id": "epic-1" (optional)
  }
  """
  def create(conn, %{"project_id" => project_id, "title" => title} = params) do
    with_project(project_id, fn _project ->
      opts =
        []
        |> maybe_add(:issue_type, params["issue_type"])
        |> maybe_add(:priority, parse_int(params["priority"]))
        |> maybe_add(:parent_beads_id, params["parent_beads_id"])
        |> maybe_add(:parent_id, params["parent_id"])

      case Tickets.create_via_beads(project_id, title, opts) do
        {:ok, ticket} ->
          conn
          |> put_status(:created)
          |> render(:show, ticket: ticket)

        {:error, {:beads_error, reason}} ->
          conn
          |> put_status(:bad_gateway)
          |> json(%{error: "beads_error", message: inspect(reason)})

        {:error, changeset} ->
          {:error, changeset}
      end
    end)
  end

  def create(conn, %{"project_id" => _}) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "missing_title", message: "title is required"})
  end

  @doc """
  List ready tickets (no blocking dependencies, status open).

  GET /api/projects/:project_id/tickets/ready
  """
  def ready(conn, %{"project_id" => project_id}) do
    with_project(project_id, fn _project ->
      tickets = Tickets.list_ready_tickets(project_id)
      render(conn, :index, tickets: tickets)
    end)
  end

  @doc """
  List in-progress tickets.

  GET /api/projects/:project_id/tickets/in_progress
  """
  def in_progress(conn, %{"project_id" => project_id}) do
    with_project(project_id, fn _project ->
      tickets = Tickets.list_in_progress_tickets(project_id)
      render(conn, :index, tickets: tickets)
    end)
  end

  @doc """
  List blocked tickets.

  GET /api/projects/:project_id/tickets/blocked
  """
  def blocked(conn, %{"project_id" => project_id}) do
    with_project(project_id, fn _project ->
      tickets = Tickets.list_blocked_tickets(project_id)
      render(conn, :index, tickets: tickets)
    end)
  end

  @doc """
  Get a board view with tickets grouped by status.

  GET /api/projects/:project_id/board
  """
  def board(conn, %{"project_id" => project_id}) do
    with_project(project_id, fn _project ->
      summary = Tickets.board_summary(project_id)
      render(conn, :board, summary)
    end)
  end

  @doc """
  Get child tickets (subtasks) of a parent ticket.

  GET /api/tickets/:id/children
  """
  def children(conn, %{"id" => id}) do
    case Tickets.get_ticket(id) do
      nil ->
        {:error, :not_found}

      _ticket ->
        children = Tickets.list_children(id)
        render(conn, :index, tickets: children)
    end
  end

  @doc """
  Syncs tickets from Beads for a project.

  POST /api/projects/:project_id/tickets/sync
  """
  def sync(conn, %{"project_id" => project_id}) do
    with_project(project_id, fn _project ->
      case Tickets.sync_all(project_id) do
        {:ok, data} ->
          json(conn, %{data: data})

        {:error, :no_beads_db} ->
          conn
          |> put_status(:precondition_required)
          |> json(%{
            error: "beads_not_initialized",
            message: "Beads database not found. Run 'bd init' in the project root."
          })

        {:error, {:beads_error, :no_beads_db}} ->
          conn
          |> put_status(:precondition_required)
          |> json(%{
            error: "beads_not_initialized",
            message: "Beads database not found. Run 'bd init' in the project root."
          })

        {:error, {:beads_error, reason}} ->
          conn
          |> put_status(:bad_gateway)
          |> json(%{error: "beads_error", message: inspect(reason)})

        {:error, reason} ->
          conn
          |> put_status(:bad_gateway)
          |> json(%{error: "sync_error", message: inspect(reason)})
      end
    end)
  end

  @doc """
  Claim a ticket for an agent (assigns and sets to in_progress).

  POST /api/tickets/:id/claim
  Body: { "agent_id": "uuid", "agent_name": "GreenPanda" }
  """
  def claim(conn, %{"id" => id} = params) do
    with_ticket(id, fn ticket ->
      agent_id = params["agent_id"]
      agent_name = params["agent_name"]

      if is_nil(agent_id) or is_nil(agent_name) do
        conn
        |> put_status(:bad_request)
        |> json(%{error: "missing_params", message: "agent_id and agent_name are required"})
      else
        case Tickets.claim_ticket(ticket, agent_id, agent_name) do
          {:ok, updated} ->
            render(conn, :show, ticket: updated)

          {:error, {:beads_error, reason}} ->
            conn
            |> put_status(:bad_gateway)
            |> json(%{error: "beads_error", message: inspect(reason)})

          {:error, changeset} ->
            {:error, changeset}
        end
      end
    end)
  end

  @doc """
  Unclaim a ticket (removes assignment and sets back to open).

  POST /api/tickets/:id/unclaim
  """
  def unclaim(conn, %{"id" => id}) do
    with_ticket(id, fn ticket ->
      case Tickets.unclaim_ticket(ticket) do
        {:ok, updated} ->
          render(conn, :show, ticket: updated)

        {:error, {:beads_error, reason}} ->
          conn
          |> put_status(:bad_gateway)
          |> json(%{error: "beads_error", message: inspect(reason)})

        {:error, changeset} ->
          {:error, changeset}
      end
    end)
  end

  @doc """
  Update a ticket's status.

  PATCH /api/tickets/:id/status
  Body: { "status": "in_progress" }
  """
  def update_status(conn, %{"id" => id, "status" => status}) do
    with_ticket(id, fn ticket ->
      case Tickets.update_status(ticket, status) do
        {:ok, updated} ->
          render(conn, :show, ticket: updated)

        {:error, {:beads_error, reason}} ->
          conn
          |> put_status(:bad_gateway)
          |> json(%{error: "beads_error", message: inspect(reason)})

        {:error, changeset} ->
          {:error, changeset}
      end
    end)
  end

  def update_status(conn, %{"id" => _id}) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "missing_status", message: "status is required"})
  end

  @doc """
  Close a ticket.

  POST /api/tickets/:id/close
  Body: { "reason": "Completed implementation" } (optional)
  """
  def close(conn, %{"id" => id} = params) do
    with_ticket(id, fn ticket ->
      case Tickets.close_ticket(ticket, params["reason"]) do
        {:ok, updated} ->
          render(conn, :show, ticket: updated)

        {:error, {:beads_error, reason}} ->
          conn
          |> put_status(:bad_gateway)
          |> json(%{error: "beads_error", message: inspect(reason)})

        {:error, changeset} ->
          {:error, changeset}
      end
    end)
  end

  # Helper to validate project exists
  defp with_project(project_id, fun) do
    case Projects.get_project(project_id) do
      nil -> {:error, :not_found}
      project -> fun.(project)
    end
  end

  # Helper to fetch ticket or return not found
  defp with_ticket(id, fun) do
    case Tickets.get_ticket(id) do
      nil -> {:error, :not_found}
      ticket -> fun.(ticket)
    end
  end

  defp maybe_add(opts, _key, nil), do: opts
  defp maybe_add(opts, key, value), do: Keyword.put(opts, key, value)

  defp parse_int(nil), do: nil

  defp parse_int(str) when is_binary(str) do
    case Integer.parse(str) do
      {int, _} -> int
      :error -> nil
    end
  end

  defp parse_int(int) when is_integer(int), do: int
end
