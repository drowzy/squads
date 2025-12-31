defmodule Squads.Projects.Project do
  @moduledoc """
  Represents a target codebase managed by Squads.

  A project is identified by its filesystem path and contains configuration
  for orchestration, agent naming, and integration settings.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Squads.Squads.Squad
  alias Squads.Events.Event
  alias Squads.Tickets.Ticket

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "projects" do
    field :path, :string
    field :name, :string
    field :config, :map, default: %{}

    has_many :squads, Squad
    has_many :events, Event
    has_many :tickets, Ticket

    timestamps(type: :utc_datetime)
  end

  @required_fields ~w(path name)a
  @optional_fields ~w(config)a

  @doc false
  def changeset(project, attrs) do
    project
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_path()
    |> unique_constraint(:path)
  end

  defp validate_path(changeset) do
    validate_change(changeset, :path, fn :path, path ->
      if String.starts_with?(path, "/") do
        []
      else
        [path: "must be an absolute path"]
      end
    end)
  end
end
