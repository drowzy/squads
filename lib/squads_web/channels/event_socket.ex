defmodule SquadsWeb.EventSocket do
  @moduledoc """
  WebSocket handler for real-time event streaming.

  Clients connect and send a join message to subscribe to project events:

      {"type": "join", "project_id": "uuid"}

  Server responds with:

      {"type": "joined", "project_id": "uuid"}

  Then pushes events as they occur:

      {"type": "event", "data": {...}}
  """

  require Logger

  def init(_args) do
    {:ok, %{project_id: nil}}
  end

  def handle_in({text, [opcode: :text]}, state) do
    case Jason.decode(text) do
      {:ok, %{"type" => "join", "project_id" => project_id}} when is_binary(project_id) ->
        # Unsubscribe from old project if switching
        if state.project_id do
          Phoenix.PubSub.unsubscribe(Squads.PubSub, "project:#{state.project_id}:events")
        end

        Phoenix.PubSub.subscribe(Squads.PubSub, "project:#{project_id}:events")
        reply = Jason.encode!(%{type: "joined", project_id: project_id})
        {:reply, :ok, {:text, reply}, %{state | project_id: project_id}}

      {:ok, %{"type" => "ping"}} ->
        reply = Jason.encode!(%{type: "pong"})
        {:reply, :ok, {:text, reply}, state}

      {:ok, _other} ->
        {:ok, state}

      {:error, _} ->
        {:ok, state}
    end
  end

  def handle_in({_data, [opcode: :binary]}, state) do
    # Ignore binary frames
    {:ok, state}
  end

  def handle_in({_data, [opcode: :ping]}, state) do
    {:reply, :ok, {:pong, ""}, state}
  end

  def handle_in({_data, [opcode: :pong]}, state) do
    {:ok, state}
  end

  def handle_info({:event, event}, state) do
    # Safely extract event data, handling Ecto structs
    payload =
      Jason.encode!(%{
        type: "event",
        data: %{
          id: event.id,
          kind: event.kind,
          payload: event.payload || %{},
          occurred_at: to_string(event.occurred_at)
        }
      })

    {:push, {:text, payload}, state}
  end

  def handle_info(_msg, state) do
    {:ok, state}
  end

  def terminate(_reason, state) do
    # Clean up PubSub subscription
    if state.project_id do
      Phoenix.PubSub.unsubscribe(Squads.PubSub, "project:#{state.project_id}:events")
    end

    :ok
  end
end
