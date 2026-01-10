defmodule SquadsWeb.API.ReviewController do
  @moduledoc false

  use SquadsWeb, :controller

  alias Squads.Reviews

  action_fallback SquadsWeb.FallbackController

  def index(conn, params) do
    project_id = params["project_id"]

    with {:ok, uuid} <- Ecto.UUID.cast(project_id) do
      reviews = Reviews.list_reviews(uuid)
      render(conn, :index, reviews: reviews)
    else
      :error ->
        {:error, :not_found}

      nil ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "missing_project_id", message: "project_id is required"})
    end
  end

  def show(conn, %{"id" => id}) do
    with {:ok, uuid} <- Ecto.UUID.cast(id),
         {:ok, review} <- Reviews.get_review(uuid) do
      render(conn, :show, review: review)
    else
      :error -> {:error, :not_found}
      {:error, :not_found} -> {:error, :not_found}
    end
  end

  def submit(conn, %{"id" => id, "status" => status} = params) do
    feedback = Map.get(params, "feedback", "")

    with {:ok, uuid} <- Ecto.UUID.cast(id),
         {:ok, _card} <- Reviews.submit_review(uuid, status, feedback),
         {:ok, review} <- Reviews.get_review(uuid) do
      render(conn, :show, review: review)
    else
      :error -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end
end
