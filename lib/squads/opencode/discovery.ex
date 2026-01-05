defmodule Squads.OpenCode.Discovery do
  @moduledoc """
  Subsystem for discovering external OpenCode nodes.
  """

  require Logger
  alias Squads.OpenCode.Resolver

  @type node_info :: %{
          base_url: String.t(),
          healthy: boolean(),
          version: String.t() | nil,
          source: atom(),
          last_seen_at: DateTime.t()
        }

  @doc """
  Discover reachable OpenCode nodes from all configured providers.
  """
  def discover_nodes do
    [
      discover_from_config(),
      discover_from_local_ports()
    ]
    |> List.flatten()
    |> Enum.uniq_by(& &1.base_url)
  end

  defp discover_from_config do
    # Read from application config
    config_urls = Application.get_env(:squads, :external_nodes, [])

    config_urls
    |> Enum.map(&probe_node/1)
    |> Enum.filter(fn
      {:ok, _} -> true
      _ -> false
    end)
    |> Enum.map(fn {:ok, node} -> Map.put(node, :source, :config) end)
  end

  defp discover_from_local_ports do
    # Only run on dev/darwin/linux; skip on Windows or if explicitly disabled
    if Application.get_env(:squads, :enable_local_discovery, true) do
      Resolver.list_local_listeners()
      |> Enum.map(fn %{port: port} -> "http://127.0.0.1:#{port}" end)
      |> Enum.map(&probe_node/1)
      |> Enum.filter(fn
        {:ok, _} -> true
        _ -> false
      end)
      |> Enum.map(fn {:ok, node} -> Map.put(node, :source, :local_lsof) end)
    else
      []
    end
  end

  @doc """
  Check health of a specific URL to see if it's an OpenCode node.
  """
  def probe_node(base_url) do
    case Squads.OpenCode.Client.health(base_url: base_url, timeout: 1000, retry_count: 0) do
      {:ok, %{"healthy" => true, "version" => version}} ->
        {:ok,
         %{
           base_url: base_url,
           healthy: true,
           version: version,
           last_seen_at: DateTime.utc_now()
         }}

      _ ->
        {:error, :unreachable}
    end
  end
end
