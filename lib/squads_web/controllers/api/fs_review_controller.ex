defmodule SquadsWeb.API.FsReviewController do
  use SquadsWeb, :controller

  require Logger

  alias Squads.Artifacts
  alias Squads.Artifacts.Diff
  alias Squads.Board.Card
  alias Squads.Projects
  alias Squads.Repo
  alias Squads.Sessions

  action_fallback SquadsWeb.FallbackController

  def index(conn, %{"project_id" => project_id}) do
    with {:ok, uuid} <- cast_uuid(project_id),
         %Projects.Project{} = project <- Projects.get_project(uuid),
         {:ok, reviews} <- Artifacts.list_reviews(project.path) do
      render(conn, :index, reviews: reviews)
    else
      {:error, :not_found} -> {:error, :not_found}
      nil -> {:error, :not_found}
    end
  end

  def show(conn, %{"project_id" => project_id, "id" => review_id}) do
    with {:ok, uuid} <- cast_uuid(project_id),
         %Projects.Project{} = project <- Projects.get_project(uuid),
         {:ok, review} <- Artifacts.get_review(project.path, review_id) do
      {diff, diff_error} = compute_diff(review)
      render(conn, :show, review: review, diff: diff, diff_error: diff_error)
    else
      {:error, :not_found} -> {:error, :not_found}
      nil -> {:error, :not_found}
    end
  end

  def create(conn, %{"project_id" => project_id} = params) do
    with {:ok, uuid} <- cast_uuid(project_id),
         %Projects.Project{} = project <- Projects.get_project(uuid),
         {:ok, review} <- create_review(project.path, params) do
      conn
      |> put_status(:created)
      |> render(:create, review: review)
    else
      {:error, :not_found} -> {:error, :not_found}
      nil -> {:error, :not_found}
    end
  end

  def submit(conn, %{"project_id" => project_id, "id" => review_id} = params) do
    with {:ok, uuid} <- cast_uuid(project_id),
         %Projects.Project{} = project <- Projects.get_project(uuid),
         {:ok, review} <- submit_review(project.path, review_id, params) do
      _ = maybe_send_review_feedback(project, review)
      render(conn, :submit, review: review)
    else
      {:error, :not_found} -> {:error, :not_found}
      nil -> {:error, :not_found}
    end
  end

  defp create_review(project_root, params) do
    attrs =
      params
      |> Map.take([
        "title",
        "summary",
        "highlights",
        "context",
        "references",
        "files_changed",
        "comments",
        "status"
      ])
      |> normalize_review_context(params)

    case Artifacts.create_review(project_root, attrs) do
      {:ok, review} -> {:ok, review}
      {:error, {:validation, changeset}} -> {:error, changeset}
      other -> other
    end
  end

  defp submit_review(project_root, review_id, params) do
    status = Map.get(params, "status")
    feedback = Map.get(params, "feedback", "")

    submitted_comment =
      if is_binary(feedback) and String.trim(feedback) != "" do
        %{
          "id" => "cmt_" <> UUIDv7.generate(),
          "created_at" =>
            DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601(),
          "author" => "human",
          "type" => "summary",
          "body" => feedback,
          "file" => nil,
          "line" => nil,
          "side" => "new"
        }
      else
        nil
      end

    comments =
      params
      |> Map.get("comments", [])
      |> List.wrap()
      |> maybe_prepend_comment(submitted_comment)

    patch =
      %{}
      |> maybe_put("status", status)
      |> Map.put("comments", comments)

    case Artifacts.update_review(project_root, review_id, patch) do
      {:ok, review} -> {:ok, review}
      {:error, {:validation, changeset}} -> {:error, changeset}
      other -> other
    end
  end

  defp normalize_review_context(attrs, params) do
    existing = Map.get(attrs, "context")

    if is_map(existing) do
      attrs
    else
      context_keys = [
        "worktree_path",
        "base_sha",
        "head_sha",
        "project_id",
        "squad_id",
        "card_id",
        "session_id"
      ]

      context =
        context_keys
        |> Enum.reduce(%{}, fn key, acc ->
          case Map.get(params, key) do
            nil -> acc
            value -> Map.put(acc, key, value)
          end
        end)

      if map_size(context) == 0 do
        attrs
      else
        Map.put(attrs, "context", context)
      end
    end
  end

  defp compute_diff(review) do
    context = Map.get(review, :context) || %{}

    worktree_path = Map.get(context, "worktree_path") || Map.get(context, :worktree_path)
    base_sha = Map.get(context, "base_sha") || Map.get(context, :base_sha)
    head_sha = Map.get(context, "head_sha") || Map.get(context, :head_sha)

    has_range_diff? =
      is_binary(base_sha) and base_sha != "" and
        is_binary(head_sha) and head_sha != ""

    cond do
      not (is_binary(worktree_path) and worktree_path != "") ->
        {"", "missing_worktree_path"}

      has_range_diff? ->
        case Diff.git_patch(worktree_path, base_sha, head_sha) do
          {:ok, diff} -> {diff, nil}
          {:error, reason} -> {"", reason}
        end

      true ->
        case Diff.worktree_patch(worktree_path) do
          {:ok, diff} -> {diff, nil}
          {:error, reason} -> {"", reason}
        end
    end
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp maybe_prepend_comment(comments, nil), do: comments
  defp maybe_prepend_comment(comments, comment), do: [comment | comments]

  defp maybe_send_review_feedback(%Projects.Project{} = project, review) do
    payload =
      review
      |> Squads.Artifacts.Review.to_storage_map()
      |> Map.put("kind", "fs_review_feedback")
      |> Map.put("project_id", project.id)

    prompt =
      """
      Human review submitted for filesystem review #{payload["id"]}.

      ```json
      #{Jason.encode!(payload, pretty: true)}
      ```
      """

    session_id = resolve_feedback_session_id(review)

    with true <- is_binary(session_id) and session_id != "",
         {:ok, uuid} <- Ecto.UUID.cast(session_id),
         {:ok, session} <- Sessions.fetch_session(uuid) do
      opts = feedback_send_opts(session)

      case Sessions.send_prompt_async(session, prompt, opts) do
        {:ok, _} ->
          :ok

        {:error, reason} ->
          Logger.warning("Failed to send fs review feedback",
            review_id: payload["id"],
            session_id: session_id,
            reason: inspect(reason)
          )

          :ok
      end
    else
      _ ->
        :ok
    end
  end

  defp resolve_feedback_session_id(review) do
    context = Map.get(review, :context) || %{}
    references = Map.get(review, :references) || %{}

    session_id =
      Map.get(context, "session_id") || Map.get(context, :session_id) ||
        Map.get(references, "session_id") || Map.get(references, :session_id)

    cond do
      is_binary(session_id) and session_id != "" ->
        session_id

      true ->
        card_id =
          Map.get(context, "card_id") || Map.get(context, :card_id) ||
            Map.get(references, "card_id") || Map.get(references, :card_id)

        with true <- is_binary(card_id) and card_id != "",
             {:ok, uuid} <- Ecto.UUID.cast(card_id),
             %Card{} = card <- Repo.get(Card, uuid) do
          card.build_session_id || card.review_session_id || card.ai_review_session_id
        else
          _ -> nil
        end
    end
  end

  defp feedback_send_opts(session) do
    metadata = session.metadata || %{}

    base_url =
      Map.get(metadata, "opencode_base_url") ||
        Map.get(metadata, :opencode_base_url)

    if is_binary(base_url) and base_url != "" do
      [base_url: base_url]
    else
      []
    end
  end

  defp cast_uuid(id) do
    case Ecto.UUID.cast(id) do
      {:ok, uuid} -> {:ok, uuid}
      :error -> {:error, :not_found}
    end
  end
end
