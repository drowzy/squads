defmodule Squads.Artifacts.Path do
  @moduledoc false

  @type error :: :invalid_path

  @spec safe_join(String.t(), String.t()) :: {:ok, String.t()} | {:error, error()}
  def safe_join(project_root, relative_path)
      when is_binary(project_root) and is_binary(relative_path) do
    project_root = Path.expand(project_root)

    cond do
      relative_path == "" ->
        {:ok, project_root}

      Path.type(relative_path) == :absolute ->
        {:error, :invalid_path}

      String.contains?(relative_path, "\0") ->
        {:error, :invalid_path}

      has_parent_traversal?(relative_path) ->
        {:error, :invalid_path}

      true ->
        joined = Path.expand(Path.join(project_root, relative_path))
        project_root_with_sep = Path.join(project_root, "")

        if joined == project_root or String.starts_with?(joined, project_root_with_sep) do
          {:ok, joined}
        else
          {:error, :invalid_path}
        end
    end
  end

  defp has_parent_traversal?(relative_path) do
    relative_path
    |> String.split(~r{[\\/]+}, trim: true)
    |> Enum.any?(&(&1 == ".."))
  end
end
