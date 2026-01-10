defmodule SquadsWeb.API.SessionController do
  @moduledoc """
  API controller for session lifecycle management.

  Provides endpoints to create, list, start, stop, and query sessions.
  """
  use SquadsWeb, :controller

  require Logger

  alias Squads.OpenCode.SSE
  alias Squads.Sessions
  alias Squads.Sessions.Helpers, as: SessionHelpers

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
  Body: { "agent_id": "uuid", "ticket_key": "owner/repo#123", "title": "optional" }
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
  Body: { "agent_id": "uuid", "ticket_key": "owner/repo#123", "title": "Work on feature" }
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

  @doc """
  Returns a persisted transcript for a session.

  By default, this endpoint will sync messages from OpenCode and upsert them to
  SQLite before returning results.

  GET /api/sessions/:session_id/transcript

  Query params:
  - `sync` (default: true) - when false, returns persisted entries without calling OpenCode
  - `limit` (default: 200)
  - `after_position` - pagination cursor (returned as `meta.next_after_position`)
  - `node_url` - optional OpenCode base URL override
  """
  def transcript(conn, %{"session_id" => id} = params) do
    with {:ok, session} <- resolve_session(id) do
      sync? = Map.get(params, "sync", "true") != "false"
      limit = parse_int(params["limit"], 200)
      after_position = parse_int(params["after_position"], -1)
      sync_opts = if params["node_url"], do: [base_url: params["node_url"]], else: []

      with :ok <- maybe_sync_transcript(session, sync?, sync_opts) do
        {entries, meta} =
          Sessions.list_transcript_entries(session.id,
            limit: limit,
            after_position: after_position
          )

        json(conn, %{data: Enum.map(entries, &transcript_entry_json/1), meta: meta})
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
  Send a prompt and stream OpenCode message deltas back.

  POST /api/sessions/:session_id/prompt_stream
  Body: { "prompt": "Fix the bug", "model": "...", "agent": "..." }

  This endpoint proxies the OpenCode `/event` SSE stream and filters it down
  to events for the target OpenCode session.

  The stream includes `message.part.updated` events with a `delta` field that
  can be used to render assistant output incrementally.
  """
  def prompt_stream(conn, %{"session_id" => id, "prompt" => prompt} = params) do
    opts =
      params
      |> Map.take(["model", "agent", "no_reply", "node_url"])
      |> normalize_opts()

    with {:ok, {base_url, opencode_session_id}} <- resolve_opencode_target(id, opts) do
      _ = Task.start(fn -> Sessions.dispatch_prompt(id, prompt, opts) end)
      stream_url = "#{base_url}/event"

      conn =
        conn
        |> put_resp_header("content-type", "text/event-stream")
        |> put_resp_header("cache-control", "no-cache")
        |> put_resp_header("connection", "keep-alive")
        |> send_chunked(200)

      {:ok, conn} =
        chunk(
          conn,
          "event: ping\ndata: {\"status\":\"connected\",\"session_id\":\"#{opencode_session_id}\"}\n\n"
        )

      SSE.stream(stream_url)
      |> Stream.filter(&opencode_session_event?(&1, opencode_session_id))
      |> Enum.reduce_while(conn, fn raw, conn_acc ->
        event_type = opencode_event_type(raw) || Map.get(raw, :event) || "opencode.event"
        data = Map.get(raw, :data)
        payload = Jason.encode!(data)

        case chunk(conn_acc, "event: #{event_type}\ndata: #{payload}\n\n") do
          {:ok, conn_acc} ->
            if opencode_event_done?(raw) do
              {:halt, conn_acc}
            else
              {:cont, conn_acc}
            end

          {:error, _reason} ->
            {:halt, conn_acc}
        end
      end)
    else
      {:error, :session_not_active} ->
        {:error, :session_not_active}

      {:error, :no_opencode_session} ->
        {:error, :session_not_active}

      {:error, reason} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{errors: %{detail: inspect(reason)}})

      error ->
        error
    end
  end

  def prompt_stream(_conn, %{"session_id" => _}) do
    {:error, :missing_prompt}
  end

  defp resolve_opencode_target(id, opts) do
    node_url = opts[:node_url]

    cond do
      is_binary(node_url) and String.trim(node_url) != "" ->
        {:ok, {String.trim_trailing(node_url, "/"), id}}

      true ->
        with {:ok, session} <- resolve_session(id),
             opencode_session_id when is_binary(opencode_session_id) <-
               session.opencode_session_id,
             base_url when is_binary(base_url) <- SessionHelpers.get_base_url_for_session(session) do
          {:ok, {base_url, opencode_session_id}}
        else
          _ -> {:error, :missing_opencode_session}
        end
    end
  end

  defp opencode_event_type(%{data: %{"type" => type}}) when is_binary(type), do: type
  defp opencode_event_type(_), do: nil

  defp opencode_session_event?(%{data: data}, opencode_session_id) when is_map(data) do
    session_id =
      get_in(data, ["properties", "sessionID"]) ||
        get_in(data, ["properties", "info", "sessionID"]) ||
        get_in(data, ["properties", "part", "sessionID"]) ||
        get_in(data, ["properties", "tool", "sessionID"]) ||
        get_in(data, ["properties", "pty", "sessionID"]) ||
        data["sessionID"]

    session_id == opencode_session_id
  end

  defp opencode_session_event?(_event, _opencode_session_id), do: false

  defp opencode_event_done?(%{event: "session.idle"}), do: true

  defp opencode_event_done?(%{data: %{"type" => "session.idle"}}), do: true

  defp opencode_event_done?(%{
         data: %{"type" => "session.status", "properties" => %{"status" => %{"type" => "idle"}}}
       }),
       do: true

  defp opencode_event_done?(%{
         data: %{
           "type" => "message.updated",
           "properties" => %{
             "info" => %{"role" => "assistant", "time" => %{"completed" => completed}}
           }
         }
       })
       when is_number(completed),
       do: true

  defp opencode_event_done?(_), do: false

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

  defp maybe_sync_transcript(_session, false, _sync_opts), do: :ok

  defp maybe_sync_transcript(session, true, sync_opts) do
    case Sessions.sync_session_transcript(session, sync_opts) do
      {:ok, _count} -> :ok
      error -> error
    end
  end

  defp transcript_entry_json(entry) do
    %{
      id: entry.id,
      session_id: entry.session_id,
      opencode_message_id: entry.opencode_message_id,
      role: entry.role,
      occurred_at: entry.occurred_at,
      payload: entry.payload,
      inserted_at: entry.inserted_at,
      updated_at: entry.updated_at
    }
  end

  defp parse_int(nil, default), do: default

  defp parse_int(value, default) when is_binary(value) do
    case Integer.parse(value) do
      {int, _} -> int
      :error -> default
    end
  end

  defp parse_int(_value, default), do: default

  defp normalize_opts(params) do
    Enum.map(params, fn {k, v} -> {String.to_atom(k), v} end)
  end
end
