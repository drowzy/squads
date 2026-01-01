defmodule Squads.Tickets do
  @moduledoc """
  Context for managing tickets synced from Beads.

  Provides CRUD operations for tickets and synchronization
  with the Beads CLI tool.
  """
  import Ecto.Query

  alias Squads.Repo
  alias Squads.Tickets.{Ticket, TicketDependency}
  alias Squads.Beads.Adapter, as: Beads

  # ============================================================================
  # Basic CRUD
  # ============================================================================

  @doc """
  Returns all tickets for a project.
  """
  def list_tickets(project_id, opts \\ []) do
    Ticket
    |> where(project_id: ^project_id)
    |> apply_filters(opts)
    |> order_by([t], asc: t.priority, desc: t.beads_updated_at)
    |> Repo.all()
  end

  @doc """
  Gets a ticket by ID.
  """
  def get_ticket(id), do: Repo.get(Ticket, id)

  @doc """
  Gets a ticket by ID with sessions preloaded.
  """
  def get_ticket_with_sessions(id) do
    Ticket
    |> where(id: ^id)
    |> preload(:sessions)
    |> Repo.one()
  end

  @doc """
  Gets a ticket by ID with all associations preloaded.
  """
  def get_ticket_with_preloads(id, preloads \\ [:sessions, :children, :assignee]) do
    Ticket
    |> where(id: ^id)
    |> preload(^preloads)
    |> Repo.one()
  end

  @doc """
  Gets a ticket by Beads ID within a project.
  """
  def get_ticket_by_beads_id(project_id, beads_id) do
    Repo.get_by(Ticket, project_id: project_id, beads_id: beads_id)
  end

  @doc """
  Creates a ticket.
  """
  def create_ticket(attrs) do
    %Ticket{}
    |> Ticket.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a ticket.
  """
  def update_ticket(%Ticket{} = ticket, attrs) do
    ticket
    |> Ticket.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a ticket.
  """
  def delete_ticket(%Ticket{} = ticket), do: Repo.delete(ticket)

  # ============================================================================
  # Query Helpers
  # ============================================================================

  @doc """
  Returns tickets that are ready to work on (no blocking dependencies).
  """
  def list_ready_tickets(project_id) do
    # Tickets are ready if:
    # 1. Status is "open"
    # 2. No "blocks" dependencies are in non-closed status
    blocked_ids = blocked_ticket_ids_query(project_id)

    Ticket
    |> where(project_id: ^project_id, status: "open")
    |> where([t], t.id not in subquery(blocked_ids))
    |> order_by([t], asc: t.priority, desc: t.beads_updated_at)
    |> Repo.all()
  end

  @doc """
  Returns tickets currently in progress.
  """
  def list_in_progress_tickets(project_id) do
    Ticket
    |> where(project_id: ^project_id, status: "in_progress")
    |> order_by([t], asc: t.priority, desc: t.beads_updated_at)
    |> Repo.all()
  end

  @doc """
  Returns tickets that are blocked.
  """
  def list_blocked_tickets(project_id) do
    blocked_ids = blocked_ticket_ids_query(project_id)

    Ticket
    |> where(project_id: ^project_id)
    |> where([t], t.status in ["open", "in_progress"])
    |> where([t], t.id in subquery(blocked_ids))
    |> order_by([t], asc: t.priority, desc: t.beads_updated_at)
    |> Repo.all()
  end

  @doc """
  Returns tickets assigned to a specific agent.
  """
  def list_agent_tickets(agent_id) do
    Ticket
    |> where(assignee_id: ^agent_id)
    |> where([t], t.status != "closed")
    |> order_by([t], asc: t.priority, desc: t.beads_updated_at)
    |> Repo.all()
  end

  @doc """
  Returns child tickets (subtasks) of a parent ticket.
  """
  def list_children(ticket_id) do
    Ticket
    |> where(parent_id: ^ticket_id)
    |> order_by([t], asc: t.priority, asc: t.beads_id)
    |> Repo.all()
  end

  # ============================================================================
  # Assignment
  # ============================================================================

  @doc """
  Assigns a ticket to an agent.
  """
  def assign_ticket(%Ticket{} = ticket, agent_id, agent_name \\ nil) do
    ticket
    |> Ticket.changeset(%{assignee_id: agent_id, assignee_name: agent_name})
    |> Repo.update()
  end

  @doc """
  Unassigns a ticket from its current agent.
  """
  def unassign_ticket(%Ticket{} = ticket) do
    ticket
    |> Ticket.changeset(%{assignee_id: nil, assignee_name: nil})
    |> Repo.update()
  end

  @doc """
  Claims a ticket for an agent and updates Beads.

  This sets the ticket to in_progress status and assigns it to the agent.
  """
  def claim_ticket(%Ticket{} = ticket, agent_id, agent_name) do
    path = get_project_path(ticket.project_id)

    with {:ok, _} <-
           Beads.update_issue(path, ticket.beads_id, status: "in_progress", assignee: agent_name),
         {:ok, updated} <-
           update_ticket(ticket, %{
             status: "in_progress",
             assignee_id: agent_id,
             assignee_name: agent_name
           }) do
      {:ok, updated}
    else
      {:error, %Ecto.Changeset{} = changeset} -> {:error, changeset}
      {:error, reason} -> {:error, {:beads_error, reason}}
    end
  end

  @doc """
  Unclaims a ticket (removes assignment and sets back to open).
  """
  def unclaim_ticket(%Ticket{} = ticket) do
    path = get_project_path(ticket.project_id)

    with {:ok, _} <- Beads.update_issue(path, ticket.beads_id, status: "open", assignee: ""),
         {:ok, updated} <-
           update_ticket(ticket, %{
             status: "open",
             assignee_id: nil,
             assignee_name: nil
           }) do
      {:ok, updated}
    else
      {:error, %Ecto.Changeset{} = changeset} -> {:error, changeset}
      {:error, reason} -> {:error, {:beads_error, reason}}
    end
  end

  @doc """
  Updates ticket status and syncs to Beads.
  """
  def update_status(%Ticket{} = ticket, status) do
    path = get_project_path(ticket.project_id)

    with {:ok, _} <- Beads.update_status(path, ticket.beads_id, status),
         {:ok, updated} <- update_ticket(ticket, %{status: status}) do
      {:ok, updated}
    else
      {:error, %Ecto.Changeset{} = changeset} -> {:error, changeset}
      {:error, reason} -> {:error, {:beads_error, reason}}
    end
  end

  @doc """
  Closes a ticket, optionally merges its associated worktree, and syncs to Beads.
  """
  def close_ticket(%Ticket{} = ticket, reason \\ nil) do
    # Try to find an associated worktree to cleanup/merge
    # Worktree name format: <agent_slug>-<ticket_id>
    ticket = Repo.preload(ticket, [:assignee])
    path = get_project_path(ticket.project_id)

    worktree_name =
      if ticket.assignee do
        "#{ticket.assignee.slug}-#{ticket.id}"
      else
        nil
      end

    if worktree_name &&
         File.exists?(
           Path.join([
             path,
             ".squads",
             "worktrees",
             worktree_name
           ])
         ) do
      # If worktree exists, we might want to merge it. 
      # For now, let's just ensure we close the ticket in Beads first.
      case perform_close(ticket, path, reason) do
        {:ok, updated} ->
          # Fire and forget worktree cleanup for now, or handle it synchronously?
          # Best to handle it synchronously to ensure state consistency if possible.
          Squads.Worktrees.merge_and_cleanup(ticket.project_id, worktree_name)
          {:ok, updated}

        error ->
          error
      end
    else
      perform_close(ticket, path, reason)
    end
  end

  defp perform_close(ticket, path, reason) do
    with {:ok, _} <- Beads.close_issue(path, ticket.beads_id, reason),
         {:ok, updated} <-
           update_ticket(ticket, %{
             status: "closed",
             beads_closed_at: DateTime.utc_now() |> DateTime.truncate(:second)
           }) do
      {:ok, updated}
    else
      {:error, %Ecto.Changeset{} = changeset} -> {:error, changeset}
      {:error, reason} -> {:error, {:beads_error, reason}}
    end
  end

  @doc """
  Creates a new ticket via Beads CLI and mirrors it locally.
  """
  def create_via_beads(project_id, title, opts \\ []) do
    path = get_project_path(project_id)

    beads_opts =
      [
        type: opts[:issue_type],
        priority: opts[:priority],
        parent: opts[:parent_beads_id]
      ]
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)

    with {:ok, beads_data} <- Beads.create_issue(path, title, beads_opts) do
      attrs =
        Ticket.map_from_beads(beads_data)
        |> Map.put(:project_id, project_id)
        |> Map.put(:synced_at, DateTime.utc_now() |> DateTime.truncate(:second))

      # Handle parent_id if provided (local reference)
      attrs =
        if parent_id = opts[:parent_id] do
          Map.put(attrs, :parent_id, parent_id)
        else
          attrs
        end

      create_ticket(attrs)
    else
      {:error, %Ecto.Changeset{} = changeset} -> {:error, changeset}
      {:error, reason} -> {:error, {:beads_error, reason}}
    end
  end

  # ============================================================================
  # Dependencies
  # ============================================================================

  @doc """
  Adds a dependency between tickets.
  """
  def add_dependency(ticket_id, dependency_id, type \\ "blocks") do
    %TicketDependency{}
    |> TicketDependency.changeset(%{
      ticket_id: ticket_id,
      dependency_id: dependency_id,
      dependency_type: type
    })
    |> Repo.insert()
  end

  @doc """
  Removes a dependency between tickets.
  """
  def remove_dependency(ticket_id, dependency_id) do
    TicketDependency
    |> where(ticket_id: ^ticket_id, dependency_id: ^dependency_id)
    |> Repo.delete_all()
  end

  @doc """
  Returns all dependencies for a ticket (what it depends on).
  """
  def list_dependencies(ticket_id) do
    TicketDependency
    |> where(ticket_id: ^ticket_id)
    |> preload(:dependency)
    |> Repo.all()
  end

  @doc """
  Returns all dependents of a ticket (what depends on it).
  """
  def list_dependents(ticket_id) do
    TicketDependency
    |> where(dependency_id: ^ticket_id)
    |> preload(:ticket)
    |> Repo.all()
  end

  # ============================================================================
  # Sync with Beads
  # ============================================================================

  @doc """
  Syncs all tickets from Beads for a project.

  Returns {:ok, %{created: n, updated: m}} on success.
  """
  def sync_from_beads(project_id) do
    path = get_project_path(project_id)

    with {:ok, issues} <- Beads.list_issues(path) do
      results =
        issues
        |> Enum.map(&sync_single_ticket(project_id, &1))
        |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))

      {:ok,
       %{
         created: length(Map.get(results, :created, [])),
         updated: length(Map.get(results, :updated, [])),
         errors: Map.get(results, :error, [])
       }}
    end
  end

  @doc """
  Syncs a single ticket from Beads data.
  """
  def sync_ticket(project_id, beads_id) do
    path = get_project_path(project_id)

    with {:ok, data} <- Beads.show_issue(path, beads_id) do
      sync_single_ticket(project_id, data)
    end
  end

  defp sync_single_ticket(project_id, beads_data) do
    beads_id = beads_data["id"]

    case get_ticket_by_beads_id(project_id, beads_id) do
      nil ->
        attrs = Ticket.map_from_beads(beads_data) |> Map.put(:project_id, project_id)

        case create_ticket(attrs) do
          {:ok, ticket} -> {:created, ticket}
          {:error, changeset} -> {:error, {beads_id, changeset}}
        end

      existing ->
        case update_ticket(existing, Ticket.map_from_beads(beads_data)) do
          {:ok, ticket} -> {:updated, ticket}
          {:error, changeset} -> {:error, {beads_id, changeset}}
        end
    end
  end

  @doc """
  Syncs dependencies from Beads data.

  This should be called after sync_from_beads to resolve dependency references.
  """
  def sync_dependencies(project_id) do
    path = get_project_path(project_id)

    with {:ok, issues} <- Beads.list_issues(path) do
      results =
        issues
        |> Enum.flat_map(&extract_dependencies(project_id, &1))
        |> Enum.map(&create_dependency_if_missing/1)
        |> Enum.count(&match?({:ok, _}, &1))

      {:ok, %{synced: results}}
    end
  end

  defp extract_dependencies(project_id, %{"id" => beads_id, "dependencies" => deps})
       when is_list(deps) do
    ticket = get_ticket_by_beads_id(project_id, beads_id)

    if ticket do
      Enum.map(deps, fn dep ->
        dep_ticket = get_ticket_by_beads_id(project_id, dep["id"])
        {ticket, dep_ticket, dep["dependency_type"] || "blocks"}
      end)
      |> Enum.filter(fn {_, dep_ticket, _} -> dep_ticket != nil end)
    else
      []
    end
  end

  defp extract_dependencies(_project_id, _), do: []

  defp create_dependency_if_missing({ticket, dep_ticket, type}) do
    existing =
      TicketDependency
      |> where(ticket_id: ^ticket.id, dependency_id: ^dep_ticket.id)
      |> Repo.one()

    if existing do
      {:ok, existing}
    else
      add_dependency(ticket.id, dep_ticket.id, type)
    end
  end

  # ============================================================================
  # Orchestration
  # ============================================================================

  @doc """
  Returns a summary of tickets grouped by status for a project.
  """
  def board_summary(project_id) do
    %{
      ready: list_ready_tickets(project_id),
      in_progress: list_in_progress_tickets(project_id),
      blocked: list_blocked_tickets(project_id),
      closed: list_tickets(project_id, status: "closed")
    }
  end

  @doc """
  Syncs all tickets and dependencies from Beads, returning a summary.
  """
  def sync_all(project_id) do
    with {:ok, result} <- sync_from_beads(project_id),
         {:ok, dep_result} <- sync_dependencies(project_id) do
      {:ok,
       %{
         created: result.created,
         updated: result.updated,
         dependencies_synced: dep_result.synced,
         errors: length(result.errors)
       }}
    end
  end

  @doc """
  Returns a command-friendly summary of tickets for a project.
  """
  def get_tickets_summary(project_id) do
    summary = board_summary(project_id)

    %{
      todo: Enum.count(summary.ready),
      in_progress: Enum.count(summary.in_progress),
      blocked: Enum.count(summary.blocked),
      closed: Enum.count(summary.closed),
      active_tickets:
        Enum.map(summary.in_progress, fn t ->
          %{id: t.beads_id, title: t.title, assignee: t.assignee_name}
        end)
    }
  end

  # ============================================================================
  # Private Helpers
  # ============================================================================

  defp apply_filters(query, opts) do
    Enum.reduce(opts, query, fn
      {:status, status}, q -> where(q, status: ^status)
      {:issue_type, type}, q -> where(q, issue_type: ^type)
      {:priority, priority}, q -> where(q, priority: ^priority)
      {:assignee_id, id}, q -> where(q, assignee_id: ^id)
      _, q -> q
    end)
  end

  defp blocked_ticket_ids_query(project_id) do
    # Find tickets that have at least one non-closed blocking dependency
    from td in TicketDependency,
      join: t in Ticket,
      on: td.ticket_id == t.id,
      join: d in Ticket,
      on: td.dependency_id == d.id,
      where: t.project_id == ^project_id,
      where: td.dependency_type == "blocks",
      where: d.status != "closed",
      select: td.ticket_id
  end

  defp get_project_path(project_id) do
    Squads.Projects.get_project(project_id).path
  end
end
