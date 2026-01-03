defmodule SquadsWeb.API.ExternalNodeController do
  use SquadsWeb, :controller

  alias Squads.OpenCode.Discovery

  def index(conn, _params) do
    nodes = Discovery.discover_nodes()
    render(conn, :index, nodes: nodes)
  end

  def probe(conn, %{"url" => url}) do
    case Discovery.probe_node(url) do
      {:ok, node} ->
        render(conn, :show, node: Map.put(node, :source, :manual))

      {:error, _reason} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Node unreachable"})
    end
  end
end
