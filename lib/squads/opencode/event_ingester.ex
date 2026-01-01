defmodule Squads.OpenCode.EventIngester do
  @moduledoc """
  GenServer that maintains SSE connections to OpenCode event streams
  and persists events to the database.

  This ingester subscribes to:
  - `/event` - Global events (session lifecycle, etc.)
  - `/session/:id/event` - Per-session events (messages, tool calls, etc.)

  ## Usage

  Start the ingester for a project:

      {:ok, pid} = EventIngester.start_link(project_id: project_id)

  Subscribe to a specific session's events:

      EventIngester.subscribe_session(pid, "session-id-123")

  ## Event Mapping

  OpenCode events are mapped to internal event kinds:
  - `session.created` -> `session.started`
  - `session.updated` -> `session.status_changed` (when status changes)
  - `message.*` -> stored in session metadata
  """

  use GenServer

  require Logger

  alias Squads.Events
  alias Squads.OpenCode.SSE

  @default_reconnect_delay 5_000
  @max_reconnect_delay 60_000

  # ============================================================================
  # Public API
  # ============================================================================

  @doc """
  Starts the event ingester for a project.

  ## Options

    * `:project_id` - Required. The project ID to associate events with.
    * `:base_url` - OpenCode server URL (default from config)
    * `:auto_connect` - Start global connection immediately (default: true)
  """
  def start_link(opts) do
    # Validate project_id is present
    _ = Keyword.fetch!(opts, :project_id)
    name = Keyword.get(opts, :name)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Subscribes to a session's event stream.
  """
  def subscribe_session(server, session_id) do
    GenServer.call(server, {:subscribe_session, session_id})
  end

  @doc """
  Unsubscribes from a session's event stream.
  """
  def unsubscribe_session(server, session_id) do
    GenServer.call(server, {:unsubscribe_session, session_id})
  end

  @doc """
  Returns the current connection status.
  """
  def status(server) do
    GenServer.call(server, :status)
  end

  @doc """
  Manually trigger a reconnection attempt.
  """
  def reconnect(server) do
    GenServer.cast(server, :reconnect)
  end

  # ============================================================================
  # GenServer Callbacks
  # ============================================================================

  @impl true
  def init(opts) do
    project_id = Keyword.fetch!(opts, :project_id)

    base_url =
      case Squads.OpenCode.Server.get_url(project_id) do
        {:ok, url} -> url
        _ -> Keyword.get(opts, :base_url) || get_base_url()
      end

    auto_connect = Keyword.get(opts, :auto_connect, true)

    state = %{
      project_id: project_id,
      base_url: base_url,
      global_connection: nil,
      session_connections: %{},
      reconnect_attempts: 0,
      buffer: ""
    }

    if auto_connect do
      send(self(), :connect_global)
    end

    {:ok, state}
  end

  @impl true
  def handle_call({:subscribe_session, session_id}, _from, state) do
    if Map.has_key?(state.session_connections, session_id) do
      {:reply, {:ok, :already_subscribed}, state}
    else
      case start_session_stream(session_id, state) do
        {:ok, ref} ->
          connections = Map.put(state.session_connections, session_id, %{ref: ref, buffer: ""})
          {:reply, :ok, %{state | session_connections: connections}}

        {:error, reason} ->
          {:reply, {:error, reason}, state}
      end
    end
  end

  @impl true
  def handle_call({:unsubscribe_session, session_id}, _from, state) do
    case Map.pop(state.session_connections, session_id) do
      {nil, _} ->
        {:reply, {:ok, :not_subscribed}, state}

      {%{ref: ref}, connections} ->
        cancel_stream(ref)
        {:reply, :ok, %{state | session_connections: connections}}
    end
  end

  @impl true
  def handle_call(:status, _from, state) do
    status = %{
      global_connected: state.global_connection != nil,
      session_count: map_size(state.session_connections),
      sessions: Map.keys(state.session_connections),
      reconnect_attempts: state.reconnect_attempts
    }

    {:reply, status, state}
  end

  @impl true
  def handle_cast(:reconnect, state) do
    state = disconnect_global(state)
    send(self(), :connect_global)
    {:noreply, state}
  end

  @impl true
  def handle_info(:connect_global, state) do
    case start_global_stream(state) do
      {:ok, ref} ->
        Logger.info("Connected to OpenCode global event stream")
        {:noreply, %{state | global_connection: ref, reconnect_attempts: 0}}

      {:error, reason} ->
        Logger.warning("Failed to connect to OpenCode events: #{inspect(reason)}")
        schedule_reconnect(state)
        {:noreply, %{state | reconnect_attempts: state.reconnect_attempts + 1}}
    end
  end

  @impl true
  def handle_info({ref, {:data, chunk}}, state) when is_reference(ref) do
    cond do
      state.global_connection == ref ->
        {events, new_buffer} = SSE.parse_chunk(chunk, state.buffer)
        Enum.each(events, &handle_global_event(&1, state))
        {:noreply, %{state | buffer: new_buffer}}

      session_id = find_session_by_ref(state.session_connections, ref) ->
        conn = state.session_connections[session_id]
        {events, new_buffer} = SSE.parse_chunk(chunk, conn.buffer)
        Enum.each(events, &handle_session_event(&1, session_id, state))
        connections = Map.put(state.session_connections, session_id, %{conn | buffer: new_buffer})
        {:noreply, %{state | session_connections: connections}}

      true ->
        {:noreply, state}
    end
  end

  @impl true
  def handle_info({ref, :done}, state) when is_reference(ref) do
    cond do
      state.global_connection == ref ->
        Logger.info("Global event stream closed, reconnecting...")
        schedule_reconnect(state)
        {:noreply, %{state | global_connection: nil}}

      session_id = find_session_by_ref(state.session_connections, ref) ->
        Logger.info("Session #{session_id} event stream closed")
        connections = Map.delete(state.session_connections, session_id)
        {:noreply, %{state | session_connections: connections}}

      true ->
        {:noreply, state}
    end
  end

  @impl true
  def handle_info({ref, {:error, reason}}, state) when is_reference(ref) do
    Logger.error("SSE stream error: #{inspect(reason)}")

    cond do
      state.global_connection == ref ->
        schedule_reconnect(state)

        {:noreply,
         %{state | global_connection: nil, reconnect_attempts: state.reconnect_attempts + 1}}

      session_id = find_session_by_ref(state.session_connections, ref) ->
        connections = Map.delete(state.session_connections, session_id)
        {:noreply, %{state | session_connections: connections}}

      true ->
        {:noreply, state}
    end
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, _pid, _reason}, state) do
    # Handle process monitor messages
    {:noreply, state}
  end

  @impl true
  def handle_info(:reconnect, state) do
    send(self(), :connect_global)
    {:noreply, state}
  end

  # ============================================================================
  # Private Implementation
  # ============================================================================

  defp start_global_stream(state) do
    url = "#{state.base_url}/event"
    start_sse_stream(url)
  end

  defp start_session_stream(session_id, state) do
    url = "#{state.base_url}/session/#{session_id}/event"
    start_sse_stream(url)
  end

  defp start_sse_stream(url) do
    request = SSE.build_request(url)

    case Req.get(request, into: :self) do
      {:ok, %{status: 200, ref: ref}} ->
        # Use the response reference for tracking
        {:ok, ref}

      {:ok, %{status: status, body: body}} ->
        {:error, {:http_error, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  rescue
    e -> {:error, e}
  end

  defp cancel_stream(_ref) do
    # Req handles cleanup automatically when the process stops receiving
    :ok
  end

  defp disconnect_global(state) do
    if state.global_connection do
      cancel_stream(state.global_connection)
    end

    %{state | global_connection: nil, buffer: ""}
  end

  defp schedule_reconnect(state) do
    delay = calculate_reconnect_delay(state.reconnect_attempts)
    Logger.debug("Scheduling reconnect in #{delay}ms")
    Process.send_after(self(), :reconnect, delay)
  end

  defp calculate_reconnect_delay(attempts) do
    # Exponential backoff with jitter
    base_delay = @default_reconnect_delay * :math.pow(2, attempts)
    delay = min(trunc(base_delay), @max_reconnect_delay)
    jitter = :rand.uniform(1000)
    delay + jitter
  end

  defp find_session_by_ref(connections, ref) do
    Enum.find_value(connections, fn {session_id, %{ref: conn_ref}} ->
      if conn_ref == ref, do: session_id
    end)
  end

  defp handle_global_event(%{event: event_type, data: data}, state) do
    Logger.debug("Global event: #{event_type}", data: data)

    case map_global_event(event_type, data) do
      {:ok, kind, payload} ->
        persist_event(kind, payload, state)

      :ignore ->
        :ok
    end
  end

  defp handle_session_event(%{event: event_type, data: data}, session_id, state) do
    Logger.debug("Session #{session_id} event: #{event_type}", data: data)

    case map_session_event(event_type, data, session_id) do
      {:ok, kind, payload} ->
        persist_event(kind, payload, state)

      :ignore ->
        :ok
    end
  end

  defp map_global_event("session.created", data) do
    {:ok, "session.started", %{opencode_session_id: data["id"], title: data["title"]}}
  end

  defp map_global_event("session.updated", data) do
    # Only create event if status changed
    if data["status"] do
      {:ok, "session.status_changed", %{opencode_session_id: data["id"], status: data["status"]}}
    else
      :ignore
    end
  end

  defp map_global_event("session.deleted", data) do
    {:ok, "session.cancelled", %{opencode_session_id: data["id"]}}
  end

  defp map_global_event(_event_type, _data) do
    :ignore
  end

  defp map_session_event("message.created", data, session_id) do
    {:ok, "mail.received",
     %{
       opencode_session_id: session_id,
       message_id: data["id"],
       role: data["role"],
       content_preview: truncate_content(data["content"])
     }}
  end

  defp map_session_event("message.updated", _data, _session_id) do
    # Message updates are frequent (streaming), skip for now
    :ignore
  end

  defp map_session_event("tool.start", data, session_id) do
    {:ok, "session.tool_started",
     %{
       opencode_session_id: session_id,
       tool: data["tool"],
       input: data["input"]
     }}
  end

  defp map_session_event("tool.end", data, session_id) do
    {:ok, "session.tool_completed",
     %{
       opencode_session_id: session_id,
       tool: data["tool"],
       success: data["success"]
     }}
  end

  defp map_session_event(_event_type, _data, _session_id) do
    :ignore
  end

  defp persist_event(kind, payload, state) do
    # Validate kind is in allowed list before persisting
    if kind in Squads.Events.Event.kinds() do
      attrs = %{
        kind: kind,
        payload: payload,
        project_id: state.project_id
      }

      case Events.create_event(attrs) do
        {:ok, _event} ->
          :ok

        {:error, changeset} ->
          Logger.warning("Failed to persist event: #{inspect(changeset.errors)}")
          :error
      end
    else
      Logger.debug("Skipping unmapped event kind: #{kind}")
      :ok
    end
  end

  defp truncate_content(nil), do: nil

  defp truncate_content(content) when is_binary(content) do
    if String.length(content) > 200 do
      String.slice(content, 0, 200) <> "..."
    else
      content
    end
  end

  defp truncate_content(content), do: inspect(content, limit: 200)

  defp get_base_url do
    config = Application.get_env(:squads, Squads.OpenCode.Client, [])
    Keyword.get(config, :base_url, "http://127.0.0.1:4096")
  end
end
