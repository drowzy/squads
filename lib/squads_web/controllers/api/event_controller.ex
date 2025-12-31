defmodule SquadsWeb.API.EventController do
  use SquadsWeb, :controller

  alias Squads.Events
  alias SquadsWeb.API.EventStream

  def index(conn, params) do
    events =
      cond do
        id = params["project_id"] -> Events.list_events_for_project(id, params)
        id = params["session_id"] -> Events.list_events_for_session(id, params)
        id = params["agent_id"] -> Events.list_events_for_agent(id, params)
        true -> []
      end

    render(conn, :index, events: events)
  end

  def stream(conn, %{"project_id" => project_id}) do
    EventStream.stream(conn, project_id)
  end
end
