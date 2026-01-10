defmodule Squads.Board.LaneAssignment do
  use Ecto.Schema

  import Ecto.Changeset

  alias Squads.Projects.Project
  alias Squads.Squads.Squad
  alias Squads.Agents.Agent

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @lanes ~w(todo plan build review)

  schema "board_lane_assignments" do
    field :lane, :string

    belongs_to :project, Project
    belongs_to :squad, Squad
    belongs_to :agent, Agent

    timestamps(type: :utc_datetime)
  end

  @required_fields ~w(project_id squad_id lane)a
  @optional_fields ~w(agent_id)a

  def changeset(assignment, attrs) do
    assignment
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_inclusion(:lane, @lanes)
    |> foreign_key_constraint(:project_id)
    |> foreign_key_constraint(:squad_id)
    |> foreign_key_constraint(:agent_id)
    |> unique_constraint([:project_id, :squad_id, :lane])
  end
end
