defmodule SquadsWeb.API.EventStream do
  @moduledoc """
  Encapsulates SSE streaming logic for Events.
  """
  import Plug.Conn
  alias SquadsWeb.API.EventJSON

  @doc """
  Performs the SSE handshake and enters the message loop.
  """
  def stream(conn, project_id) do
    conn =
      conn
      |> put_resp_header("content-type", "text/event-stream")
      |> put_resp_header("cache-control", "no-cache")
      |> put_resp_header("connection", "keep-alive")
      |> send_chunked(200)

    # Subscribe to project events
    Squads.Events.subscribe(project_id)

    # Initial ping
    {:ok, conn} =
      chunk(
        conn,
        "event: ping\ndata: {\"status\":\"connected\",\"project_id\":\"#{project_id}\"}\n\n"
      )

    loop(conn)
  end

  defp loop(conn) do
    receive do
      {:event, event} ->
        data = EventJSON.show(%{event: event})

        case chunk(conn, "event: event\ndata: #{Jason.encode!(data)}\n\n") do
          {:ok, conn} -> loop(conn)
          {:error, _reason} -> conn
        end

      _ ->
        loop(conn)
    after
      30_000 ->
        case chunk(conn, "event: ping\ndata: {\"status\":\"keep-alive\"}\n\n") do
          {:ok, conn} -> loop(conn)
          {:error, _reason} -> conn
        end
    end
  end
end
