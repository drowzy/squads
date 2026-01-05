defmodule Squads.Events do
  @moduledoc """
  The Events context manages the append-only event log.

  Events track all significant actions in the system for traceability
  and audit purposes. Events are immutable once created.
  """

  import Ecto.Query, warn: false
  alias Squads.Repo
  alias Squads.Events.Event
  alias Phoenix.PubSub

  @doc """
  Subscribes to events for a project.
  """
  def subscribe(project_id) do
    PubSub.subscribe(Squads.PubSub, "project:#{project_id}:events")
  end

  @doc """
  Creates a new event.
  """
  @spec create_event(map()) :: {:ok, Event.t()} | {:error, Ecto.Changeset.t()}
  def create_event(attrs) do
    %Event{}
    |> Event.changeset(attrs)
    |> Repo.insert()
    |> case do
      {:ok, event} ->
        broadcast(event)
        {:ok, event}

      error ->
        error
    end
  end

  defp broadcast(%Event{} = event) do
    PubSub.broadcast(Squads.PubSub, "project:#{event.project_id}:events", {:event, event})
    event
  end

  @doc """
  Lists events for a project, most recent first.
  """
  @spec list_events_for_project(Ecto.UUID.t(), keyword()) :: [Event.t()]
  def list_events_for_project(project_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 100)

    Event
    |> where(project_id: ^project_id)
    |> order_by(desc: :occurred_at)
    |> limit(^limit)
    |> Repo.all()
  end

  @doc """
  Lists events for a session.
  """
  @spec list_events_for_session(Ecto.UUID.t(), keyword()) :: [Event.t()]
  def list_events_for_session(session_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 100)

    Event
    |> where(session_id: ^session_id)
    |> order_by(desc: :occurred_at)
    |> limit(^limit)
    |> Repo.all()
  end

  @doc """
  Lists events for an agent.
  """
  @spec list_events_for_agent(Ecto.UUID.t(), keyword()) :: [Event.t()]
  def list_events_for_agent(agent_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 100)

    Event
    |> where(agent_id: ^agent_id)
    |> order_by(desc: :occurred_at)
    |> limit(^limit)
    |> Repo.all()
  end

  @doc """
  Lists events by kind.
  """
  @spec list_events_by_kind(String.t(), keyword()) :: [Event.t()]
  def list_events_by_kind(kind, opts \\ []) do
    project_id = Keyword.get(opts, :project_id)
    limit = Keyword.get(opts, :limit, 100)

    query = Event |> where(kind: ^kind) |> order_by(desc: :occurred_at) |> limit(^limit)

    query =
      if project_id do
        where(query, project_id: ^project_id)
      else
        query
      end

    Repo.all(query)
  end

  @doc """
  Gets events since a given timestamp.
  """
  @spec list_events_since(DateTime.t(), keyword()) :: [Event.t()]
  def list_events_since(since, opts \\ []) do
    project_id = Keyword.get(opts, :project_id)
    limit = Keyword.get(opts, :limit, 100)

    query =
      Event
      |> where([e], e.occurred_at > ^since)
      |> order_by(asc: :occurred_at)
      |> limit(^limit)

    query =
      if project_id do
        where(query, project_id: ^project_id)
      else
        query
      end

    Repo.all(query)
  end

  @doc """
  Counts events by kind for a project.
  """
  @spec count_events_by_kind(Ecto.UUID.t()) :: map()
  def count_events_by_kind(project_id) do
    Event
    |> where(project_id: ^project_id)
    |> group_by(:kind)
    |> select([e], {e.kind, count(e.id)})
    |> Repo.all()
    |> Map.new()
  end
end
