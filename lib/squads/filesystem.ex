defmodule Squads.Filesystem do
  @moduledoc """
  Filesystem utilities for browsing directories.

  Provides functions to safely browse the local filesystem for project selection.
  """

  @type directory_entry :: %{
          name: String.t(),
          path: String.t(),
          has_children: boolean(),
          is_git_repo: boolean()
        }

  @type browse_result :: %{
          current_path: String.t(),
          parent_path: String.t(),
          directories: [directory_entry()]
        }

  @doc """
  Browse directories at the given path.

  Returns a list of subdirectories with metadata including:
  - Whether they contain subdirectories (for tree expansion)
  - Whether they are git repositories

  ## Options
  - `:show_hidden` - Include hidden directories (starting with `.`). Default: `false`

  ## Examples

      iex> Squads.Filesystem.browse("/home/user/projects")
      {:ok, %{
        current_path: "/home/user/projects",
        parent_path: "/home/user",
        directories: [
          %{name: "my-app", path: "/home/user/projects/my-app", has_children: true, is_git_repo: true},
          %{name: "other", path: "/home/user/projects/other", has_children: false, is_git_repo: false}
        ]
      }}

      iex> Squads.Filesystem.browse("/nonexistent")
      {:error, :not_a_directory}
  """
  @spec browse(String.t(), keyword()) :: {:ok, browse_result()} | {:error, atom() | String.t()}
  def browse(path \\ nil, opts \\ []) do
    show_hidden = Keyword.get(opts, :show_hidden, false)

    abs_path = normalize_path(path)

    with :ok <- validate_directory(abs_path),
         {:ok, entries} <- list_directory(abs_path) do
      directories =
        entries
        |> filter_directories(abs_path, show_hidden)
        |> Enum.sort()
        |> Enum.map(&build_entry(abs_path, &1))

      {:ok,
       %{
         current_path: abs_path,
         parent_path: Path.dirname(abs_path),
         directories: directories
       }}
    end
  end

  @doc """
  Get the user's home directory.
  """
  @spec home_directory() :: String.t()
  def home_directory do
    System.user_home!()
  end

  @doc """
  Check if a path is a git repository.
  """
  @spec git_repo?(String.t()) :: boolean()
  def git_repo?(path) do
    File.dir?(Path.join(path, ".git"))
  end

  @doc """
  Check if a directory has any non-hidden subdirectories.
  """
  @spec has_subdirectories?(String.t()) :: boolean()
  def has_subdirectories?(path) do
    case File.ls(path) do
      {:ok, entries} ->
        Enum.any?(entries, fn entry ->
          not String.starts_with?(entry, ".") and File.dir?(Path.join(path, entry))
        end)

      _ ->
        false
    end
  end

  @doc """
  Recursively list all files in a directory.
  If it's a git repository, uses `git ls-files` for efficiency and .gitignore respect.
  """
  @spec list_all_files(String.t()) :: {:ok, [String.t()]} | {:error, term()}
  def list_all_files(path) do
    abs_path = normalize_path(path)

    if git_repo?(abs_path) do
      case System.cmd("git", ["ls-files"], cd: abs_path) do
        {output, 0} ->
          files = String.split(output, "\n", trim: true)
          {:ok, files}

        {_output, _} ->
          # Fallback to manual if git fails for some reason
          manual_recursive_list(abs_path)
      end
    else
      manual_recursive_list(abs_path)
    end
  end

  @ignored_dirs ~w(.git node_modules _build deps .elixir_ls .terrapin)

  defp manual_recursive_list(path) do
    try do
      files =
        path
        |> File.ls!()
        |> Enum.flat_map(fn entry ->
          full_path = Path.join(path, entry)

          cond do
            entry in @ignored_dirs ->
              []

            File.dir?(full_path) ->
              manual_recursive_list(full_path)
              |> case do
                {:ok, sub_files} -> Enum.map(sub_files, &Path.join(entry, &1))
                _ -> []
              end

            true ->
              [entry]
          end
        end)

      {:ok, files}
    rescue
      e -> {:error, e}
    end
  end

  # Private functions

  defp normalize_path(nil), do: home_directory()
  defp normalize_path(""), do: home_directory()
  defp normalize_path("~"), do: home_directory()
  defp normalize_path("~/" <> rest), do: Path.join(home_directory(), rest) |> Path.expand()
  defp normalize_path(path), do: Path.expand(path)

  defp validate_directory(path) do
    if File.dir?(path) do
      :ok
    else
      {:error, :not_a_directory}
    end
  end

  defp list_directory(path) do
    case File.ls(path) do
      {:ok, entries} -> {:ok, entries}
      {:error, reason} -> {:error, reason}
    end
  end

  defp filter_directories(entries, base_path, show_hidden) do
    Enum.filter(entries, fn entry ->
      full_path = Path.join(base_path, entry)
      is_dir = File.dir?(full_path)
      is_hidden = String.starts_with?(entry, ".")

      is_dir and (show_hidden or not is_hidden)
    end)
  end

  defp build_entry(base_path, name) do
    full_path = Path.join(base_path, name)

    %{
      name: name,
      path: full_path,
      has_children: has_subdirectories?(full_path),
      is_git_repo: git_repo?(full_path)
    }
  end
end
