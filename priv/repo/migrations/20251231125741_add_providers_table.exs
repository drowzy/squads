defmodule Squads.Repo.Migrations.AddProvidersTable do
  use Ecto.Migration

  def change do
    # Providers represent AI provider configurations from OpenCode
    create table(:providers, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :project_id, references(:projects, type: :binary_id, on_delete: :delete_all),
        null: false

      # Provider identification
      # e.g., "anthropic", "openai"
      add :provider_id, :string, null: false
      # e.g., "Anthropic", "OpenAI"
      add :name, :string, null: false

      # Connection status
      # connected, disconnected, error, unknown
      add :status, :string, default: "unknown"
      add :last_checked_at, :utc_datetime

      # Available models for this provider
      # [{id, name, default}]
      add :models, {:array, :map}, default: []

      # Default model for this provider
      add :default_model, :string

      # Raw provider data from OpenCode
      add :metadata, :map, default: %{}

      timestamps(type: :utc_datetime)
    end

    create index(:providers, [:project_id])
    create unique_index(:providers, [:project_id, :provider_id])
    create index(:providers, [:status])
  end
end
