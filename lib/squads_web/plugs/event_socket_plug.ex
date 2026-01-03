defmodule SquadsWeb.EventSocketPlug do
  @moduledoc """
  Plug that upgrades HTTP connections to WebSocket for the event stream.
  """
  import Plug.Conn

  def init(options), do: options

  def call(conn, _opts) do
    if conn.request_path == "/socket/websocket" and websocket_upgrade?(conn) do
      conn
      |> WebSockAdapter.upgrade(SquadsWeb.EventSocket, [], timeout: 60_000)
      |> halt()
    else
      conn
    end
  end

  defp websocket_upgrade?(conn) do
    # Check for proper WebSocket upgrade headers
    upgrade_header =
      conn
      |> get_req_header("upgrade")
      |> List.first()
      |> case do
        nil -> ""
        val -> String.downcase(val)
      end

    upgrade_header == "websocket"
  end
end
