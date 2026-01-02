defmodule SquadsWeb.EventSocket do
  @behaviour Phoenix.Socket.Transport

  def child_spec(_opts) do
    # We won't spawn any process, so this can return a dummy task
    %{
      id: __MODULE__,
      start: {Task, :start_link, [fn -> :process.sleep(:infinity) end]},
      type: :worker
    }
  end

  def connect(map) do
    # You can inspect query params here if needed
    # %{params: %{"token" => token}} = map
    {:ok, %{project_id: nil}}
  end

  def init(state) do
    # Send a welcome message
    {:ok, state}
  end

  def handle_in({text, _opts}, state) do
    case Jason.decode(text) do
      {:ok, %{"type" => "join", "project_id" => project_id}} ->
        # Subscribe to the project topic
        Phoenix.PubSub.subscribe(Squads.PubSub, "project:#{project_id}:events")

        {:reply, :ok, {:text, Jason.encode!(%{type: "joined", project_id: project_id})},
         Map.put(state, :project_id, project_id)}

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

    {:push, {:text, payload}, state}
  end

  def handle_info(_, state), do: {:ok, state}

  def terminate(_reason, _state), do: :ok
end
