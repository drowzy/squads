defmodule Squads.Repo.Migrations.CreateBoardAndDropOldOrchestration do
  use Ecto.Migration

  def change do
    # Remove Loom/Fleet workflow tables (deprecated)
    drop_if_exists table(:fleet_step_sessions)
    drop_if_exists table(:fleet_steps)
    drop_if_exists table(:fleet_runs)

    # NOTE: Legacy ticket tables are intentionally left in place (unused).
    # SQLite does not support dropping columns, and older tables include foreign keys
    # that are not worth rebuilding for this transition.

    create table(:board_lane_assignments, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :project_id, references(:projects, type: :binary_id, on_delete: :delete_all),
        null: false

      add :squad_id, references(:squads, type: :binary_id, on_delete: :delete_all), null: false

      # todo|plan|build|review
      add :lane, :string, null: false

      add :agent_id, references(:agents, type: :binary_id, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    create unique_index(:board_lane_assignments, [:project_id, :squad_id, :lane])
    create index(:board_lane_assignments, [:project_id])
    create index(:board_lane_assignments, [:squad_id])

    create table(:board_cards, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :project_id, references(:projects, type: :binary_id, on_delete: :delete_all),
        null: false

      add :squad_id, references(:squads, type: :binary_id, on_delete: :delete_all), null: false

      # todo|plan|build|review
      add :lane, :string, null: false, default: "todo"
      add :position, :integer, null: false, default: 0

      add :title, :string
      add :body, :text, null: false

      # Artifacts
      add :prd_path, :string
      add :issue_plan, :map
      add :issue_refs, :map

      add :pr_url, :string
      add :pr_opened_at, :utc_datetime

      # Sessions per lane
      add :plan_agent_id, references(:agents, type: :binary_id, on_delete: :nilify_all)
      add :build_agent_id, references(:agents, type: :binary_id, on_delete: :nilify_all)
      add :review_agent_id, references(:agents, type: :binary_id, on_delete: :nilify_all)

      add :plan_session_id, references(:sessions, type: :binary_id, on_delete: :nilify_all)
      add :build_session_id, references(:sessions, type: :binary_id, on_delete: :nilify_all)
      add :review_session_id, references(:sessions, type: :binary_id, on_delete: :nilify_all)

      # Worktree info (for BUILD and REVIEW)
      add :build_worktree_name, :string
      add :build_worktree_path, :string
      add :build_branch, :string
      add :base_branch, :string

      # AI review + human review
      add :ai_review, :map
      add :ai_review_session_id, references(:sessions, type: :binary_id, on_delete: :nilify_all)

      add :human_review_status, :string
      add :human_review_feedback, :text
      add :human_reviewed_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create index(:board_cards, [:project_id])
    create index(:board_cards, [:squad_id])
    create index(:board_cards, [:lane])
  end
end
