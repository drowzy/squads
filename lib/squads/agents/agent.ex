defmodule Squads.Agents.Agent do
  @moduledoc """
  An agent is a named worker in the Squads system.

  Agents use curated AdjectiveNoun names (e.g., GreenPanda, BlueRock)
  with slug forms for paths and branch names.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Squads.Agents.Roles
  alias Squads.Squads.Squad
  alias Squads.Sessions.Session
  alias Squads.Events.Event
  alias Squads.Tickets.Ticket

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @statuses ~w(idle working blocked offline)

  schema "agents" do
    field :name, :string
    field :slug, :string
    field :model, :string
    field :role, :string, default: "fullstack_engineer"
    field :level, :string, default: "senior"
    field :system_instruction, :string
    field :status, :string, default: "idle"

    belongs_to :squad, Squad
    belongs_to :mentor, Squads.Agents.Agent
    has_many :mentees, Squads.Agents.Agent, foreign_key: :mentor_id
    has_many :sessions, Session
    has_many :events, Event
    has_many :assigned_tickets, Ticket, foreign_key: :assignee_id

    timestamps(type: :utc_datetime)
  end

  @required_fields ~w(name slug squad_id role level)a
  @optional_fields ~w(model system_instruction status mentor_id)a

  @doc false
  def changeset(agent, attrs) do
    agent
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_inclusion(:role, Roles.role_ids())
    |> validate_inclusion(:level, Roles.level_ids())
    |> validate_inclusion(:status, @statuses)
    |> validate_name_format()
    |> validate_slug_format()
    |> foreign_key_constraint(:squad_id)
    |> unique_constraint([:squad_id, :slug])
  end

  defp validate_name_format(changeset) do
    validate_format(changeset, :name, ~r/^[A-Z][a-z]+[A-Z][a-z]+$/,
      message: "must be AdjectiveNoun format (e.g., GreenPanda)"
    )
  end

  defp validate_slug_format(changeset) do
    validate_format(changeset, :slug, ~r/^[a-z]+-[a-z]+$/,
      message: "must be lowercase hyphenated (e.g., green-panda)"
    )
  end
end
