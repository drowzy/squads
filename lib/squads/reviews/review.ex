defmodule Squads.Reviews.Review do
  @moduledoc """
  Reviews track code review workflow for tickets.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Squads.Repo
  alias Squads.Tickets.Ticket
  alias Squads.Agents.Agent

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @statuses ~w(pending in_review approved changes_requested)

  schema "reviews" do
    field :status, :string, default: "pending"
    field :summary, :string
    field :diff_url, :string

    belongs_to :ticket, Ticket
    belongs_to :author, Agent, foreign_key: :author_id
    belongs_to :reviewer, Agent, foreign_key: :reviewer_id

    timestamps(type: :utc_datetime)
  end

  @required_fields ~w(ticket_id author_id reviewer_id)a
  @optional_fields ~w(status summary diff_url)a

  @doc false
  def changeset(review, attrs) do
    review
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_inclusion(:status, @statuses)
    |> foreign_key_constraint(:ticket_id)
    |> foreign_key_constraint(:author_id)
    |> foreign_key_constraint(:reviewer_id)
  end

  @doc """
  Creates a review for a ticket, assigning the author and auto-assigning a reviewer.
  """
  def create_review(attrs) do
    %__MODULE__{}
    |> changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates the review status.
  """
  def update_status(review, new_status) when new_status in @statuses do
    review
    |> change(status: new_status)
    |> Repo.update()
  end

  @doc """
  Marks a review as approved.
  """
  def approve(review) do
    update_status(review, "approved")
  end

  @doc """
  Marks a review as changes_requested.
  """
  def request_changes(review) do
    update_status(review, "changes_requested")
  end
end
