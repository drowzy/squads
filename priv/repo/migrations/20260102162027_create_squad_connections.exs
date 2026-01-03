defmodule Squads.Repo.Migrations.CreateSquadConnections do
  use Ecto.Migration

  def change do
    create table(:squad_connections, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :from_squad_id, references(:squads, type: :binary_id, on_delete: :delete_all),
        null: false

      add :to_squad_id, references(:squads, type: :binary_id, on_delete: :delete_all), null: false
      add :status, :string, default: "active", null: false
      add :metadata, :map, default: %{}
      add :notes, :text

      timestamps(type: :utc_datetime)
    end

    create index(:squad_connections, [:from_squad_id])
    create index(:squad_connections, [:to_squad_id])
    create unique_index(:squad_connections, [:from_squad_id, :to_squad_id])
  end
end
