defmodule SquadsWeb.API.SessionController do
  @moduledoc """
  API controller for session lifecycle management.

  Provides endpoints to create, list, start, stop, and query sessions.
  """
  use SquadsWeb, :controller

  alias Squads.Sessions

  action_fallback SquadsWeb.FallbackController

  @doc """
  List all sessions, optionally filtered by status or agent.

  GET /api/sessions
  GET /api/sessions?status=running
  GET /api/sessions?agent_id=uuid
  """
  def index(conn, params) do
    cond do
      params["status"] ->
        sessions = Sessions.list_sessions_by_status(params["status"])
        render(conn, :index, sessions: sessions)

      agent_id = params["agent_id"] ->
        case Ecto.UUID.cast(agent_id) do
          {:ok, uuid} ->
            sessions = Sessions.list_sessions_for_agent(uuid)
            render(conn, :index, sessions: sessions)

          :error ->
            # Return empty list for invalid agent ID, or 404.
            # Returning empty list is safer for "list" endpoints unless we want strict validation.
            # Given list_sessions_for_agent queries by agent_id, empty is appropriate.
            render(conn, :index, sessions: [])
        end

      true ->
        sessions = Sessions.list_sessions()
        render(conn, :index, sessions: sessions)
    end
  end

  @doc """
  Get a specific session.

  GET /api/sessions/:id
  """
  def show(conn, %{"id" => id}) do
    case Ecto.UUID.cast(id) do
      {:ok, uuid} ->
        with_session(uuid, fn session ->
          render(conn, :show, session: session)
        end)

      :error ->
        {:error, :not_found}
    end
  end

  @doc """
  Create a new session.

  POST /api/sessions
  Body: { "agent_id": "uuid", "ticket_key": "bd-123", "title": "optional" }
  """
  def create(conn, params) do
    attrs = Sessions.normalize_params(params)

    case Sessions.create_session(attrs) do
      {:ok, session} ->
        conn
        |> put_status(:created)
        |> render(:show, session: session)

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  @doc """
  Create and immediately start a session on OpenCode.

  POST /api/sessions/start
  Body: { "agent_id": "uuid", "ticket_key": "bd-123", "title": "Work on feature" }
  """
  def start(conn, params) do
    attrs = Sessions.normalize_params(params)

    case Sessions.create_and_start_session(attrs) do
      {:ok, session} ->
        conn
        |> put_status(:created)
        |> render(:show, session: session)

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  @doc """
  Start an existing pending session.

  POST /api/sessions/:session_id/start
  """
  def start_existing(conn, %{"session_id" => id} = params) do
    with_session(id, fn session ->
      opts = if params["title"], do: [title: params["title"]], else: []
      Sessions.start_session(session, opts)
    end)
    |> case do
      {:ok, session} -> render(conn, :show, session: session)
      error -> error
    end
  end

  @doc """
  Stop a running session.

  POST /api/sessions/:session_id/stop
  Body: { "exit_code": 0 } (optional)
  """
  def stop(conn, %{"session_id" => id} = params) do
    with_session(id, fn session ->
      exit_code = params["exit_code"] || 0
      Sessions.stop_session(session, exit_code)
    end)
    |> case do
      {:ok, session} -> render(conn, :show, session: session)
      error -> error
    end
  end

  @doc """
  Cancel a pending session.

  POST /api/sessions/:session_id/cancel
  """
  def cancel(conn, %{"session_id" => id}) do
    with_session(id, fn session ->
      Sessions.cancel_session(session)
    end)
    |> case do
      {:ok, session} -> render(conn, :show, session: session)
      error -> error
    end
  end

  @doc """
  Get messages from a session.

  GET /api/sessions/:session_id/messages
  GET /api/sessions/:session_id/messages?limit=50
  """
  def messages(conn, %{"session_id" => id} = params) do
    with_session(id, fn session ->
      opts = if params["limit"], do: [limit: String.to_integer(params["limit"])], else: []
      Sessions.get_messages(session, opts)
    end)
    |> case do
      {:ok, messages} -> json(conn, %{data: messages})
      error -> error
    end
  end

  @doc """
  Get the diff for a session.

  GET /api/sessions/:session_id/diff
  """
  def diff(conn, %{"session_id" => id}) do
    with_session(id, fn session ->
      Sessions.get_diff(session)
    end)
    |> case do
      {:ok, diff} -> json(conn, %{data: diff})
      error -> error
    end
  end

  @doc """
  Get the todo list for a session.

  GET /api/sessions/:session_id/todos
  """
  def todos(conn, %{"session_id" => id}) do
    with_session(id, fn session ->
      Sessions.get_todos(session)
    end)
    |> case do
      {:ok, todos} -> json(conn, %{data: todos})
      error -> error
    end
  end

  # ============================================================================
  # Dispatch Endpoints
  # ============================================================================

  @doc """
  Send a prompt/message to a session.

  POST /api/sessions/:session_id/prompt
  Body: { "prompt": "Fix the bug in auth.ex" }
  Body: { "prompt": "Hello", "model": "anthropic/claude-sonnet-4-5", "agent": "coder" }
  """
  def prompt(conn, %{"session_id" => id, "prompt" => prompt} = params) do
    with_session(id, fn session ->
      opts =
        []
        |> maybe_add(:model, params["model"])
        |> maybe_add(:agent, params["agent"])
        |> maybe_add(:no_reply, params["no_reply"])

      Sessions.send_prompt(session, prompt, opts)
    end)
    |> case do
      {:ok, response} -> json(conn, %{data: response})
      error -> error
    end
  end

  def prompt(conn, %{"session_id" => _}) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "missing_prompt", message: "prompt is required"})
  end

  @doc """
  Send a prompt asynchronously to a session (fire and forget).

  POST /api/sessions/:session_id/prompt_async
  Body: { "prompt": "Run the tests" }
  """
  def prompt_async(conn, %{"session_id" => id, "prompt" => prompt} = params) do
    with_session(id, fn session ->
      opts =
        []
        |> maybe_add(:model, params["model"])
        |> maybe_add(:agent, params["agent"])

      Sessions.send_prompt_async(session, prompt, opts)
    end)
    |> case do
      {:ok, response} ->
        conn
        |> put_status(:accepted)
        |> json(%{data: response})

      error ->
        error
    end
  end

  def prompt_async(conn, %{"session_id" => _}) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "missing_prompt", message: "prompt is required"})
  end

  @doc """
  Execute a slash command in a session.

  POST /api/sessions/:session_id/command
  Body: { "command": "/help" }
  Body: { "command": "/compact", "arguments": "all" }
  """
  def command(conn, %{"session_id" => id, "command" => command} = params) do
    with_session(id, fn session ->
      opts =
        []
        |> maybe_add(:arguments, params["arguments"])
        |> maybe_add(:agent, params["agent"])
        |> maybe_add(:model, params["model"])

      Sessions.execute_command(session, command, opts)
    end)
    |> case do
      {:ok, response} -> json(conn, %{data: response})
      error -> error
    end
  end

  def command(conn, %{"session_id" => _}) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "missing_command", message: "command is required"})
  end

  @doc """
  Run a shell command in a session.

  POST /api/sessions/:session_id/shell
  Body: { "command": "mix test" }
  Body: { "command": "git status", "agent": "coder" }
  """
  def shell(conn, %{"session_id" => id, "command" => command} = params) do
    with_session(id, fn session ->
      opts =
        []
        |> maybe_add(:agent, params["agent"])
        |> maybe_add(:model, params["model"])

      Sessions.run_shell(session, command, opts)
    end)
    |> case do
      {:ok, response} -> json(conn, %{data: response})
      error -> error
    end
  end

  def shell(conn, %{"session_id" => _}) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "missing_command", message: "command is required"})
  end

  # Helper to fetch a session or return not found
  defp with_session(id, fun) do
    case Sessions.get_session(id) do
      nil -> {:error, :not_found}
      session -> fun.(session)
    end
  end

  defp maybe_add(opts, _key, nil), do: opts
  defp maybe_add(opts, key, value), do: Keyword.put(opts, key, value)
end
