defmodule Squads.OpenCode.Resolver do
  @moduledoc """
  Centralizes OpenCode node discovery, base_url resolution, and path normalization.
  """
  require Logger
  alias Squads.OpenCode.Client

  @doc """
  Resolves the base_url for an OpenCode instance associated with a project.

  Priority order:
  1) explicit opts[:base_url]
  2) find_matching_local_node(project_path)
  3) Fallback to configured default
  """
  def resolve_base_url(project_path, opts \\ []) do
    cond do
      url = Keyword.get(opts, :base_url) ->
        {:ok, url}

      url = find_matching_local_node(project_path) ->
        {:ok, url}

      true ->
        {:ok, configured_base_url()}
    end
  end

  @doc """
  Finds a local OpenCode node that is currently serving the given project path.
  """
  def find_matching_local_node(project_path) do
    list_local_listeners()
    |> Enum.find_value(fn listener ->
      base_url = "http://127.0.0.1:#{listener.port}"

      case Client.get_current_project(base_url: base_url, timeout: 1000, retry_count: 0) do
        {:ok, project} when is_map(project) ->
          if project_matches?(project_path, project) do
            base_url
          end

        _ ->
          nil
      end
    end)
  end

  @doc """
  Canonicalizes and normalizes a project path for comparison.
  Handles macOS /System/Volumes/Data prefix.
  """
  def project_matches?(project_path, project) do
    path = project["worktree"] || project["path"]

    project_path = canonicalize_path(project_path)
    opencode_path = canonicalize_path(path)

    is_binary(project_path) and is_binary(opencode_path) and project_path == opencode_path
  end

  def canonicalize_path(path) when is_binary(path) do
    path
    |> Path.expand()
    |> normalize_macos_volume()
  end

  def canonicalize_path(_), do: nil

  defp normalize_macos_volume(path) do
    data_prefix = "/System/Volumes/Data"

    if String.starts_with?(path, data_prefix <> "/") do
      String.replace_prefix(path, data_prefix, "")
    else
      path
    end
  end

  @doc """
  Scans for local OpenCode processes using lsof.
  """
  def list_local_listeners(lsof_runner \\ &System.cmd/2) do
    case lsof_runner.("lsof", ["-nP", "-iTCP", "-sTCP:LISTEN"]) do
      {output, 0} ->
        output
        |> String.split("\n", trim: true)
        |> Enum.filter(&String.contains?(&1, "opencode"))
        |> Enum.map(&parse_lsof_listener/1)
        |> Enum.filter(& &1)
        |> Enum.uniq_by(& &1.port)

      _ ->
        []
    end
  rescue
    _ -> []
  end

  @doc """
  Parses a single line of lsof output to extract PID and port.
  """
  def parse_lsof_listener(line) do
    case Regex.run(~r/^\s*\S+\s+(\d+).*TCP\s+.*:(\d+)\s+\(LISTEN\)/, line) do
      [_, pid, port] ->
        %{pid: String.to_integer(pid), port: String.to_integer(port)}

      _ ->
        nil
    end
  end

  defp configured_base_url do
    System.get_env("OPENCODE_BASE_URL") ||
      :squads
      |> Application.get_env(Squads.OpenCode.Client, [])
      |> Keyword.get(:base_url, "http://127.0.0.1:4096")
  end
end
