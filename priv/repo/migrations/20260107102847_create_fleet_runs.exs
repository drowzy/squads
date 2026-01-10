defmodule Squads.Repo.Migrations.CreateFleetRuns do
  use Ecto.Migration

  def change do
    create table(:fleet_runs, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :project_id, references(:projects, type: :binary_id, on_delete: :delete_all),
        null: false

      add :workflow_path, :string, null: false
      add :status, :string, null: false, default: "queued"

      add :inputs, :map, default: %{}
      add :output, :map
      add :error, :map

      add :started_at, :utc_datetime
      add :finished_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create index(:fleet_runs, [:project_id])
    create index(:fleet_runs, [:status])

    create table(:fleet_steps, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :run_id, references(:fleet_runs, type: :binary_id, on_delete: :delete_all), null: false

      add :task_name, :string, null: false
      add :task_pointer, :string
      add :task_kind, :string
      add :position, :integer

      add :status, :string, null: false, default: "queued"

      add :output, :map
      add :error, :map

      add :started_at, :utc_datetime
      add :finished_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create index(:fleet_steps, [:run_id])
    create index(:fleet_steps, [:status])
    create unique_index(:fleet_steps, [:run_id, :task_name])
  end
end
