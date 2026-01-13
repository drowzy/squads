defmodule SquadsWeb.API.FsReviewJSON do
  @moduledoc false

  alias Squads.Artifacts.Review

  def index(%{reviews: reviews}) do
    %{data: reviews}
  end

  def show(%{review: %Review{} = review, diff: diff, diff_error: diff_error}) do
    %{
      data: %{
        review: Review.to_storage_map(review),
        diff: diff,
        diff_error: diff_error
      }
    }
  end

  def create(%{review: %Review{} = review}) do
    %{data: review_card(review)}
  end

  def submit(%{review: %Review{} = review}) do
    %{data: review_card(review)}
  end

  defp review_card(%Review{} = review) do
    %{
      id: review.id,
      path: review.path,
      title: review.title,
      status: review.status
    }
  end
end
