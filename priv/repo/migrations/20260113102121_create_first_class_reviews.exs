defmodule Squads.Repo.Migrations.CreateFirstClassReviews do
  use Ecto.Migration

  def change do
    # Drop old reviews table (was ticket-centric, not used)
    drop_if_exists table(:reviews)

    # Create first-class reviews table
    create table(:reviews, primary_key: false) do
      add :id, :binary_id, primary_key: true

      # Core fields
      add :status, :string, null: false, default: "pending"
      add :title, :string
      add :summary, :text
      add :highlights, :map, default: "[]"

      # Diff storage and context
      add :diff, :text
      add :diff_url, :string
      add :worktree_path, :string
      add :base_sha, :string
      add :head_sha, :string

      # Files changed: [{path, additions, deletions}, ...]
      add :files_changed, :map, default: "[]"

      # Project association (array for multi-project reviews)
      add :project_ids, :map, default: "[]"
      add :workspace_root, :string

      # Generic references (ticket_id, card_id, squad_id, etc.)
      add :references, :map, default: "{}"

      # Author tracking
      add :author_type, :string, default: "system"
      add :author_name, :string
      add :author_id, references(:agents, type: :binary_id, on_delete: :nilify_all)

      # Session association
      add :session_id, references(:sessions, type: :binary_id, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    create index(:reviews, [:status])
    create index(:reviews, [:author_id])
    create index(:reviews, [:session_id])

    # Review comments table
    create table(:review_comments, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :review_id, references(:reviews, type: :binary_id, on_delete: :delete_all), null: false

      # Comment type: summary, file, line
      add :type, :string, null: false

      # Content
      add :body, :text, null: false

      # Author tracking
      add :author_type, :string, null: false, default: "human"
      add :author_name, :string

      # Location (for file/line types)
      add :file_path, :string
      add :line_number, :integer
      add :diff_side, :string

      # Code context snippets (3 lines before/after)
      add :before_context, :text
      add :after_context, :text

      timestamps(type: :utc_datetime)
    end

    create index(:review_comments, [:review_id])
    create index(:review_comments, [:type])
    create index(:review_comments, [:file_path])
  end
end
