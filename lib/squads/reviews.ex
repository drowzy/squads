defmodule Squads.Reviews do
  @moduledoc """
  First-class reviews domain module.

  Reviews are independent artifacts that capture code changes (diffs)
  with summaries, highlights, and comments. They can span multiple projects
  and support both committed (immutable) and uncommitted (recomputed) diffs.
  """

  import Ecto.Query, warn: false

  alias Squads.Repo
  alias Squads.Reviews.{Review, ReviewComment}
  alias Squads.Artifacts.Diff

  @context_lines 3

  # --- List / Get ---

  @doc """
  Lists reviews, optionally filtered by project_id or workspace_root.
  """
  def list_reviews(opts \\ []) do
    project_id = Keyword.get(opts, :project_id)
    workspace_root = Keyword.get(opts, :workspace_root)
    status = Keyword.get(opts, :status)

    Review
    |> maybe_filter_project(project_id)
    |> maybe_filter_workspace(workspace_root)
    |> maybe_filter_status(status)
    |> order_by([r], desc: r.updated_at)
    |> Repo.all()
    |> Repo.preload([:author, :comments])
  end

  defp maybe_filter_project(query, nil), do: query

  defp maybe_filter_project(query, project_id) do
    # SQLite JSON: project_ids is stored as JSON array
    where(query, [r], fragment("json_array_length(?) > 0", r.project_ids))
    |> where(
      [r],
      fragment("EXISTS (SELECT 1 FROM json_each(?) WHERE value = ?)", r.project_ids, ^project_id)
    )
  end

  defp maybe_filter_workspace(query, nil), do: query
  defp maybe_filter_workspace(query, root), do: where(query, [r], r.workspace_root == ^root)

  defp maybe_filter_status(query, nil), do: query
  defp maybe_filter_status(query, status), do: where(query, [r], r.status == ^status)

  @doc """
  Gets a review by ID with computed diff.
  """
  def get_review(id) do
    case Repo.get(Review, id) do
      nil ->
        {:error, :not_found}

      review ->
        review = Repo.preload(review, [:author, :comments])
        {:ok, review}
    end
  end

  @doc """
  Fetches a review, returns {:error, :not_found} if missing.
  """
  def fetch_review(id) do
    get_review(id)
  end

  # --- Create / Update ---

  @doc """
  Creates a new review.

  Computes and stores the initial diff snapshot.
  """
  def create_review(attrs) do
    attrs = normalize_attrs(attrs)

    # Compute initial diff if worktree info provided
    attrs = maybe_compute_diff(attrs)

    %Review{}
    |> Review.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a review.
  """
  def update_review(%Review{} = review, attrs) do
    review
    |> Review.changeset(normalize_attrs(attrs))
    |> Repo.update()
  end

  def update_review(id, attrs) when is_binary(id) do
    case get_review(id) do
      {:ok, review} -> update_review(review, attrs)
      error -> error
    end
  end

  @doc """
  Submits a review with a status update and optional feedback comment.
  """
  def submit_review(id, status, feedback \\ nil)
      when status in ["approved", "changes_requested"] do
    Repo.transaction(fn ->
      with {:ok, review} <- get_review(id),
           {:ok, updated} <- update_review(review, %{status: status}) do
        # Add feedback as summary comment if provided
        if is_binary(feedback) and String.trim(feedback) != "" do
          add_comment(updated, %{
            type: "summary",
            body: feedback,
            author_type: "human",
            author_name: "human"
          })
        end

        {:ok, Repo.preload(updated, [:comments], force: true)}
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
    |> case do
      {:ok, {:ok, review}} -> {:ok, review}
      {:ok, review} -> {:ok, review}
      {:error, reason} -> {:error, reason}
    end
  end

  # --- Comments ---

  @doc """
  Adds a comment to a review.

  For line comments, captures code context snippets.
  """
  def add_comment(%Review{} = review, attrs) do
    attrs =
      attrs
      |> Map.put(:review_id, review.id)
      |> maybe_capture_context(review)

    %ReviewComment{}
    |> ReviewComment.changeset(attrs)
    |> Repo.insert()
  end

  def add_comment(review_id, attrs) when is_binary(review_id) do
    case get_review(review_id) do
      {:ok, review} -> add_comment(review, attrs)
      error -> error
    end
  end

  @doc """
  Lists comments for a review.
  """
  def list_comments(review_id) do
    ReviewComment
    |> where([c], c.review_id == ^review_id)
    |> order_by([c], asc: c.inserted_at)
    |> Repo.all()
  end

  # --- Diff Computation ---

  @doc """
  Computes or returns the diff for a review.

  - If head_sha is present: uses stored diff (immutable commit range)
  - If head_sha is nil: recomputes from worktree (uncommitted changes)
  """
  def compute_diff(%Review{} = review) do
    cond do
      # Committed range - use stored diff or compute from commits
      is_binary(review.head_sha) and review.head_sha != "" ->
        if is_binary(review.diff) and review.diff != "" do
          {:ok, review.diff}
        else
          compute_committed_diff(review)
        end

      # Uncommitted - recompute from worktree
      is_binary(review.worktree_path) and review.worktree_path != "" ->
        compute_worktree_diff(review)

      # Use stored diff if available
      is_binary(review.diff) ->
        {:ok, review.diff}

      true ->
        {:ok, ""}
    end
  end

  defp compute_committed_diff(%Review{worktree_path: path, base_sha: base, head_sha: head}) do
    if is_binary(path) and path != "" do
      Diff.git_patch(path, base, head)
    else
      {:ok, ""}
    end
  end

  defp compute_worktree_diff(%Review{worktree_path: path, base_sha: base}) do
    cond do
      not is_binary(path) or path == "" ->
        {:ok, ""}

      is_binary(base) and base != "" ->
        # Diff from base_sha to current worktree
        Diff.git_patch(path, base, "HEAD")
        |> case do
          {:ok, committed} ->
            case Diff.worktree_patch(path) do
              {:ok, uncommitted} ->
                combined = String.trim(committed) <> "\n" <> String.trim(uncommitted)
                {:ok, String.trim(combined)}

              _ ->
                {:ok, committed}
            end

          _ ->
            Diff.worktree_patch(path)
        end

      true ->
        Diff.worktree_patch(path)
    end
  end

  # --- Files Changed Extraction ---

  @doc """
  Extracts files changed statistics from a diff.
  """
  def extract_files_changed(diff) when is_binary(diff) do
    diff
    |> String.split("\n")
    |> Enum.reduce(%{current: nil, files: []}, fn line, acc ->
      cond do
        String.starts_with?(line, "diff --git ") ->
          # Extract file path from "diff --git a/path b/path"
          case Regex.run(~r/diff --git a\/.+ b\/(.+)/, line) do
            [_, path] ->
              file_entry = %{path: path, additions: 0, deletions: 0}
              %{acc | current: path, files: acc.files ++ [file_entry]}

            _ ->
              acc
          end

        String.starts_with?(line, "+") and not String.starts_with?(line, "+++") ->
          update_file_stat(acc, :additions)

        String.starts_with?(line, "-") and not String.starts_with?(line, "---") ->
          update_file_stat(acc, :deletions)

        true ->
          acc
      end
    end)
    |> Map.get(:files)
  end

  def extract_files_changed(_), do: []

  defp update_file_stat(%{current: nil} = acc, _), do: acc

  defp update_file_stat(%{current: path, files: files} = acc, stat) do
    files =
      Enum.map(files, fn file ->
        if file.path == path do
          Map.update!(file, stat, &(&1 + 1))
        else
          file
        end
      end)

    %{acc | files: files}
  end

  # --- Helpers ---

  defp normalize_attrs(attrs) when is_map(attrs) do
    attrs
    |> Enum.map(fn
      {k, v} when is_atom(k) -> {k, v}
      {k, v} when is_binary(k) -> {String.to_existing_atom(k), v}
    end)
    |> Map.new()
  rescue
    ArgumentError -> attrs
  end

  defp maybe_compute_diff(attrs) do
    worktree = Map.get(attrs, :worktree_path)
    base = Map.get(attrs, :base_sha)
    head = Map.get(attrs, :head_sha)

    cond do
      # Already has diff
      Map.has_key?(attrs, :diff) and attrs.diff != nil and attrs.diff != "" ->
        maybe_extract_files(attrs)

      # Can compute from worktree
      is_binary(worktree) and worktree != "" ->
        diff_result =
          if is_binary(head) and head != "" do
            Diff.git_patch(worktree, base || "HEAD", head)
          else
            Diff.worktree_patch(worktree)
          end

        case diff_result do
          {:ok, diff} ->
            attrs
            |> Map.put(:diff, diff)
            |> Map.put(:files_changed, extract_files_changed(diff))

          _ ->
            attrs
        end

      true ->
        attrs
    end
  end

  defp maybe_extract_files(attrs) do
    if Map.has_key?(attrs, :files_changed) and attrs.files_changed != [] do
      attrs
    else
      diff = Map.get(attrs, :diff, "")
      Map.put(attrs, :files_changed, extract_files_changed(diff))
    end
  end

  defp maybe_capture_context(attrs, review) do
    type = Map.get(attrs, :type) || Map.get(attrs, "type")
    file_path = Map.get(attrs, :file_path) || Map.get(attrs, "file_path")
    line_number = Map.get(attrs, :line_number) || Map.get(attrs, "line_number")

    if type == "line" and is_binary(file_path) and is_integer(line_number) do
      case capture_line_context(review, file_path, line_number) do
        {:ok, before_ctx, after_ctx} ->
          attrs
          |> Map.put(:before_context, before_ctx)
          |> Map.put(:after_context, after_ctx)

        _ ->
          attrs
      end
    else
      attrs
    end
  end

  defp capture_line_context(%Review{worktree_path: worktree}, file_path, line_number)
       when is_binary(worktree) and worktree != "" do
    abs_path = Path.join(worktree, file_path)

    if File.exists?(abs_path) do
      case File.read(abs_path) do
        {:ok, content} ->
          lines = String.split(content, "\n")
          start_idx = max(0, line_number - @context_lines - 1)
          end_idx = min(length(lines) - 1, line_number + @context_lines - 1)

          before_lines = Enum.slice(lines, start_idx, line_number - start_idx - 1)
          after_lines = Enum.slice(lines, line_number, end_idx - line_number + 1)

          {:ok, Enum.join(before_lines, "\n"), Enum.join(after_lines, "\n")}

        _ ->
          :error
      end
    else
      :error
    end
  end

  defp capture_line_context(_, _, _), do: :error
end
