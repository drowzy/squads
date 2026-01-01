defmodule SquadsWeb.API.EventController do
  use SquadsWeb, :controller

  alias Squads.Events
  alias SquadsWeb.API.EventStream

  def index(conn, params) do
    opts = parse_opts(params)

    cond do
      id = params["project_id"] ->
        case Ecto.UUID.cast(id) do
          {:ok, uuid} ->
            events = Events.list_events_for_project(uuid, opts)
            render(conn, :index, events: events)

          :error ->
            render(conn, :index, events: [])
        end

      id = params["session_id"] ->
        case Ecto.UUID.cast(id) do
          {:ok, uuid} ->
            events = Events.list_events_for_session(uuid, opts)
            render(conn, :index, events: events)

          :error ->
            render(conn, :index, events: [])
        end

      id = params["agent_id"] ->
        case Ecto.UUID.cast(id) do
          {:ok, uuid} ->
            events = Events.list_events_for_agent(uuid, opts)
            render(conn, :index, events: events)

          :error ->
            render(conn, :index, events: [])
        end

      true ->
        # No filter provided, return empty list or all events?
        # Original code returned empty list for no filter.
        render(conn, :index, events: [])
    end
  end

  defp parse_opts(params) do
    case Integer.parse(params["limit"] || "") do
      {limit, _} -> [limit: limit]
      :error -> []
    end
  end

  def stream(conn, %{"project_id" => project_id}) do
    EventStream.stream(conn, project_id)
  end
end
