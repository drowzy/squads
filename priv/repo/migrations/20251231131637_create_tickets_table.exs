defmodule Squads.Repo.Migrations.CreateTicketsTable do
  use Ecto.Migration

  def change do
    # Tickets mirror Beads issues with local metadata
    create table(:tickets, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :project_id, references(:projects, type: :binary_id, on_delete: :delete_all),
        null: false

      # Beads issue identity
      add :beads_id, :string, null: false
      add :title, :string, null: false
      add :description, :text

      # Issue metadata from Beads
      add :status, :string, null: false, default: "open"
      add :priority, :integer, default: 2
      add :issue_type, :string, default: "task"

      # Assignment (optional link to agent)
      add :assignee_id, references(:agents, type: :binary_id, on_delete: :nilify_all)
      add :assignee_name, :string

      # Parent/child relationship for epics
      add :parent_id, references(:tickets, type: :binary_id, on_delete: :nilify_all)

      # Beads timestamps
      add :beads_created_at, :utc_datetime
      add :beads_updated_at, :utc_datetime
      add :beads_closed_at, :utc_datetime

      # Last sync with Beads CLI
      add :synced_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:tickets, [:project_id, :beads_id])
    create index(:tickets, [:project_id])
    create index(:tickets, [:status])
    create index(:tickets, [:priority])
    create index(:tickets, [:assignee_id])
    create index(:tickets, [:parent_id])
    create index(:tickets, [:issue_type])

    # Dependencies table for ticket relationships
    create table(:ticket_dependencies, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :ticket_id, references(:tickets, type: :binary_id, on_delete: :delete_all), null: false

      add :dependency_id, references(:tickets, type: :binary_id, on_delete: :delete_all),
        null: false

      add :dependency_type, :string, null: false, default: "blocks"

      timestamps(type: :utc_datetime)
    end

    create unique_index(:ticket_dependencies, [:ticket_id, :dependency_id])
    create index(:ticket_dependencies, [:ticket_id])
    create index(:ticket_dependencies, [:dependency_id])
  end
end
