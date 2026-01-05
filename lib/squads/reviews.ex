defmodule Squads.Reviews do
  @moduledoc """
  Context for managing code reviews with mentor-based reviewer assignment.
  """
  import Ecto.Query, warn: false

  alias Squads.Repo
  alias Squads.Reviews.Review
  alias Squads.Agents.Agent, as: AgentModel

  @doc """
  Creates a review for a ticket, generating a summary from the associated worktree if available.
  """
  def request_review(project_id, author_id, ticket_id, worktree_name) do
    with {:ok, summary_data} <- Squads.Worktrees.generate_pr_summary(project_id, worktree_name),
         {:ok, reviewer_id} <- suggest_reviewer(author_id),
         {:ok, review} <-
           create_review(%{
             project_id: project_id,
             author_id: author_id,
             ticket_id: ticket_id,
             reviewer_id: reviewer_id,
             summary: summary_data.summary,
             status: "pending",
             metadata: %{
               test_results: summary_data.test_results,
               generated_at: summary_data.generated_at
             }
           }) do
      # Notify reviewer
      if reviewer_id do
        Squads.Mail.send_message(%{
          project_id: project_id,
          sender_id: author_id,
          subject: "Review Request: #{ticket_id}",
          body_md:
            "Please review my changes for #{ticket_id}.\n\nSummary:\n#{summary_data.summary}",
          importance: "normal",
          ack_required: true,
          to: [reviewer_id]
        })
      end

      {:ok, review}
    end
  end

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
  def get_review(id) do
    Review
    |> Repo.get(id)
    |> Repo.preload([:ticket, :author, :reviewer])
  end

  @doc """
  Fetches a review by ID with a tuple result.
  """
  def fetch_review(id) do
    case get_review(id) do
      nil -> {:error, :not_found}
      review -> {:ok, review}
    end
  end

  @doc """
  Gets a review by ID, raising if not found.
  """
  def get_review!(id) do
    case get_review(id) do
      nil -> raise Ecto.NoResultsError, queryable: Review
      review -> review
    end
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
  Approves a review, and if successful, triggers worktree cleanup for the ticket.
  """
  def approve_review(review) do
    review = Repo.preload(review, [:ticket, author: :squad])

    with {:ok, updated} <- Review.approve(review) do
      # Notify author
      Squads.Mail.send_message(%{
        project_id: review.ticket.project_id,
        sender_id: updated.reviewer_id,
        subject: "Review Approved: #{updated.ticket_id}",
        body_md: "Your changes have been approved. You can now merge.",
        to: [updated.author_id]
      })

      # Cleanup worktree
      if review.author && review.author.squad do
        worktree_name = "#{review.author.slug}-#{review.ticket.id}"
        Squads.Worktrees.merge_and_cleanup(review.author.squad.project_id, worktree_name)
      end

      {:ok, updated}
    end
  end

  @doc """
  Requests changes on a review.
  """
  def request_changes(review, summary) do
    review = Repo.preload(review, :ticket)

    with {:ok, updated} <-
           review
           |> Ecto.Changeset.change()
           |> Ecto.Changeset.put_change(:summary, summary)
           |> Ecto.Changeset.put_change(:status, "changes_requested")
           |> Repo.update() do
      # Notify author
      Squads.Mail.send_message(%{
        project_id: review.ticket.project_id,
        sender_id: updated.reviewer_id,
        subject: "Changes Requested: #{updated.ticket_id}",
        body_md: "Reviewer has requested changes:\n\n#{summary}",
        to: [updated.author_id]
      })

      {:ok, updated}
    end
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
