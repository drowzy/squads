defmodule Squads.MCP.Server do
  @moduledoc """
  Schema for squad-level MCP server configuration.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Squads.Squads.Squad

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @sources ~w(builtin registry custom)
  @types ~w(remote container)

  schema "squad_mcp_servers" do
    field :name, :string
    field :source, :string
    field :type, :string
    field :image, :string
    field :url, :string
    field :command, :string
    field :args, :map, default: %{}
    field :headers, :map, default: %{}
    field :enabled, :boolean, default: false
    field :status, :string, default: "unknown"
    field :last_error, :string
    field :catalog_meta, :map, default: %{}
    field :tools, :map, default: %{}

    belongs_to :squad, Squad

    timestamps(type: :utc_datetime)
  end

  @required_fields ~w(squad_id name source type)a
  @optional_fields ~w(image url command args headers enabled status last_error catalog_meta tools)a

  @doc false
  def changeset(server, attrs) do
    server
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_inclusion(:source, @sources)
    |> validate_inclusion(:type, @types)
    |> validate_length(:name, min: 1, max: 100)
    |> normalize_map_field(:args)
    |> normalize_map_field(:headers)
    |> normalize_map_field(:catalog_meta)
    |> normalize_map_field(:tools)
    |> foreign_key_constraint(:squad_id)
    |> unique_constraint([:squad_id, :name])
  end

  defp normalize_map_field(changeset, field) do
    case get_change(changeset, field, :__missing__) do
      :__missing__ -> changeset
      nil -> put_change(changeset, field, %{})
      _value -> changeset
    end
  end
end
