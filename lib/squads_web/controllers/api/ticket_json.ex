defmodule SquadsWeb.API.TicketJSON do
  @moduledoc """
  JSON rendering for tickets.
  """

  alias Squads.Tickets.Ticket

  @doc """
  Renders a list of tickets.
  """
  def index(%{tickets: tickets}) do
    %{data: for(ticket <- tickets, do: data(ticket))}
  end

  @doc """
  Renders a single ticket.
  """
  def show(%{ticket: ticket}) do
    %{data: data(ticket)}
  end

  @doc """
  Renders a board view with tickets grouped by status.
  """
  def board(%{ready: ready, in_progress: in_progress, blocked: blocked, closed: closed}) do
    %{
      data: %{
        ready: for(t <- ready, do: data(t)),
        in_progress: for(t <- in_progress, do: data(t)),
        blocked: for(t <- blocked, do: data(t)),
        closed: for(t <- closed, do: data(t))
      }
    }
  end

  defp data(%Ticket{} = ticket) do
    %{
      id: ticket.id,
      beads_id: ticket.beads_id,
      title: ticket.title,
      description: ticket.description,
      status: ticket.status,
      priority: ticket.priority,
      issue_type: ticket.issue_type,
      assignee_id: ticket.assignee_id,
      assignee_name: ticket.assignee_name,
      parent_id: ticket.parent_id,
      project_id: ticket.project_id,
      beads_created_at: ticket.beads_created_at,
      beads_updated_at: ticket.beads_updated_at,
      beads_closed_at: ticket.beads_closed_at,
      synced_at: ticket.synced_at,
      inserted_at: ticket.inserted_at,
      updated_at: ticket.updated_at
    }
  end
end
