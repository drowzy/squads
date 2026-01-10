defmodule Squads.Board.Card do
  use Ecto.Schema

  import Ecto.Changeset

  alias Squads.Projects.Project
  alias Squads.Squads.Squad
  alias Squads.Agents.Agent
  alias Squads.Sessions.Session

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @lanes ~w(todo plan build review done)
  @human_review_statuses ~w(pending approved changes_requested)

  schema "board_cards" do
    field :lane, :string, default: "todo"
    field :position, :integer, default: 0

    field :title, :string
    field :body, :string

    field :prd_path, :string

    field :issue_plan, :map
    field :issue_refs, :map

    field :pr_url, :string
    field :pr_opened_at, :utc_datetime

    belongs_to :project, Project
    belongs_to :squad, Squad

    belongs_to :plan_agent, Agent
    belongs_to :build_agent, Agent
    belongs_to :review_agent, Agent

    belongs_to :plan_session, Session
    belongs_to :build_session, Session
    belongs_to :review_session, Session

    field :build_worktree_name, :string
    field :build_worktree_path, :string
    field :build_branch, :string
    field :base_branch, :string

    field :ai_review, :map
    belongs_to :ai_review_session, Session

    field :human_review_status, :string
    field :human_review_feedback, :string
    field :human_reviewed_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end

  @required_fields ~w(project_id squad_id body lane)a

  @optional_fields ~w(position title prd_path issue_plan issue_refs pr_url pr_opened_at plan_agent_id build_agent_id review_agent_id plan_session_id build_session_id review_session_id build_worktree_name build_worktree_path build_branch base_branch ai_review ai_review_session_id human_review_status human_review_feedback human_reviewed_at)a

  def changeset(card, attrs) do
    card
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_inclusion(:lane, @lanes)
    |> validate_inclusion(:human_review_status, @human_review_statuses)
    |> foreign_key_constraint(:project_id)
    |> foreign_key_constraint(:squad_id)
    |> foreign_key_constraint(:plan_agent_id)
    |> foreign_key_constraint(:build_agent_id)
    |> foreign_key_constraint(:review_agent_id)
    |> foreign_key_constraint(:plan_session_id)
    |> foreign_key_constraint(:build_session_id)
    |> foreign_key_constraint(:review_session_id)
    |> foreign_key_constraint(:ai_review_session_id)
  end
end
