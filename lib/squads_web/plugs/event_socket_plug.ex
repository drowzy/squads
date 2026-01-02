defmodule SquadsWeb.EventSocketPlug do
  import Plug.Conn

  def init(options), do: options

  def call(conn, _opts) do
    if conn.request_path == "/socket/websocket" do
      conn
      |> WebSockAdapter.upgrade(SquadsWeb.EventSocket, [], compress: false, timeout: 60_000)
      |> halt()
    else
      conn
    end
  end
end
