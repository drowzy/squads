defmodule Squads.Reviews.Review do
  @moduledoc """
  First-class Review schema.

  A review captures a diff (committed or uncommitted) with summary,
  highlights, and associated comments. Reviews can span multiple projects.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Squads.Agents.Agent
  alias Squads.Sessions.Session
  alias Squads.Reviews.ReviewComment

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @statuses ~w(pending approved changes_requested)
  @author_types ~w(agent human system)

  schema "reviews" do
    field :status, :string, default: "pending"
    field :title, :string
    field :summary, :string
    field :highlights, {:array, :string}, default: []

    # Diff storage
    field :diff, :string
    field :diff_url, :string

    # Git context for diff recomputation
    field :worktree_path, :string
    field :base_sha, :string
    field :head_sha, :string

    # Files changed: [%{path: "...", additions: n, deletions: n}, ...]
    field :files_changed, {:array, :map}, default: []

    # Multi-project support
    field :project_ids, {:array, :binary_id}, default: []
    field :workspace_root, :string

    # Generic references (ticket_id, card_id, squad_id, etc.)
    field :references, :map, default: %{}

    # Author tracking
    field :author_type, :string, default: "system"
    field :author_name, :string
    belongs_to :author, Agent

    # Session association
    belongs_to :session, Session

    # Comments
    has_many :comments, ReviewComment

    timestamps(type: :utc_datetime)
  end

  @required_fields ~w()a
  @optional_fields ~w(
    status title summary highlights diff diff_url
    worktree_path base_sha head_sha files_changed
    project_ids workspace_root references
    author_type author_name author_id session_id
  )a

  def changeset(review, attrs) do
    review
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_inclusion(:status, @statuses)
    |> validate_inclusion(:author_type, @author_types)
    |> foreign_key_constraint(:author_id)
    |> foreign_key_constraint(:session_id)
  end

  def statuses, do: @statuses
  def author_types, do: @author_types
end
