defmodule Squads.Artifacts do
  @moduledoc """
  Filesystem-backed issues and reviews stored under a project root.

  See `.squads/prds/002-document.md`.
  """

  alias Squads.Artifacts.{Issue, Review}
  alias Squads.Artifacts.Path, as: ArtifactsPath

  @issues_dir_rel ".squads/issues"
  @reviews_dir_rel ".squads/reviews"

  @type error ::
          :invalid_project_root
          | :invalid_path
          | :not_found
          | :invalid_id
          | :invalid_title
          | {:validation, Ecto.Changeset.t()}
          | term()

  @spec ensure_dirs(String.t()) :: :ok | {:error, error()}
  def ensure_dirs(project_root) when is_binary(project_root) do
    if File.dir?(project_root) do
      with {:ok, issues_dir} <- ArtifactsPath.safe_join(project_root, @issues_dir_rel),
           {:ok, reviews_dir} <- ArtifactsPath.safe_join(project_root, @reviews_dir_rel),
           :ok <- File.mkdir_p(issues_dir),
           :ok <- File.mkdir_p(reviews_dir) do
        :ok
      end
    else
      {:error, :invalid_project_root}
    end
  end

  @spec list_issues(String.t()) :: {:ok, [map()]} | {:error, error()}
  def list_issues(project_root) do
    with :ok <- ensure_dirs(project_root),
         {:ok, issues_dir} <- ArtifactsPath.safe_join(project_root, @issues_dir_rel),
         {:ok, entries} <- File.ls(issues_dir) do
      issues =
        entries
        |> Enum.filter(&String.starts_with?(&1, "iss_"))
        |> Enum.filter(&String.ends_with?(&1, ".md"))
        |> Enum.map(fn filename ->
          issue_id = String.trim_trailing(filename, ".md")

          case get_issue(project_root, issue_id) do
            {:ok, %Issue{} = issue} ->
              %{
                id: issue.id,
                title: issue.title,
                status: issue.status,
                updated_at: Issue.updated_at_iso8601(issue),
                path: issue.path
              }

            {:error, _} ->
              nil
          end
        end)
        |> Enum.reject(&is_nil/1)
        |> Enum.sort_by(&(&1.updated_at || ""), :desc)

      {:ok, issues}
    end
  end

  @spec get_issue(String.t(), String.t()) :: {:ok, Issue.t()} | {:error, error()}
  def get_issue(project_root, issue_id) when is_binary(issue_id) do
    with :ok <- ensure_dirs(project_root),
         :ok <- validate_issue_id(issue_id),
         rel_path = Path.join(@issues_dir_rel, issue_id <> ".md"),
         {:ok, abs_path} <- ArtifactsPath.safe_join(project_root, rel_path),
         {:ok, content} <- read_file(abs_path),
         {:ok, %Issue{} = issue} <- normalize_issue_parse(Issue.parse(content)) do
      {:ok, %Issue{issue | path: rel_path}}
    end
  end

  @spec create_issue(String.t(), map()) :: {:ok, Issue.t()} | {:error, error()}
  def create_issue(project_root, attrs) when is_map(attrs) do
    with :ok <- ensure_dirs(project_root),
         title when is_binary(title) and title != "" <- get_attr(attrs, "title"),
         issue_id <- "iss_" <> UUIDv7.generate(),
         {:ok, %Issue{} = issue} <-
           Issue.new(issue_id, Map.put(stringify_keys(attrs), "title", title)) do
      rel_path = Path.join(@issues_dir_rel, issue_id <> ".md")

      with {:ok, abs_path} <- ArtifactsPath.safe_join(project_root, rel_path),
           :ok <- File.write(abs_path, Issue.render(issue)),
           {:ok, %Issue{} = stored} <- get_issue(project_root, issue_id) do
        {:ok, %Issue{stored | path: rel_path}}
      end
    else
      nil -> {:error, :invalid_title}
      "" -> {:error, :invalid_title}
      {:error, %Ecto.Changeset{} = changeset} -> {:error, {:validation, changeset}}
      {:error, {:validation, %Ecto.Changeset{} = changeset}} -> {:error, {:validation, changeset}}
      {:error, other} -> {:error, other}
      other -> {:error, other}
    end
  end

  @spec update_issue(String.t(), String.t(), map()) :: {:ok, Issue.t()} | {:error, error()}
  def update_issue(project_root, issue_id, attrs) when is_binary(issue_id) and is_map(attrs) do
    with {:ok, %Issue{} = issue} <- get_issue(project_root, issue_id),
         {:ok, %Issue{} = updated} <- normalize_issue_update(Issue.apply_update(issue, attrs)) do
      rel_path = Path.join(@issues_dir_rel, issue_id <> ".md")

      with {:ok, abs_path} <- ArtifactsPath.safe_join(project_root, rel_path),
           :ok <- File.write(abs_path, Issue.render(updated)),
           {:ok, %Issue{} = stored} <- get_issue(project_root, issue_id) do
        {:ok, %Issue{stored | path: rel_path}}
      end
    end
  end

  @spec list_reviews(String.t()) :: {:ok, [map()]} | {:error, error()}
  def list_reviews(project_root) do
    with :ok <- ensure_dirs(project_root),
         {:ok, reviews_dir} <- ArtifactsPath.safe_join(project_root, @reviews_dir_rel),
         {:ok, entries} <- File.ls(reviews_dir) do
      reviews =
        entries
        |> Enum.filter(&String.starts_with?(&1, "rev_"))
        |> Enum.filter(&String.ends_with?(&1, ".json"))
        |> Enum.map(fn filename ->
          review_id = String.trim_trailing(filename, ".json")

          case get_review(project_root, review_id) do
            {:ok, %Review{} = review} ->
              %{
                id: review.id,
                title: review.title,
                status: review.status,
                updated_at: Review.updated_at_iso8601(review),
                path: review.path
              }

            {:error, _} ->
              nil
          end
        end)
        |> Enum.reject(&is_nil/1)
        |> Enum.sort_by(&(&1.updated_at || ""), :desc)

      {:ok, reviews}
    end
  end

  @spec get_review(String.t(), String.t()) :: {:ok, Review.t()} | {:error, error()}
  def get_review(project_root, review_id) when is_binary(review_id) do
    with :ok <- ensure_dirs(project_root),
         :ok <- validate_review_id(review_id),
         rel_path = Path.join(@reviews_dir_rel, review_id <> ".json"),
         {:ok, abs_path} <- ArtifactsPath.safe_join(project_root, rel_path),
         {:ok, content} <- read_file(abs_path),
         {:ok, %Review{} = review} <- normalize_review_parse(Review.parse(content)) do
      {:ok, %Review{review | path: rel_path}}
    end
  end

  @spec create_review(String.t(), map()) :: {:ok, Review.t()} | {:error, error()}
  def create_review(project_root, attrs) when is_map(attrs) do
    with :ok <- ensure_dirs(project_root),
         title when is_binary(title) and title != "" <- get_attr(attrs, "title"),
         review_id <- "rev_" <> UUIDv7.generate(),
         {:ok, %Review{} = review} <-
           Review.new(review_id, Map.put(stringify_keys(attrs), "title", title)) do
      rel_path = Path.join(@reviews_dir_rel, review_id <> ".json")

      with {:ok, abs_path} <- ArtifactsPath.safe_join(project_root, rel_path),
           :ok <- File.write(abs_path, Review.render(review)),
           {:ok, %Review{} = stored} <- get_review(project_root, review_id) do
        {:ok, %Review{stored | path: rel_path}}
      end
    else
      nil -> {:error, :invalid_title}
      "" -> {:error, :invalid_title}
      {:error, %Ecto.Changeset{} = changeset} -> {:error, {:validation, changeset}}
      {:error, {:validation, %Ecto.Changeset{} = changeset}} -> {:error, {:validation, changeset}}
      {:error, other} -> {:error, other}
      other -> {:error, other}
    end
  end

  @spec update_review(String.t(), String.t(), map()) :: {:ok, Review.t()} | {:error, error()}
  def update_review(project_root, review_id, patch) when is_binary(review_id) and is_map(patch) do
    with {:ok, %Review{} = existing} <- get_review(project_root, review_id),
         {:ok, %Review{} = updated} <-
           normalize_review_update(Review.apply_patch(existing, patch)) do
      rel_path = Path.join(@reviews_dir_rel, review_id <> ".json")

      with {:ok, abs_path} <- ArtifactsPath.safe_join(project_root, rel_path),
           :ok <- File.write(abs_path, Review.render(updated)),
           {:ok, %Review{} = stored} <- get_review(project_root, review_id) do
        {:ok, %Review{stored | path: rel_path}}
      end
    end
  end

  defp validate_issue_id(issue_id) do
    if Regex.match?(~r/^iss_[A-Za-z0-9\-_.]+$/, issue_id) do
      :ok
    else
      {:error, :invalid_id}
    end
  end

  defp validate_review_id(review_id) do
    if Regex.match?(~r/^rev_[A-Za-z0-9\-_.]+$/, review_id) do
      :ok
    else
      {:error, :invalid_id}
    end
  end

  defp read_file(path) do
    case File.read(path) do
      {:ok, content} -> {:ok, content}
      {:error, :enoent} -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  defp get_attr(attrs, key) when is_map(attrs) and is_binary(key) do
    Map.get(attrs, key) || Map.get(attrs, safe_to_existing_atom(key))
  end

  defp safe_to_existing_atom(key) when is_binary(key) do
    String.to_existing_atom(key)
  rescue
    ArgumentError -> nil
  end

  defp stringify_keys(map) when is_map(map) do
    map
    |> Enum.map(fn {k, v} -> {to_string(k), v} end)
    |> Map.new()
  end

  defp normalize_issue_parse({:ok, %Issue{} = issue}), do: {:ok, issue}

  defp normalize_issue_parse({:error, {:validation, %Ecto.Changeset{} = changeset}}),
    do: {:error, {:validation, changeset}}

  defp normalize_issue_parse(other), do: other

  defp normalize_issue_update({:ok, %Issue{} = issue}), do: {:ok, issue}

  defp normalize_issue_update({:error, %Ecto.Changeset{} = changeset}),
    do: {:error, {:validation, changeset}}

  defp normalize_issue_update(other), do: other

  defp normalize_review_parse({:ok, %Review{} = review}), do: {:ok, review}

  defp normalize_review_parse({:error, {:validation, %Ecto.Changeset{} = changeset}}),
    do: {:error, {:validation, changeset}}

  defp normalize_review_parse(other), do: other

  defp normalize_review_update({:ok, %Review{} = review}), do: {:ok, review}

  defp normalize_review_update({:error, %Ecto.Changeset{} = changeset}),
    do: {:error, {:validation, changeset}}

  defp normalize_review_update(other), do: other
end
