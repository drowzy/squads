defmodule Squads.Events.Event do
  @moduledoc """
  An append-only event log for traceability.

  Events track all significant actions in the system including agent activity,
  session lifecycle, and integration events.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Squads.Projects.Project
  alias Squads.Sessions.Session
  alias Squads.Agents.Agent

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @event_kinds ~w(
    agent.created agent.status_changed
    session.started session.paused session.resumed session.completed session.failed session.cancelled
    ticket.assigned ticket.started ticket.completed
    mail.received mail.sent mail.read mail.acknowledged
    reservation.acquired reservation.released
    file_reserved file_released
    worktree.created worktree.deleted
    pr.created pr.merged pr.closed
    session.status_changed session.tool_started session.tool_completed
    squad.connected squad.disconnected
    fleet.run_event
  )

  schema "events" do
    field :kind, :string
    field :payload, :map, default: %{}
    field :occurred_at, :utc_datetime

    belongs_to :project, Project
    belongs_to :session, Session
    belongs_to :agent, Agent

    # No timestamps - events use occurred_at instead
  end

  @required_fields ~w(kind project_id)a
  @optional_fields ~w(payload session_id agent_id occurred_at)a

  @doc false
  def changeset(event, attrs) do
    event
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_inclusion(:kind, @event_kinds)
    |> put_occurred_at()
    |> foreign_key_constraint(:project_id)
    |> foreign_key_constraint(:session_id)
    |> foreign_key_constraint(:agent_id)
  end

  defp put_occurred_at(changeset) do
    case get_field(changeset, :occurred_at) do
      nil -> put_change(changeset, :occurred_at, DateTime.utc_now() |> DateTime.truncate(:second))
      _ -> changeset
    end
  end

  @doc """
  Returns the list of valid event kinds.
  """
  def kinds, do: @event_kinds
end
