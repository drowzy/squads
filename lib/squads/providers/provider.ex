defmodule Squads.Providers.Provider do
  @moduledoc """
  A Provider represents an AI provider configuration from OpenCode.

  Providers track connection status, available models, and configuration
  for each AI backend (Anthropic, OpenAI, etc.).
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Squads.Projects.Project

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @statuses ~w(connected disconnected error unknown)

  schema "providers" do
    field :provider_id, :string
    field :name, :string
    field :status, :string, default: "unknown"
    field :last_checked_at, :utc_datetime
    field :models, {:array, :map}, default: []
    field :default_model, :string
    field :metadata, :map, default: %{}

    belongs_to :project, Project

    timestamps(type: :utc_datetime)
  end

  @required_fields ~w(project_id provider_id name)a
  @optional_fields ~w(status last_checked_at models default_model metadata)a

  @doc false
  def changeset(provider, attrs) do
    provider
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_inclusion(:status, @statuses)
    |> unique_constraint([:project_id, :provider_id])
    |> foreign_key_constraint(:project_id)
  end

  @doc """
  Changeset for updating provider status from a sync.
  """
  def sync_changeset(provider, attrs) do
    provider
    |> cast(attrs, [:status, :models, :default_model, :last_checked_at, :metadata])
    |> put_change(:last_checked_at, DateTime.utc_now() |> DateTime.truncate(:second))
  end

  @doc """
  Returns valid status values.
  """
  def statuses, do: @statuses
end
