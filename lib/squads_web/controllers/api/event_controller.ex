defmodule SquadsWeb.API.EventController do
  use SquadsWeb, :controller

  alias Squads.Events
  alias SquadsWeb.API.EventStream

  def index(conn, params) do
    opts = parse_opts(params)

    events =
      cond do
        id = params["project_id"] -> Events.list_events_for_project(id, opts)
        id = params["session_id"] -> Events.list_events_for_session(id, opts)
        id = params["agent_id"] -> Events.list_events_for_agent(id, opts)
        true -> []
      end

    render(conn, :index, events: events)
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
