defmodule Squads.Repo.Migrations.CreateFileReservations do
  use Ecto.Migration

  def change do
    create table(:file_reservations, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :project_id, references(:projects, on_delete: :delete_all, type: :binary_id),
        null: false

      add :agent_id, references(:agents, on_delete: :delete_all, type: :binary_id), null: false
      add :path_pattern, :string, null: false
      add :exclusive, :boolean, default: false, null: false
      add :reason, :text
      add :expires_at, :utc_datetime, null: false

      timestamps()
    end

    create index(:file_reservations, [:project_id])
    create index(:file_reservations, [:agent_id])
    create index(:file_reservations, [:expires_at])
  end
end
