defmodule Squads.Repo.Migrations.CreateCoreTables do
  use Ecto.Migration

  def change do
    # Projects represent a target codebase (identified by path)
    create table(:projects, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :path, :string, null: false
      add :name, :string, null: false
      add :config, :map, default: %{}

      timestamps(type: :utc_datetime)
    end

    create unique_index(:projects, [:path])

    # Squads group agents working on related tickets
    create table(:squads, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :project_id, references(:projects, type: :binary_id, on_delete: :delete_all),
        null: false

      add :name, :string, null: false
      add :description, :text

      timestamps(type: :utc_datetime)
    end

    create index(:squads, [:project_id])

    # Agents are named workers (AdjectiveNoun style)
    create table(:agents, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :squad_id, references(:squads, type: :binary_id, on_delete: :delete_all), null: false
      add :name, :string, null: false
      add :slug, :string, null: false
      add :model, :string
      add :status, :string, default: "idle"

      timestamps(type: :utc_datetime)
    end

    create index(:agents, [:squad_id])
    create unique_index(:agents, [:squad_id, :slug])

    # Sessions represent OpenCode session instances
    create table(:sessions, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :agent_id, references(:agents, type: :binary_id, on_delete: :delete_all), null: false
      add :opencode_session_id, :string
      add :ticket_key, :string
      add :status, :string, default: "pending"
      add :worktree_path, :string
      add :branch, :string
      add :started_at, :utc_datetime
      add :finished_at, :utc_datetime
      add :exit_code, :integer
      add :metadata, :map, default: %{}

      timestamps(type: :utc_datetime)
    end

    create index(:sessions, [:agent_id])
    create index(:sessions, [:ticket_key])
    create index(:sessions, [:status])

    # Events are append-only log entries for traceability
    create table(:events, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :project_id, references(:projects, type: :binary_id, on_delete: :delete_all),
        null: false

      add :session_id, references(:sessions, type: :binary_id, on_delete: :nilify_all)
      add :agent_id, references(:agents, type: :binary_id, on_delete: :nilify_all)
      add :kind, :string, null: false
      add :payload, :map, default: %{}

      add :occurred_at, :utc_datetime, null: false
    end

    create index(:events, [:project_id])
    create index(:events, [:session_id])
    create index(:events, [:agent_id])
    create index(:events, [:kind])
    create index(:events, [:occurred_at])
  end
end
