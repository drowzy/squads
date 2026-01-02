defmodule SquadsWeb.ProjectEventsChannel do
  use SquadsWeb, :channel

  def join("project:" <> project_id, _payload, socket) do
    {:ok, assign(socket, :project_id, project_id)}
  end
end
