defmodule SquadsWeb.API.ReviewJSON do
  @moduledoc false

  alias Squads.Reviews.Review
  alias Squads.Reviews.ReviewComment

  def index(%{reviews: reviews}) when is_list(reviews) do
    %{data: Enum.map(reviews, &review_summary/1)}
  end

  def show(%{review: review, diff: diff}) do
    %{data: review_detail(review, diff)}
  end

  def show(%{review: review}) do
    %{data: review_detail(review, review.diff)}
  end

  # --- Serializers ---

  defp review_summary(%Review{} = review) do
    %{
      id: review.id,
      title: review.title,
      summary: review.summary,
      status: review.status,
      author_name: review.author_name,
      author_type: review.author_type,
      project_ids: review.project_ids,
      workspace_root: review.workspace_root,
      files_changed: review.files_changed,
      inserted_at: review.inserted_at,
      updated_at: review.updated_at
    }
  end

  defp review_detail(%Review{} = review, diff) do
    %{
      id: review.id,
      title: review.title,
      summary: review.summary,
      highlights: review.highlights,
      status: review.status,
      diff: diff,
      diff_url: review.diff_url,
      worktree_path: review.worktree_path,
      base_sha: review.base_sha,
      head_sha: review.head_sha,
      files_changed: review.files_changed,
      project_ids: review.project_ids,
      workspace_root: review.workspace_root,
      references: review.references,
      author_type: review.author_type,
      author_name: review.author_name,
      author_id: review.author_id,
      session_id: review.session_id,
      comments: serialize_comments(review.comments),
      inserted_at: review.inserted_at,
      updated_at: review.updated_at
    }
  end

  defp serialize_comments(comments) when is_list(comments) do
    Enum.map(comments, &serialize_comment/1)
  end

  defp serialize_comments(_), do: []

  defp serialize_comment(%ReviewComment{} = comment) do
    %{
      id: comment.id,
      type: comment.type,
      body: comment.body,
      author_type: comment.author_type,
      author_name: comment.author_name,
      file_path: comment.file_path,
      line_number: comment.line_number,
      diff_side: comment.diff_side,
      before_context: comment.before_context,
      after_context: comment.after_context,
      inserted_at: comment.inserted_at
    }
  end
end
