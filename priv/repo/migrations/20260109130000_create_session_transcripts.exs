defmodule Squads.Repo.Migrations.CreateSessionTranscripts do
  use Ecto.Migration

  def change do
    create table(:session_transcript_entries, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :session_id, references(:sessions, type: :binary_id, on_delete: :delete_all),
        null: false

      add :opencode_message_id, :string, null: false
      add :position, :integer, null: false

      add :role, :string
      add :payload, :map, default: %{}, null: false
      add :occurred_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create index(:session_transcript_entries, [:session_id])
    create index(:session_transcript_entries, [:session_id, :position])
    create index(:session_transcript_entries, [:occurred_at])
    create index(:session_transcript_entries, [:role])

    create unique_index(:session_transcript_entries, [:session_id, :opencode_message_id])

    create table(:fleet_step_sessions, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :fleet_step_id, references(:fleet_steps, type: :binary_id, on_delete: :delete_all),
        null: false

      add :session_id, references(:sessions, type: :binary_id, on_delete: :delete_all),
        null: false

      timestamps(type: :utc_datetime)
    end

    create index(:fleet_step_sessions, [:fleet_step_id])
    create index(:fleet_step_sessions, [:session_id])
    create unique_index(:fleet_step_sessions, [:fleet_step_id, :session_id])
  end
end
