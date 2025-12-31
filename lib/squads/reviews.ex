defmodule Squads.Reviews do
  @moduledoc """
  Context for managing code reviews with mentor-based reviewer assignment.
  """
  import Ecto.Query, warn: false

  alias Squads.Repo
  alias Squads.Reviews.Review
  alias Squads.Agents.Agent, as: AgentModel

  @doc """
  Lists all reviews for a ticket.
  """
  def list_reviews_for_ticket(ticket_id) do
    Review
    |> where([r], r.ticket_id == ^ticket_id)
    |> order_by([r], desc: r.inserted_at)
    |> preload([:author, :reviewer])
    |> Repo.all()
  end

  @doc """
  Gets a review by ID.
  """
  def get_review!(id) do
    Review
    |> Repo.get!(id)
    |> Repo.preload([:ticket, :author, :reviewer])
  end

  @doc """
  Creates a review with mentor-based reviewer assignment.
  If author has a mentor, assigns mentor as reviewer. Otherwise requires explicit reviewer_id.
  """
  def create_review(attrs) do
    attrs = Map.put(attrs, :status, "pending")

    %Review{}
    |> Review.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Starts review (moves from pending to in_review).
  """
  def start_review(review) do
    Review.update_status(review, "in_review")
  end

  @doc """
  Approves a review.
  """
  def approve_review(review) do
    Review.approve(review)
  end

  @doc """
  Requests changes on a review.
  """
  def request_changes(review, summary) do
    review
    |> Ecto.Changeset.change()
    |> Ecto.Changeset.put_change(:summary, summary)
    |> Ecto.Changeset.put_change(:status, "changes_requested")
    |> Repo.update()
  end

  @doc """
  Gets pending reviews for a reviewer.
  """
  def pending_reviews_for_reviewer(reviewer_id) do
    Review
    |> where([r], r.reviewer_id == ^reviewer_id)
    |> where([r], r.status in ["pending", "in_review"])
    |> order_by([r], asc: r.inserted_at)
    |> preload([:ticket, :author])
    |> Repo.all()
  end

  @doc """
  Gets reviews authored by an agent.
  """
  def reviews_by_author(author_id) do
    Review
    |> where([r], r.author_id == ^author_id)
    |> order_by([r], desc: r.inserted_at)
    |> preload([:ticket, :reviewer])
    |> Repo.all()
  end

  @doc """
  Suggests a reviewer for a ticket based on mentor mapping.
  Returns mentor_id if author has one, otherwise nil.
  """
  def suggest_reviewer(author_id) do
    author = Repo.get(AgentModel, author_id)

    if author && author.mentor_id do
      {:ok, author.mentor_id}
    else
      {:ok, nil}
    end
  end
end
