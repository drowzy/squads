defmodule Squads.Repo.Migrations.CreateSquadMcpServers do
  use Ecto.Migration

  def change do
    create table(:squad_mcp_servers, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :squad_id, references(:squads, type: :binary_id, on_delete: :delete_all), null: false
      add :name, :string, null: false
      add :source, :string, null: false
      add :type, :string, null: false
      add :image, :string
      add :url, :string
      add :command, :string
      add :args, :map, default: %{}
      add :headers, :map, default: %{}
      add :enabled, :boolean, default: false, null: false
      add :status, :string, default: "unknown", null: false
      add :last_error, :text
      add :catalog_meta, :map, default: %{}
      add :tools, :map, default: %{}

      timestamps(type: :utc_datetime)
    end

    create unique_index(:squad_mcp_servers, [:squad_id, :name])
    create index(:squad_mcp_servers, [:squad_id, :enabled, :status])
  end
end
