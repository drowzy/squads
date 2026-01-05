defmodule Squads.Sessions.Queries do
  @moduledoc """
  Read-only queries for the Sessions context.
  """

  import Ecto.Query, warn: false
  alias Squads.Repo
  alias Squads.Sessions.Session

  @doc """
  Returns all sessions.
  """
  def list_sessions do
    Session
    |> order_by(desc: :inserted_at)
    |> Repo.all()
  end

  @doc """
  Returns sessions for a specific agent.
  """
  def list_sessions_for_agent(agent_id) do
    Session
    |> where(agent_id: ^agent_id)
    |> order_by(desc: :inserted_at)
    |> Repo.all()
  end

  @doc """
  Returns sessions by status.
  """
  def list_sessions_by_status(status) when is_binary(status) do
    statuses = String.split(status, ",")

    Session
    |> where([s], s.status in ^statuses)
    |> order_by(desc: :inserted_at)
    |> Repo.all()
  end

  @doc """
  Returns sessions for a specific agent and status.
  """
  def list_sessions_by_agent_and_status(agent_id, status) do
    statuses = String.split(status, ",")

    Session
    |> where(agent_id: ^agent_id)
    |> where([s], s.status in ^statuses)
    |> order_by(desc: :inserted_at)
    |> Repo.all()
  end

  @doc """
  Returns running sessions.
  """
  def list_running_sessions do
    list_sessions_by_status("running")
  end

  @doc """
  Returns all sessions for a specific ticket.
  """
  def list_sessions_for_ticket(ticket_id) do
    Session
    |> where(ticket_id: ^ticket_id)
    |> order_by(desc: :inserted_at)
    |> Repo.all()
  end

  @doc """
  Gets a session by ID. Raises if not found.
  Deprecated: use fetch_session/1.
  """
  def get_session!(id), do: Repo.get!(Session, id)

  @doc """
  Gets a session by ID. Returns nil if not found.
  """
  def get_session(id), do: Repo.get(Session, id)

  @doc """
  Gets a session by OpenCode session ID. Returns nil if not found.
  """
  def get_session_by_opencode_id(opencode_session_id) do
    Repo.get_by(Session, opencode_session_id: opencode_session_id)
  end

  @doc """
  Gets a session with its associated ticket preloaded. Returns nil if not found.
  """
  def get_session_with_ticket(session_id) do
    Session
    |> where(id: ^session_id)
    |> preload(:ticket)
    |> Repo.one()
  end

  @doc """
  Gets a session by ID. Returns `{:ok, session}` or `{:error, :not_found}`.
  """
  def fetch_session(id) do
    case Repo.get(Session, id) do
      nil -> {:error, :not_found}
      session -> {:ok, session}
    end
  end

  @doc """
  Gets a session by OpenCode session ID. Returns `{:ok, session}` or `{:error, :not_found}`.
  """
  def fetch_session_by_opencode_id(opencode_session_id) do
    case Repo.get_by(Session, opencode_session_id: opencode_session_id) do
      nil -> {:error, :not_found}
      session -> {:ok, session}
    end
  end

  @doc """
  Gets a session with its associated ticket preloaded. Returns `{:ok, session}` or `{:error, :not_found}`.
  """
  def fetch_session_with_ticket(session_id) do
    Session
    |> where(id: ^session_id)
    |> preload(:ticket)
    |> Repo.one()
    |> case do
      nil -> {:error, :not_found}
      session -> {:ok, session}
    end
  end
end
