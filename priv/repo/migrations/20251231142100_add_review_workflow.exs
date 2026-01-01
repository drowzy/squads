defmodule Squads.Repo.Migrations.AddReviewWorkflow do
  use Ecto.Migration

  def change do
    # Add mentor_id to agents for mentor mapping
    alter table(:agents, primary_key: false) do
      add :mentor_id, references(:agents, type: :binary_id, on_delete: :nilify_all)
    end

    create index(:agents, [:mentor_id])

    # Reviews table for review workflow
    create table(:reviews, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :ticket_id, references(:tickets, type: :binary_id, on_delete: :delete_all), null: false

      add :author_id, references(:agents, type: :binary_id, on_delete: :nilify_all), null: false

      add :reviewer_id, references(:agents, type: :binary_id, on_delete: :nilify_all), null: false

      add :status, :string, null: false, default: "pending"

      add :summary, :text
      add :diff_url, :string

      timestamps(type: :utc_datetime)
    end

    create index(:reviews, [:ticket_id])
    create index(:reviews, [:author_id])
    create index(:reviews, [:reviewer_id])
    create index(:reviews, [:status])
  end
end
