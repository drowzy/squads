defmodule Squads.OpenCode.Resolver do
  @moduledoc """
  Centralizes OpenCode node discovery and base_url resolution.
  """
  require Logger
  alias Squads.OpenCode.Discovery
  alias Squads.OpenCode.Client

  @doc """
  Resolves the base_url for an OpenCode instance associated with a project.

  Priority order:
  1) explicit opts[:base_url]
  2) Discovery.discover_nodes() filtered by project match
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

  defp find_matching_local_node(project_path) do
    Discovery.discover_nodes()
    |> Enum.find_value(fn node ->
      case Client.client().get_current_project(base_url: node.base_url) do
        {:ok, %{"path" => path}} when path == project_path ->
          node.base_url

        _ ->
          nil
      end
    end)
  end

  defp configured_base_url do
    System.get_env("OPENCODE_BASE_URL") ||
      :squads
      |> Application.get_env(Squads.OpenCode.Client, [])
      |> Keyword.get(:base_url, "http://127.0.0.1:4096")
  end

  @doc """
  Scans for local OpenCode processes using lsof.
  Deduplicated logic from Sessions and Discovery.
  """
  def list_local_listeners do
    case System.find_executable("lsof") do
      nil ->
        []

      _executable ->
        case System.cmd("lsof", ["-nP", "-iTCP", "-sTCP:LISTEN"]) do
          {output, 0} ->
            output
            |> String.split("\n", trim: true)
            |> Enum.filter(&Regex.match?(~r/\bopencode\b/i, &1))
            |> Enum.map(&parse_lsof_line/1)
            |> Enum.reject(&is_nil/1)
            |> Enum.uniq()

          _ ->
            []
        end
    end
  rescue
    _ -> []
  end

  defp parse_lsof_line(line) do
    case Regex.run(~r/:(\d+)\s+\(LISTEN\)/, line) do
      [_, port] -> "http://127.0.0.1:#{port}"
      _ -> nil
    end
  end
end
