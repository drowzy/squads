defmodule SquadsWeb.API.EventJSON do
  def index(%{events: events}) do
    %{data: for(event <- events, do: data(event))}
  end

  def show(%{event: event}) do
    %{data: data(event)}
  end

  defp data(event) do
    %{
      id: event.id,
      kind: event.kind,
      payload: event.payload,
      occurred_at: event.occurred_at,
      project_id: event.project_id,
      session_id: event.session_id,
      agent_id: event.agent_id
    }
  end
end
