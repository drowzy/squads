defmodule Squads.Squads.Squad do
  @moduledoc """
  A squad groups agents working on related tickets.

  Squads provide organizational context and can be used to coordinate
  work on specific features or areas of the codebase.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Squads.Projects.Project
  alias Squads.Agents.Agent

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @type t :: %__MODULE__{
          id: Ecto.UUID.t(),
          name: String.t(),
          description: String.t() | nil,
          project_id: Ecto.UUID.t(),
          opencode_status: atom(),
          project: Project.t() | Ecto.Association.NotLoaded.t(),
          agents: [Agent.t()] | Ecto.Association.NotLoaded.t(),
          inserted_at: DateTime.t(),
          updated_at: DateTime.t()
        }

  schema "squads" do
    field :name, :string
    field :description, :string
    field :opencode_status, :any, virtual: true, default: :idle

    belongs_to :project, Project
    has_many :agents, Agent

    timestamps(type: :utc_datetime)
  end

  @required_fields ~w(name project_id)a
  @optional_fields ~w(description)a

  @doc false
  def changeset(squad, attrs) do
    squad
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_length(:name, min: 1, max: 100)
    |> foreign_key_constraint(:project_id)
  end
end
