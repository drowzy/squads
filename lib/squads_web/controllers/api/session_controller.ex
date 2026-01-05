defmodule SquadsWeb.API.SessionController do
  @moduledoc """
  API controller for session lifecycle management.

  Provides endpoints to create, list, start, stop, and query sessions.
  """
  use SquadsWeb, :controller

  require Logger

  alias Squads.Sessions

  action_fallback SquadsWeb.FallbackController

  @doc """
  List all sessions, optionally filtered by status or agent.

  GET /api/sessions
  GET /api/sessions?status=running
  GET /api/sessions?agent_id=uuid
  GET /api/sessions?agent_id=uuid&status=running
  """
  def index(conn, params) do
    sessions =
      cond do
        params["agent_id"] && params["status"] ->
          Sessions.list_sessions_by_agent_and_status(params["agent_id"], params["status"])

        params["status"] ->
          Sessions.list_sessions_by_status(params["status"])

        params["agent_id"] ->
          case Ecto.UUID.cast(params["agent_id"]) do
            {:ok, uuid} -> Sessions.list_sessions_for_agent(uuid)
            :error -> []
          end

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
    with {:ok, uuid} <- Ecto.UUID.cast(id),
         {:ok, session} <- Sessions.fetch_session(uuid) do
      render(conn, :show, session: session)
    else
      :error -> {:error, :not_found}
      {:error, :not_found} -> {:error, :not_found}
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
    agent_id = attrs[:agent_id]

    case Sessions.new_session_for_agent(agent_id, attrs) do
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
    with {:ok, session} <- resolve_session(id) do
      opts = if params["title"], do: [title: params["title"]], else: []

      case Sessions.start_session(session, opts) do
        {:ok, session} -> render(conn, :show, session: session)
        error -> error
      end
    end
  end

  def stop(conn, %{"session_id" => id} = params) do
    with {:ok, session} <- resolve_session(id) do
      exit_code = params["exit_code"] || 0
      opts = [terminated_by: "user"]
      opts = if params["reason"], do: opts ++ [reason: params["reason"]], else: opts

      case Sessions.stop_session(session, exit_code, opts) do
        {:ok, session} -> render(conn, :show, session: session)
        error -> error
      end
    end
  end

  @doc """
  Abort a running session without finishing it.

  POST /api/sessions/:session_id/abort
  """
  def abort(conn, %{"session_id" => id} = params) do
    opts = if params["node_url"], do: [node_url: params["node_url"]], else: []

    case Sessions.dispatch_abort(id, opts) do
      {:ok, response} -> json(conn, %{data: response})
      error -> error
    end
  end

  @doc """
  Archive a session on OpenCode and mark it archived locally.

  POST /api/sessions/:session_id/archive
  """
  def archive(conn, %{"session_id" => id} = params) do
    opts = if params["node_url"], do: [node_url: params["node_url"]], else: []

    case Sessions.dispatch_archive(id, opts) do
      {:ok, session} when is_struct(session) -> render(conn, :show, session: session)
      {:ok, response} -> json(conn, %{data: response})
      error -> error
    end
  end

  @doc """
  Cancel a pending session.

  POST /api/sessions/:session_id/cancel
  """
  def cancel(conn, %{"session_id" => id}) do
    with {:ok, session} <- resolve_session(id),
         {:ok, session} <- Sessions.cancel_session(session) do
      render(conn, :show, session: session)
    end
  end

  def messages(conn, %{"session_id" => id} = params) do
    with {:ok, session} <- resolve_session(id) do
      opts = if params["limit"], do: [limit: String.to_integer(params["limit"])], else: []

      case Sessions.get_messages(session, opts) do
        {:ok, messages} -> json(conn, %{data: messages})
        error -> error
      end
    end
  end

  def diff(conn, %{"session_id" => id} = params) do
    with {:ok, session} <- resolve_session(id) do
      opts = if params["node_url"], do: [base_url: params["node_url"]], else: []

      case Sessions.get_diff(session, opts) do
        {:ok, diff} -> json(conn, %{data: diff})
        error -> error
      end
    end
  end

  def todos(conn, %{"session_id" => id} = params) do
    with {:ok, session} <- resolve_session(id) do
      opts = if params["node_url"], do: [base_url: params["node_url"]], else: []

      case Sessions.get_todos(session, opts) do
        {:ok, todos} -> json(conn, %{data: todos})
        error -> error
      end
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
    opts =
      params
      |> Map.take(["model", "agent", "no_reply", "node_url"])
      |> normalize_opts()

    case Sessions.dispatch_prompt(id, prompt, opts) do
      {:ok, response} ->
        json(conn, %{data: response})

      {:error, :session_not_active} ->
        {:error, :session_not_active}

      {:error, :no_opencode_session} ->
        {:error, :session_not_active}

      error ->
        error
    end
  end

  def prompt(_conn, %{"session_id" => _}) do
    {:error, :missing_prompt}
  end

  @doc """
  Send a prompt asynchronously to a session (fire and forget).

  POST /api/sessions/:session_id/prompt_async
  Body: { "prompt": "Run the tests" }
  """
  def prompt_async(conn, %{"session_id" => id, "prompt" => prompt} = params) do
    opts =
      params
      |> Map.take(["model", "agent", "node_url"])
      |> normalize_opts()

    case Sessions.dispatch_prompt_async(id, prompt, opts) do
      {:ok, response} ->
        conn
        |> put_status(:accepted)
        |> json(%{data: response})

      {:error, :session_not_active} ->
        {:error, :session_not_active}

      {:error, :no_opencode_session} ->
        {:error, :session_not_active}

      error ->
        error
    end
  end

  def prompt_async(_conn, %{"session_id" => _}) do
    {:error, :missing_prompt}
  end

  @doc """
  Execute a slash command in a session.

  POST /api/sessions/:session_id/command
  Body: { "command": "/help" }
  Body: { "command": "/compact", "arguments": "all" }
  """
  def command(conn, %{"session_id" => id, "command" => command} = params) do
    opts =
      params
      |> Map.take(["arguments", "agent", "model", "node_url"])
      |> normalize_opts()

    case Sessions.dispatch_command(id, command, opts) do
      {:ok, response} -> json(conn, %{data: response})
      error -> error
    end
  end

  def command(_conn, %{"session_id" => _}) do
    {:error, :missing_command}
  end

  @doc """
  Run a shell command in a session.

  POST /api/sessions/:session_id/shell
  Body: { "command": "mix test" }
  Body: { "command": "git status", "agent": "coder" }
  """
  def shell(conn, %{"session_id" => id, "command" => command} = params) do
    opts =
      params
      |> Map.take(["agent", "model", "node_url"])
      |> normalize_opts()

    case Sessions.dispatch_shell(id, command, opts) do
      {:ok, response} -> json(conn, %{data: response})
      error -> error
    end
  end

  def shell(_conn, %{"session_id" => _}) do
    {:error, :missing_command}
  end

  @doc """
  Stop active session and start a new one for an agent.

  POST /api/agents/:agent_id/sessions/new
  """
  def new_session(conn, %{"agent_id" => agent_id} = params) do
    attrs = Sessions.normalize_params(params)

    case Sessions.new_session_for_agent(agent_id, attrs) do
      {:ok, session} ->
        conn
        |> put_status(:created)
        |> render(:show, session: session)

      {:error, reason} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{errors: %{detail: inspect(reason)}})
    end
  end

  defp resolve_session(id) do
    if is_binary(id) and String.starts_with?(id, "ses") do
      Sessions.fetch_session_by_opencode_id(id)
    else
      with {:ok, uuid} <- Ecto.UUID.cast(id) do
        Sessions.fetch_session(uuid)
      else
        :error -> {:error, :not_found}
      end
    end
  end

  defp normalize_opts(params) do
    Enum.map(params, fn {k, v} -> {String.to_atom(k), v} end)
  end
end
