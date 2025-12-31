defmodule Squads.Reservations.FileReservation do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "file_reservations" do
    field :path_pattern, :string
    field :exclusive, :boolean, default: false
    field :reason, :string
    field :expires_at, :utc_datetime

    belongs_to :project, Squads.Projects.Project
    belongs_to :agent, Squads.Agents.Agent

    timestamps()
  end

  def changeset(reservation, attrs) do
    reservation
    |> cast(attrs, [:path_pattern, :exclusive, :reason, :expires_at, :project_id, :agent_id])
    |> validate_required([:path_pattern, :expires_at, :project_id, :agent_id])
  end
end
