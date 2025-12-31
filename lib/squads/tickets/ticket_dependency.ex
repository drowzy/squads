defmodule Squads.Tickets.TicketDependency do
  @moduledoc """
  Represents a dependency relationship between two tickets.

  Supports Beads dependency types like "blocks", "parent-child", and "discovered-from".
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Squads.Tickets.Ticket

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @dependency_types ~w(blocks parent-child discovered-from relates-to)

  schema "ticket_dependencies" do
    field :dependency_type, :string, default: "blocks"

    belongs_to :ticket, Ticket
    belongs_to :dependency, Ticket

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(dep, attrs) do
    dep
    |> cast(attrs, [:ticket_id, :dependency_id, :dependency_type])
    |> validate_required([:ticket_id, :dependency_id])
    |> validate_inclusion(:dependency_type, @dependency_types)
    |> foreign_key_constraint(:ticket_id)
    |> foreign_key_constraint(:dependency_id)
    |> unique_constraint([:ticket_id, :dependency_id])
    |> validate_not_self_referential()
  end

  defp validate_not_self_referential(changeset) do
    ticket_id = get_field(changeset, :ticket_id)
    dependency_id = get_field(changeset, :dependency_id)

    if ticket_id && dependency_id && ticket_id == dependency_id do
      add_error(changeset, :dependency_id, "cannot depend on itself")
    else
      changeset
    end
  end
end
