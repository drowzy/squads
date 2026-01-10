defmodule Squads.Repo.Migrations.MigrateTicketsToGithubIssues do
  use Ecto.Migration

  def change do
    drop_if_exists index(:tickets, [:project_id, :beads_id])

    alter table(:tickets) do
      # Remove Beads fields
      remove :beads_id, :string
      remove :beads_created_at, :utc_datetime
      remove :beads_updated_at, :utc_datetime
      remove :beads_closed_at, :utc_datetime

      # GitHub issue identity
      add :github_repo, :string, null: false
      add :github_issue_number, :integer, null: false
      add :github_issue_url, :text

      # GitHub timestamps
      add :github_created_at, :utc_datetime
      add :github_updated_at, :utc_datetime
      add :github_closed_at, :utc_datetime
    end

    create unique_index(:tickets, [:project_id, :github_repo, :github_issue_number])
    create index(:tickets, [:github_repo])
    create index(:tickets, [:github_issue_number])
  end
end
