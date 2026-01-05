defmodule Squads.MCP.Catalog do
  @moduledoc """
  Fetches and caches MCP catalog entries from Docker's MCP registry.
  """

  require Logger

  @registry_api Application.compile_env(
                  :squads,
                  [__MODULE__, :registry_api],
                  "https://api.github.com/repos/docker/mcp-registry/contents/servers"
                )
  @registry_raw Application.compile_env(
                  :squads,
                  [__MODULE__, :registry_raw],
                  "https://raw.githubusercontent.com/docker/mcp-registry/main/servers"
                )
  @registry_tarball Application.compile_env(
                      :squads,
                      [__MODULE__, :registry_tarball],
                      "https://codeload.github.com/docker/mcp-registry/tar.gz/refs/heads/main"
                    )
  @cache_ttl_seconds Application.compile_env(
                       :squads,
                       [__MODULE__, :cache_ttl_seconds],
                       900
                     )

  @cache_key {__MODULE__, :catalog}

  @doc """
  Returns catalog entries with optional filters.
  """
  def list(opts \\ []) do
    with {:ok, entries} <- fetch_cached() do
      {:ok, apply_filters(entries, opts)}
    end
  end

  @doc """
  Forces a refresh of the catalog cache.
  """
  def refresh do
    fetch_and_cache()
  end

  defp fetch_cached do
    case :persistent_term.get(@cache_key, :miss) do
      {fetched_at, entries} ->
        if stale?(fetched_at) do
          fetch_and_cache()
        else
          {:ok, entries}
        end

      :miss ->
        fetch_and_cache()
    end
  end

  defp fetch_and_cache do
    with {:ok, entries} <- fetch_registry() do
      :persistent_term.put(@cache_key, {System.system_time(:second), entries})
      {:ok, entries}
    end
  end

  defp fetch_registry do
    with {:ok, servers} <- fetch_server_list() do
      servers
      |> Task.async_stream(&fetch_server_entry/1, max_concurrency: 6, timeout: 15_000)
      |> Enum.reduce_while({:ok, []}, fn
        {:ok, {:ok, entry}}, {:ok, acc} -> {:cont, {:ok, [entry | acc]}}
        {:ok, {:error, reason}}, _acc -> {:halt, {:error, reason}}
        {:exit, reason}, _acc -> {:halt, {:error, reason}}
      end)
      |> case do
        {:ok, entries} -> {:ok, Enum.sort_by(entries, & &1.name)}
        error -> error
      end
    end
  end

  defp fetch_server_list do
    headers = github_headers()

    case Req.get(@registry_api, headers: headers) do
      {:ok, %Req.Response{status: 200, body: body}} when is_list(body) ->
        server_names =
          body
          |> Enum.filter(fn entry -> entry["type"] == "dir" end)
          |> Enum.map(& &1["name"])

        {:ok, server_names}

      {:ok, %Req.Response{status: status, body: body}} ->
        case fetch_server_list_from_tarball() do
          {:ok, servers} -> {:ok, servers}
          {:error, _} -> {:error, {:http_error, status, body}}
        end

      {:error, reason} ->
        case fetch_server_list_from_tarball() do
          {:ok, servers} -> {:ok, servers}
          {:error, _} -> {:error, reason}
        end
    end
  end

  defp fetch_server_entry(name) do
    server_url = "#{@registry_raw}/#{name}/server.yaml"
    tools_url = "#{@registry_raw}/#{name}/tools.json"

    with {:ok, server_yaml} <- fetch_yaml(server_url),
         {:ok, tools} <- fetch_optional_json(tools_url) do
      {:ok, normalize_entry(name, server_yaml, tools)}
    else
      {:error, reason} ->
        Logger.error("MCP catalog entry fetch failed",
          name: name,
          server_url: server_url,
          tools_url: tools_url,
          reason: inspect(reason)
        )

        {:error, reason}
    end
  end

  defp fetch_server_list_from_tarball do
    case Req.get(@registry_tarball, headers: raw_headers()) do
      {:ok, %Req.Response{status: 200, body: body}} when is_binary(body) ->
        case :erl_tar.table({:binary, body}, [:compressed]) do
          {:ok, files} ->
            server_names =
              files
              |> Enum.map(&to_string/1)
              |> Enum.reduce(MapSet.new(), fn path, acc ->
                case server_name_from_path(path) do
                  nil -> acc
                  name -> MapSet.put(acc, name)
                end
              end)
              |> MapSet.to_list()

            {:ok, server_names}

          {:error, reason} ->
            {:error, {:tar_error, reason}}
        end

      {:ok, %Req.Response{status: status, body: body}} ->
        {:error, {:http_error, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp fetch_yaml(url) do
    case Req.get(url, headers: raw_headers()) do
      {:ok, %Req.Response{status: 200, body: body}} when is_binary(body) ->
        parse_yaml(body)

      {:ok, %Req.Response{status: status, body: body}} ->
        {:error, {:http_error, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp fetch_optional_json(url) do
    headers = github_headers()

    case Req.get(url, headers: headers) do
      {:ok, %Req.Response{status: 200, body: body}} ->
        {:ok, body}

      {:ok, %Req.Response{status: 404}} ->
        {:ok, nil}

      {:ok, %Req.Response{status: status, body: body}} ->
        {:error, {:http_error, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp parse_yaml(body) do
    try do
      case YamlElixir.read_from_string(body) do
        {:ok, parsed} -> {:ok, parsed}
        parsed -> {:ok, parsed}
      end
    rescue
      error -> {:error, {:invalid_yaml, Exception.message(error)}}
    end
  end

  defp normalize_entry(name, server_yaml, tools) do
    meta = server_yaml["meta"] || %{}
    about = server_yaml["about"] || %{}
    config = server_yaml["config"] || %{}
    run = server_yaml["run"] || %{}

    %{
      name: server_yaml["name"] || name,
      title: about["title"] || name,
      icon: about["icon"],
      category: meta["category"],
      tags: List.wrap(meta["tags"] || []),
      image: server_yaml["image"],
      secrets: List.wrap(config["secrets"] || []),
      oauth: List.wrap(server_yaml["oauth"] || []),
      run_env: run["env"] || %{},
      source: server_yaml["source"],
      tools: tools || [],
      raw: server_yaml
    }
  end

  defp apply_filters(entries, opts) do
    entries
    |> filter_query(opts[:query])
    |> filter_category(opts[:category])
    |> filter_tag(opts[:tag])
  end

  defp filter_query(entries, nil), do: entries

  defp filter_query(entries, query) do
    needle = String.downcase(query)

    Enum.filter(entries, fn entry ->
      String.contains?(String.downcase(entry.name), needle) ||
        String.contains?(String.downcase(entry.title || ""), needle)
    end)
  end

  defp filter_category(entries, nil), do: entries
  defp filter_category(entries, category), do: Enum.filter(entries, &(&1.category == category))

  defp filter_tag(entries, nil), do: entries
  defp filter_tag(entries, tag), do: Enum.filter(entries, &(tag in &1.tags))

  defp github_headers do
    base = [
      {"accept", "application/vnd.github+json"},
      {"user-agent", "squads"}
    ]

    case github_token() do
      nil -> base
      token -> [{"authorization", "Bearer #{token}"} | base]
    end
  end

  defp raw_headers do
    [{"user-agent", "squads"}]
  end

  defp github_token do
    Application.get_env(:squads, __MODULE__, [])[:github_token] ||
      System.get_env("MCP_REGISTRY_GITHUB_TOKEN") ||
      System.get_env("GITHUB_TOKEN")
  end

  defp server_name_from_path(path) do
    parts = String.split(path, "/", trim: true)

    case Enum.find_index(parts, &(&1 == "servers")) do
      nil -> nil
      index -> Enum.at(parts, index + 1)
    end
  end

  defp stale?(fetched_at) do
    System.system_time(:second) - fetched_at > @cache_ttl_seconds
  end
end
