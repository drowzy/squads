defmodule SquadsWeb.API.BoardController do
  @moduledoc false

  use SquadsWeb, :controller

  alias Squads.Board

  action_fallback SquadsWeb.FallbackController

  def show(conn, %{"project_id" => project_id}) do
    with {:ok, uuid} <- Ecto.UUID.cast(project_id) do
      board = Board.list_board(uuid)
      render(conn, :show, board: board)
    else
      :error -> {:error, :not_found}
    end
  end

  def create_card(conn, %{"project_id" => project_id, "squad_id" => squad_id, "body" => body}) do
    with {:ok, project_uuid} <- Ecto.UUID.cast(project_id),
         {:ok, squad_uuid} <- Ecto.UUID.cast(squad_id),
         {:ok, card} <- Board.create_card(project_uuid, squad_uuid, body) do
      conn
      |> put_status(:created)
      |> render(:card, card: card)
    else
      :error -> {:error, :not_found}
      {:error, changeset} -> {:error, changeset}
    end
  end

  def create_card(conn, %{"project_id" => _}) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "missing_params", message: "squad_id and body are required"})
  end

  def update_card(conn, %{"id" => id} = params) do
    with {:ok, uuid} <- Ecto.UUID.cast(id) do
      cond do
        is_binary(params["lane"]) ->
          with {:ok, updated} <- Board.move_card(uuid, String.downcase(params["lane"])) do
            render(conn, :card, card: updated)
          end

        is_binary(params["pr_url"]) ->
          with {:ok, updated} <- Board.set_pr_url(uuid, params["pr_url"]) do
            render(conn, :card, card: updated)
          end

        true ->
          conn
          |> put_status(:bad_request)
          |> json(%{error: "missing_params", message: "lane or pr_url is required"})
      end
    else
      :error -> {:error, :not_found}
    end
  end

  def assign_lane(
        conn,
        %{"project_id" => project_id, "squad_id" => squad_id, "lane" => lane} = params
      ) do
    agent_id = Map.get(params, "agent_id")

    with {:ok, project_uuid} <- Ecto.UUID.cast(project_id),
         {:ok, squad_uuid} <- Ecto.UUID.cast(squad_id),
         lane <- String.downcase(lane),
         {:ok, agent_uuid} <- cast_optional_uuid(agent_id),
         {:ok, assignment} <-
           Board.upsert_lane_assignment(project_uuid, squad_uuid, lane, agent_uuid) do
      render(conn, :lane_assignment, assignment: assignment)
    else
      :error -> {:error, :not_found}
      {:error, changeset} -> {:error, changeset}
    end
  end

  def sync_artifacts(conn, %{"id" => id}) do
    with {:ok, uuid} <- Ecto.UUID.cast(id),
         {:ok, card} <- Board.sync_artifacts(uuid) do
      render(conn, :card, card: card)
    else
      :error -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  def create_issues(conn, %{"id" => id}) do
    with {:ok, uuid} <- Ecto.UUID.cast(id),
         {:ok, card} <- Board.create_issues_from_plan(uuid) do
      render(conn, :card, card: card)
    else
      :error -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  def create_pr(conn, %{"id" => id}) do
    with {:ok, uuid} <- Ecto.UUID.cast(id),
         {:ok, _} <- Board.request_create_pr(uuid) do
      send_resp(conn, :no_content, "")
    else
      :error -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  def submit_human_review(conn, %{"id" => id, "status" => status} = params) do
    feedback = Map.get(params, "feedback", "")

    with {:ok, uuid} <- Ecto.UUID.cast(id),
         {:ok, card} <- Board.submit_human_review(uuid, status, feedback) do
      render(conn, :card, card: card)
    else
      :error -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  defp cast_optional_uuid(nil), do: {:ok, nil}
  defp cast_optional_uuid(""), do: {:ok, nil}

  defp cast_optional_uuid(id) do
    case Ecto.UUID.cast(id) do
      {:ok, uuid} -> {:ok, uuid}
      :error -> {:error, :not_found}
    end
  end
end
