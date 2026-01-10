defmodule Squads.Sessions.Session do
  @moduledoc """
  A session represents an OpenCode session instance.

  Sessions track work performed by an agent, including worktree paths,
  branch names, and execution status.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Squads.Agents.Agent
  alias Squads.Events.Event

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @statuses ~w(pending running paused completed failed cancelled archived)

  schema "sessions" do
    field :opencode_session_id, :string
    field :ticket_key, :string
    field :status, :string, default: "pending"
    field :worktree_path, :string
    field :branch, :string
    field :started_at, :utc_datetime
    field :finished_at, :utc_datetime
    field :exit_code, :integer
    field :metadata, :map, default: %{}

    belongs_to :agent, Agent
    has_one :squad, through: [:agent, :squad]
    has_one :project, through: [:agent, :squad, :project]
    has_many :events, Event

    timestamps(type: :utc_datetime)
  end

  @required_fields ~w(agent_id)a
  @optional_fields ~w(opencode_session_id ticket_key status worktree_path branch started_at finished_at exit_code metadata)a

  @doc false
  def changeset(session, attrs) do
    session
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_inclusion(:status, @statuses)
    |> foreign_key_constraint(:agent_id)
  end

  @doc """
  Marks a session as started.
  """
  def start_changeset(session, attrs \\ %{}) do
    session
    |> cast(attrs, [:opencode_session_id, :worktree_path, :branch, :metadata])
    |> put_change(:status, "running")
    |> put_change(:started_at, DateTime.utc_now() |> DateTime.truncate(:second))
  end

  @doc """
  Marks a session as completed or failed.
  """
  def finish_changeset(session, exit_code) do
    status = if exit_code == 0, do: "completed", else: "failed"

    session
    |> change(%{
      status: status,
      exit_code: exit_code,
      finished_at: DateTime.utc_now() |> DateTime.truncate(:second)
    })
  end
end
