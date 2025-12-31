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
    sessions =
      cond do
        params["status"] ->
          Sessions.list_sessions_by_status(params["status"])

        params["agent_id"] ->
          Sessions.list_sessions_for_agent(params["agent_id"])

        true ->
          Sessions.list_sessions()
      end

    render(conn, :index, sessions: sessions)
  end

  @doc """
  Get a specific session.

  GET /api/sessions/:id
  """
  def show(conn, %{"id" => id}) do
    with_session(id, fn session ->
      render(conn, :show, session: session)
    end)
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

      case Sessions.start_session(session, opts) do
        {:ok, session} ->
          render(conn, :show, session: session)

        {:error, :already_started} ->
          conn
          |> put_status(:conflict)
          |> json(%{error: "already_started", message: "Session has already been started"})

        {:error, {:opencode_error, _reason}} = error ->
          error
      end
    end)
  end

  @doc """
  Stop a running session.

  POST /api/sessions/:session_id/stop
  Body: { "exit_code": 0 } (optional)
  """
  def stop(conn, %{"session_id" => id} = params) do
    with_session(id, fn session ->
      exit_code = params["exit_code"] || 0

      case Sessions.stop_session(session, exit_code) do
        {:ok, session} ->
          render(conn, :show, session: session)

        {:error, :not_running} ->
          conn
          |> put_status(:conflict)
          |> json(%{error: "not_running", message: "Session is not running"})

        {:error, {:opencode_error, _reason}} = error ->
          error
      end
    end)
  end

  @doc """
  Cancel a pending session.

  POST /api/sessions/:session_id/cancel
  """
  def cancel(conn, %{"session_id" => id}) do
    with_session(id, fn session ->
      case Sessions.cancel_session(session) do
        {:ok, session} ->
          render(conn, :show, session: session)

        {:error, :already_started} ->
          conn
          |> put_status(:conflict)
          |> json(%{
            error: "already_started",
            message: "Cannot cancel a session that has already started"
          })
      end
    end)
  end

  @doc """
  Get messages from a session.

  GET /api/sessions/:session_id/messages
  GET /api/sessions/:session_id/messages?limit=50
  """
  def messages(conn, %{"session_id" => id} = params) do
    with_session(id, fn session ->
      opts = if params["limit"], do: [limit: String.to_integer(params["limit"])], else: []

      case Sessions.get_messages(session, opts) do
        {:ok, messages} ->
          json(conn, %{data: messages})

        {:error, :no_opencode_session} ->
          conn
          |> put_status(:conflict)
          |> json(%{error: "no_opencode_session", message: "Session has no OpenCode session"})

        {:error, {:opencode_error, _reason}} = error ->
          error
      end
    end)
  end

  @doc """
  Get the diff for a session.

  GET /api/sessions/:session_id/diff
  """
  def diff(conn, %{"session_id" => id}) do
    with_session(id, fn session ->
      case Sessions.get_diff(session) do
        {:ok, diff} ->
          json(conn, %{data: diff})

        {:error, :no_opencode_session} ->
          conn
          |> put_status(:conflict)
          |> json(%{error: "no_opencode_session", message: "Session has no OpenCode session"})

        {:error, {:opencode_error, _reason}} = error ->
          error
      end
    end)
  end

  @doc """
  Get the todo list for a session.

  GET /api/sessions/:session_id/todos
  """
  def todos(conn, %{"session_id" => id}) do
    with_session(id, fn session ->
      case Sessions.get_todos(session) do
        {:ok, todos} ->
          json(conn, %{data: todos})

        {:error, :no_opencode_session} ->
          conn
          |> put_status(:conflict)
          |> json(%{error: "no_opencode_session", message: "Session has no OpenCode session"})

        {:error, {:opencode_error, _reason}} = error ->
          error
      end
    end)
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

      case Sessions.send_prompt(session, prompt, opts) do
        {:ok, response} ->
          json(conn, %{data: response})

        {:error, :session_not_active} ->
          conn
          |> put_status(:conflict)
          |> json(%{error: "session_not_active", message: "Session is not running"})

        {:error, :no_opencode_session} ->
          conn
          |> put_status(:conflict)
          |> json(%{error: "no_opencode_session", message: "Session has no OpenCode session"})

        {:error, {:opencode_error, _reason}} = error ->
          error
      end
    end)
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

      case Sessions.send_prompt_async(session, prompt, opts) do
        {:ok, response} ->
          conn
          |> put_status(:accepted)
          |> json(%{data: response})

        {:error, :session_not_active} ->
          conn
          |> put_status(:conflict)
          |> json(%{error: "session_not_active", message: "Session is not running"})

        {:error, :no_opencode_session} ->
          conn
          |> put_status(:conflict)
          |> json(%{error: "no_opencode_session", message: "Session has no OpenCode session"})

        {:error, {:opencode_error, _reason}} = error ->
          error
      end
    end)
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

      case Sessions.execute_command(session, command, opts) do
        {:ok, response} ->
          json(conn, %{data: response})

        {:error, :session_not_active} ->
          conn
          |> put_status(:conflict)
          |> json(%{error: "session_not_active", message: "Session is not running"})

        {:error, :no_opencode_session} ->
          conn
          |> put_status(:conflict)
          |> json(%{error: "no_opencode_session", message: "Session has no OpenCode session"})

        {:error, {:opencode_error, _reason}} = error ->
          error
      end
    end)
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

      case Sessions.run_shell(session, command, opts) do
        {:ok, response} ->
          json(conn, %{data: response})

        {:error, :session_not_active} ->
          conn
          |> put_status(:conflict)
          |> json(%{error: "session_not_active", message: "Session is not running"})

        {:error, :no_opencode_session} ->
          conn
          |> put_status(:conflict)
          |> json(%{error: "no_opencode_session", message: "Session has no OpenCode session"})

        {:error, {:opencode_error, _reason}} = error ->
          error
      end
    end)
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
