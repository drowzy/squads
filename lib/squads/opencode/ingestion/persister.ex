defmodule Squads.OpenCode.Ingestion.Persister do
  @moduledoc """
  A supervised task that handles the persistence of events.
  Used to decouple ingestion (SSE parsing) from database writes.
  """
  use Task

  require Logger
  alias Squads.Events

  def start_link(arg) do
    Task.start_link(__MODULE__, :run, [arg])
  end

  def run({kind, payload, project_id}) do
    # Validate kind is in allowed list before persisting
    # We trust the caller (EventIngester) to map raw events to valid internal kinds,
    # but we double check against the schema definition implicitly via changeset if needed.
    # The requirement says: "Remove the redundant kind pre-check or replace it with a warning while relying on changeset validation."

    # So we just try to create it.
    attrs = %{
      kind: kind,
      payload: payload,
      project_id: project_id
    }

    case Events.create_event(attrs) do
      {:ok, _event} ->
        :ok

      {:error, changeset} ->
        # Just log warning, don't crash the task so the supervisor doesn't restart it endlessly if data is bad
        Logger.warning("Failed to persist event #{kind}: #{inspect(changeset.errors)}")
        :error
    end
  end
end
