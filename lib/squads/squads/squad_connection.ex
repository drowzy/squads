defmodule Squads.Squads.SquadConnection do
  @moduledoc """
  Represents a connection between two squads, potentially across projects.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Squads.Squads.Squad

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @type t :: %__MODULE__{
          id: Ecto.UUID.t(),
          from_squad_id: Ecto.UUID.t(),
          from_squad: Squad.t() | Ecto.Association.NotLoaded.t(),
          to_squad_id: Ecto.UUID.t(),
          to_squad: Squad.t() | Ecto.Association.NotLoaded.t(),
          status: String.t(),
          metadata: map(),
          notes: String.t() | nil,
          inserted_at: DateTime.t(),
          updated_at: DateTime.t()
        }

  schema "squad_connections" do
    field :status, :string, default: "active"
    field :metadata, :map, default: %{}
    field :notes, :string

    belongs_to :from_squad, Squad
    belongs_to :to_squad, Squad

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(squad_connection, attrs) do
    squad_connection
    |> cast(attrs, [:from_squad_id, :to_squad_id, :status, :metadata, :notes])
    |> validate_required([:from_squad_id, :to_squad_id])
    |> validate_inclusion(:status, ["active", "disabled"])
    |> unique_constraint([:from_squad_id, :to_squad_id])
    |> check_constraint(:from_squad_id,
      name: :different_squads,
      message: "cannot connect to itself"
    )
  end
end
