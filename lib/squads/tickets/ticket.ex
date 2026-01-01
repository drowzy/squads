defmodule Squads.Tickets.Ticket do
  @moduledoc """
  A ticket mirrors a Beads issue in the local database.

  Tickets are synced from the Beads CLI and can be assigned to agents
  for work tracking. They maintain a reference to their Beads ID for
  bidirectional sync.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Squads.Projects.Project
  alias Squads.Agents.Agent
  alias Squads.Sessions.Session

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @statuses ~w(open in_progress blocked closed)
  @issue_types ~w(bug feature task epic chore)
  @priorities 0..4

  schema "tickets" do
    field :beads_id, :string
    field :title, :string
    field :description, :string
    field :status, :string, default: "open"
    field :priority, :integer, default: 2
    field :issue_type, :string, default: "task"
    field :assignee_name, :string
    field :beads_created_at, :utc_datetime
    field :beads_updated_at, :utc_datetime
    field :beads_closed_at, :utc_datetime
    field :synced_at, :utc_datetime

    belongs_to :project, Project
    belongs_to :assignee, Agent
    belongs_to :parent, __MODULE__
    has_many :children, __MODULE__, foreign_key: :parent_id
    has_many :ticket_dependencies, Squads.Tickets.TicketDependency
    has_many :dependencies, through: [:ticket_dependencies, :dependency]
    has_many :sessions, Session

    timestamps(type: :utc_datetime)
  end

  @required_fields ~w(beads_id title project_id)a
  @optional_fields ~w(description status priority issue_type assignee_id assignee_name parent_id beads_created_at beads_updated_at beads_closed_at synced_at)a

  @doc false
  def changeset(ticket, attrs) do
    ticket
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_inclusion(:status, @statuses)
    |> validate_inclusion(:issue_type, @issue_types)
    |> validate_inclusion(:priority, @priorities)
    |> foreign_key_constraint(:project_id)
    |> foreign_key_constraint(:assignee_id)
    |> foreign_key_constraint(:parent_id)
    |> unique_constraint([:project_id, :beads_id])
  end

  @doc """
  Changeset for syncing from Beads CLI data.
  """
  def sync_changeset(ticket, beads_data) do
    attrs = map_from_beads(beads_data)

    ticket
    |> changeset(attrs)
    |> put_change(:synced_at, DateTime.utc_now() |> DateTime.truncate(:second))
  end

  @doc """
  Maps Beads JSON data to ticket attributes.
  """
  def map_from_beads(data) when is_map(data) do
    %{
      beads_id: data["id"],
      title: data["title"],
      description: data["description"],
      status: normalize_status(data["status"]),
      priority: data["priority"] || 2,
      issue_type: data["issue_type"] || "task",
      assignee_name: data["assignee"],
      beads_created_at: parse_datetime(data["created_at"]),
      beads_updated_at: parse_datetime(data["updated_at"]),
      beads_closed_at: parse_datetime(data["closed_at"])
    }
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Map.new()
  end

  # Beads uses "open", "in_progress", "closed"
  # We also support "blocked"
  defp normalize_status(nil), do: "open"
  defp normalize_status(status) when status in @statuses, do: status
  defp normalize_status(_), do: "open"

  defp parse_datetime(nil), do: nil

  defp parse_datetime(str) when is_binary(str) do
    case DateTime.from_iso8601(str) do
      {:ok, dt, _offset} -> DateTime.truncate(dt, :second)
      _ -> nil
    end
  end

  defp parse_datetime(_), do: nil
end
