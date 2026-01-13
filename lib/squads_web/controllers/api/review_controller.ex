defmodule SquadsWeb.API.ReviewController do
  @moduledoc false

  use SquadsWeb, :controller

  alias Squads.Reviews

  action_fallback SquadsWeb.FallbackController

  def index(conn, params) do
    opts = build_filter_opts(params)
    reviews = Reviews.list_reviews(opts)
    render(conn, :index, reviews: reviews)
  end

  def show(conn, %{"id" => id}) do
    with {:ok, uuid} <- Ecto.UUID.cast(id),
         {:ok, review} <- Reviews.get_review(uuid) do
      # Compute diff for display (may recompute for uncommitted changes)
      diff = compute_display_diff(review)
      render(conn, :show, review: review, diff: diff)
    else
      :error -> {:error, :not_found}
      {:error, :not_found} -> {:error, :not_found}
    end
  end

  def submit(conn, %{"id" => id, "status" => status} = params) do
    feedback = Map.get(params, "feedback", "")

    with {:ok, uuid} <- Ecto.UUID.cast(id),
         {:ok, review} <- Reviews.submit_review(uuid, status, feedback) do
      diff = compute_display_diff(review)
      render(conn, :show, review: review, diff: diff)
    else
      :error -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  # --- Helpers ---

  defp build_filter_opts(params) do
    []
    |> maybe_add_opt(:project_id, params["project_id"])
    |> maybe_add_opt(:workspace_root, params["workspace_root"])
    |> maybe_add_opt(:status, params["status"])
  end

  defp maybe_add_opt(opts, _key, nil), do: opts
  defp maybe_add_opt(opts, _key, ""), do: opts

  defp maybe_add_opt(opts, :project_id, value) do
    case Ecto.UUID.cast(value) do
      {:ok, uuid} -> [{:project_id, uuid} | opts]
      :error -> opts
    end
  end

  defp maybe_add_opt(opts, key, value), do: [{key, value} | opts]

  defp compute_display_diff(review) do
    case Reviews.compute_diff(review) do
      {:ok, diff} -> diff
      _ -> review.diff || ""
    end
  end
end
