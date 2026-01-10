defmodule Squads.GitHub.RepoResolver do
  @moduledoc false

  alias Squads.Projects
  alias Squads.Projects.Project

  @spec github_repo_for_project(Ecto.UUID.t() | Project.t()) ::
          {:ok, String.t()} | {:error, atom()}
  def github_repo_for_project(%Project{} = project), do: github_repo_for_project(project.id)

  def github_repo_for_project(project_id) when is_binary(project_id) do
    case Projects.get_project(project_id) do
      %Project{} = project -> resolve_for_project(project)
      nil -> {:error, :not_found}
    end
  end

  defp resolve_for_project(%Project{} = project) do
    configured = get_in(project.config || %{}, ["integrations", "github", "repo"])

    cond do
      is_binary(configured) and configured != "" ->
        {:ok, configured}

      is_binary(project.path) and project.path != "" ->
        detect_repo_from_git_remote(project.path)

      true ->
        {:error, :github_repo_not_configured}
    end
  end

  defp detect_repo_from_git_remote(path) do
    case System.cmd("git", ["remote", "get-url", "origin"], cd: path, stderr_to_stdout: true) do
      {output, 0} ->
        output
        |> parse_github_repo_from_remote()
        |> case do
          nil -> {:error, :github_repo_not_configured}
          repo -> {:ok, repo}
        end

      {_output, _status} ->
        {:error, :github_repo_not_configured}
    end
  end

  defp parse_github_repo_from_remote(output) when is_binary(output) do
    url = output |> String.trim() |> String.trim_trailing(".git")

    url =
      cond do
        String.starts_with?(url, "git@github.com:") ->
          String.replace_prefix(url, "git@github.com:", "")

        String.starts_with?(url, "https://github.com/") ->
          String.replace_prefix(url, "https://github.com/", "")

        String.starts_with?(url, "ssh://git@github.com/") ->
          String.replace_prefix(url, "ssh://git@github.com/", "")

        true ->
          url
      end

    case String.split(url, "/", parts: 2) do
      [owner, repo] when owner != "" and repo != "" -> "#{owner}/#{repo}"
      _ -> nil
    end
  end
end
