defmodule Squads.Sessions.TranscriptEntry do
  @moduledoc """
  A persisted transcript entry for an OpenCode session.

  We store the raw message payload (JSON map) as returned by OpenCode.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Squads.Sessions.Session

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "session_transcript_entries" do
    field :opencode_message_id, :string
    field :position, :integer
    field :role, :string
    field :payload, :map, default: %{}
    field :occurred_at, :utc_datetime

    belongs_to :session, Session

    timestamps(type: :utc_datetime)
  end

  @required_fields ~w(session_id opencode_message_id position payload)a
  @optional_fields ~w(role occurred_at)a

  def changeset(entry, attrs) do
    entry
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> foreign_key_constraint(:session_id)
    |> unique_constraint([:session_id, :opencode_message_id])
  end
end
