defmodule SquadsWeb.EventSocket do
  @behaviour WebSock

  def init(_args) do
    {:ok, %{project_id: nil}}
  end

  def handle_in({text, _opts}, state) do
    case Jason.decode(text) do
      {:ok, %{"type" => "join", "project_id" => project_id}} ->
        # Subscribe to the project topic
        Phoenix.PubSub.subscribe(Squads.PubSub, "project:#{project_id}:events")

        reply = Jason.encode!(%{type: "joined", project_id: project_id})
        {:reply, :text, reply, Map.put(state, :project_id, project_id)}

      _ ->
        {:ok, state}
    end
  end

  def handle_info({:event, event}, state) do
    # Broadcast event to client
    payload =
      Jason.encode!(%{
        type: "event",
        data: %{
          id: event.id,
          kind: event.kind,
          payload: event.payload,
          occurred_at: event.occurred_at
        }
      })

    {:push, :text, payload, state}
  end

  def handle_info(_, state), do: {:ok, state}

  def terminate(_reason, _state), do: :ok
end
