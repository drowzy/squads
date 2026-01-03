defmodule SquadsWeb.API.ExternalNodeJSON do
  def index(%{nodes: nodes}) do
    %{data: Enum.map(nodes, &data/1)}
  end

  def show(%{node: node}) do
    %{data: data(node)}
  end

  defp data(node) do
    %{
      base_url: node.base_url,
      healthy: node.healthy,
      version: node.version,
      source: node.source,
      last_seen_at: node.last_seen_at
    }
  end
end
