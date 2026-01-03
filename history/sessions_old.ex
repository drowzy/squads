# Stored for historical reference
# This file was previously at the repository root and has been moved to history/

defmodule Squads.Sessions do
  @moduledoc """
  The Sessions context manages OpenCode session lifecycle.

  Sessions represent work being done on tickets by agents. This context
  provides functions to create, start, stop, and query sessions, integrating
  with the OpenCode server via the HTTP client.
  """

  import Ecto.Query, warn: false
  alias Squads.Repo
  alias Squads.Agents
  alias Squads.Agents.Roles
  alias Squads.Sessions.Session
  alias Squads.Tickets.Ticket
  alias Squads.OpenCode.Client, as: OpenCodeClient

  require Logger

  # ============================================================================
  # Session Queries
  # ============================================================================

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
    Session
    |> where(status: ^status)
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
  Gets a session by ID. Raises if not found.
  """
  def get_session!(id), do: Repo.get!(Session, id)

  @doc """
  Gets a session by ID. Returns nil if not found.
  """
  def get_session(id), do: Repo.get(Session, id)

  @doc """
  Gets a session by OpenCode session ID.
  """
  def get_session_by_opencode_id(opencode_session_id) do
    Repo.get_by(Session, opencode_session_id: opencode_session_id)
  end

  # ============================================================================
  # Ticket-Session Linking
  # ============================================================================

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
  Links an existing session to a ticket.

  Returns `{:error, :not_found}` if the session doesn't exist.
  """
  def link_session_to_ticket(session_id, ticket_id) do
    case get_session(session_id) do
      nil ->
        {:error, :not_found}

      session ->
        session
        |> Ecto.Changeset.change(%{ticket_id: ticket_id})
        |> Repo.update()
    end
  end

  @doc """
  Unlinks a session from its ticket.

  Returns `{:error, :not_found}` if the session doesn't exist.
  """
  def unlink_session_from_ticket(session_id) do
    case get_session(session_id) do
      nil ->
        {:error, :not_found}

      session ->
        session
        |> Ecto.Changeset.change(%{ticket_id: nil})
        |> Repo.update()
    end
  end

  @doc """
  Creates a session already linked to a ticket.

  Takes the same attrs as `create_session/1` but requires `:ticket_id`.
  """
  def create_session_for_ticket(%Ticket{id: ticket_id}, attrs) do
    create_session_for_ticket(ticket_id, attrs)
  end

  def create_session_for_ticket(ticket_id, attrs) when is_binary(ticket_id) do
    attrs
    |> Map.put(:ticket_id, ticket_id)
    |> create_session()
  end

  @doc """
  Gets a session with its associated ticket preloaded.
  """
  def get_session_with_ticket(session_id) do
    Session
    |> where(id: ^session_id)
    |> preload(:ticket)
    |> Repo.one()
  end

  # ============================================================================
  # Param Normalization
  # ============================================================================

  @doc """
  Normalizes session parameters from a map into a validated attributes map.
  """
  def normalize_params(params) do
    %{
      agent_id: params["agent_id"],
      ticket_key: params["ticket_key"],
      worktree_path: params["worktree_path"],
      branch: params["branch"],
      title: params["title"],
      metadata: params["metadata"] || %{}
    }
  end

  # ============================================================================
  # Session Creation
  # ============================================================================

  @doc """
  Creates a new session for an agent.

  This creates a local session record in the database. To also start
  an OpenCode session, use `create_and_start_session/2`.

  ## Params

    * `:agent_id` - Required. The agent that will run this session.
    * `:ticket_key` - Optional. The Beads ticket this session is working on.
    * `:metadata` - Optional. Additional session metadata.
  """
  def create_session(attrs) do
    %Session{}
    |> Session.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Creates a session and starts it on the OpenCode server.

  ## Params

    * `:agent_id` - Required. The agent that will run this session.
    * `:ticket_key` - Optional. The Beads ticket this session is working on.
    * `:title` - Optional. Title for the OpenCode session.
    * `:worktree_path` - Optional. Path to the worktree for this session.
    * `:branch` - Optional. Git branch for this session.
    * `:opencode_opts` - Optional. Options to pass to OpenCode client.
  """
  def create_and_start_session(attrs, opencode_opts \\ []) do
    Repo.transaction(fn ->
      # Create local session first
      case create_session(attrs) do
        {:ok, session} ->
          # Start OpenCode session
          title = attrs[:title] || "Session #{session.id}"

          case OpenCodeClient.create_session(Keyword.merge(opencode_opts, title: title)) do
            {:ok, %{"id" => opencode_id}} ->
              # Update local session with OpenCode ID and mark as running
              start_attrs = %{
                opencode_session_id: opencode_id,
                worktree_path: attrs[:worktree_path],
                branch: attrs[:branch]
              }

              session
              |> Session.start_changeset(start_attrs)
              |> Repo.update!()

            {:error, reason} ->
              Logger.error("Failed to start OpenCode session: #{inspect(reason)}")
              Repo.rollback({:opencode_error, reason})
          end

        {:error, changeset} ->
          Repo.rollback(changeset)
      end
    end)
  end

  # ============================================================================
  # Session Lifecycle
  # ============================================================================

  @doc """
  Starts a pending session on the OpenCode server.
  """
  def start_session(session, opencode_opts \\ []) do
    if session.status != "pending" do
      {:error, :already_started}
    else
      title = opencode_opts[:title] || "Session #{session.id}"

      case OpenCodeClient.create_session(Keyword.merge(opencode_opts, title: title)) do
        {:ok, %{"id" => opencode_id}} ->
          session
          |> Session.start_changeset(%{opencode_session_id: opencode_id})
          |> Repo.update()

        {:error, reason} ->
          {:error, {:opencode_error, reason}}
      end
    end
  end

  @doc """
  Stops a running session by aborting it on OpenCode.
  """
  def stop_session(session, exit_code \\ 0) do
    cond do
      session.status not in ["running", "paused"] ->
        {:error, :not_running}

      is_nil(session.opencode_session_id) ->
        # No OpenCode session, just update local state
        session
        |> Session.finish_changeset(exit_code)
        |> Repo.update()

      true ->
        # Abort OpenCode session first
        case OpenCodeClient.abort_session(session.opencode_session_id) do
          {:ok, _} ->
            session
            |> Session.finish_changeset(exit_code)
            |> Repo.update()

          {:error, {:not_found, _}} ->
            # Session already gone on OpenCode side
            session
            |> Session.finish_changeset(exit_code)
            |> Repo.update()

          {:error, reason} ->
            {:error, {:opencode_error, reason}}
        end
    end
  end

  @doc """
  Cancels a session that hasn't started yet.
  """
  def cancel_session(session) do
    if session.status == "pending" do
      session
      |> Ecto.Changeset.change(%{status: "cancelled"})
      |> Repo.update()
    else
      {:error, :already_started}
    end
  end

  @doc """
  Marks a session as paused.
  """
  def pause_session(session) do
    if session.status == "running" do
      session
      |> Ecto.Changeset.change(%{status: "paused"})
      |> Repo.update()
    else
      {:error, :not_running}
    end
  end

  @doc """
  Resumes a paused session.
  """
  def resume_session(session) do
    if session.status == "paused" do
      session
      |> Ecto.Changeset.change(%{status: "running"})
      |> Repo.update()
    else
      {:error, :not_paused}
    end
  end

  # ============================================================================
  # Session Sync with OpenCode
  # ============================================================================

  @doc """
  Syncs the local session status with OpenCode server.
  """
  def sync_session_status(session) do
    if session.opencode_session_id do
      case OpenCodeClient.get_sessions_status() do
        {:ok, statuses} ->
          case Map.get(statuses, session.opencode_session_id) do
            nil ->
              # Session not found - might have been deleted
              {:ok, session}

            opencode_status ->
              # Map OpenCode status to our status
              new_status = map_opencode_status(opencode_status)

              if new_status != session.status do
                session
                |> Ecto.Changeset.change(%{status: new_status})
                |> Repo.update()
              else
                {:ok, session}
              end
          end

        {:error, reason} ->
          {:error, {:opencode_error, reason}}
      end
    else
      {:ok, session}
    end
  end

  # ============================================================================
  # Session Messages
  # ============================================================================

  @doc """
  Sends a message/prompt to a running session.

  ## Params

    * `:parts` - Required. Message parts (e.g., `[%{type: "text", text: "Hello"}]`)
    * `:model` - Optional. Override the model.
    * `:agent` - Optional. Agent to use.
    * `:no_reply` - Optional. If true, don't wait for AI response.
  """
  def send_message(session, params, opencode_opts \\ []) do
    if session.opencode_session_id && session.status == "running" do
      OpenCodeClient.send_message(session.opencode_session_id, params, opencode_opts)
    else
      {:error, :session_not_active}
    end
  end

  @doc """
  Sends a message asynchronously to a running session.
  """
  def send_message_async(session, params, opencode_opts \\ []) do
    if session.opencode_session_id && session.status == "running" do
      OpenCodeClient.send_message_async(session.opencode_session_id, params, opencode_opts)
    else
      {:error, :session_not_active}
    end
  end

  @doc """
  Gets messages from a session.
  """
  def get_messages(session, opts \\ []) do
    if session.opencode_session_id do
      OpenCodeClient.list_messages(session.opencode_session_id, opts)
    else
      {:error, :no_opencode_session}
    end
  end

  @doc """
  Gets the diff for a session.
  """
  def get_diff(session, opts \\ []) do
    if session.opencode_session_id do
      OpenCodeClient.get_session_diff(session.opencode_session_id, opts)
    else
      {:error, :no_opencode_session}
    end
  end

  @doc """
  Gets the todo list for a session.
  """
  def get_todos(session, opts \\ []) do
    if session.opencode_session_id do
      OpenCodeClient.get_session_todos(session.opencode_session_id, opts)
    else
      {:error, :no_opencode_session}
    end
  end

  # ============================================================================
  # Session Commands and Dispatch
  # ============================================================================

  @doc """
  Executes a slash command in a session.

  ## Params

    * `:arguments` - Optional. Command arguments.
    * `:agent` - Optional. Agent to use.
    * `:model` - Optional. Model to use.

  ## Examples

      Sessions.execute_command(session, "/help")
      Sessions.execute_command(session, "/compact", arguments: "all")
  """
  def execute_command(session, command, params \\ [], opencode_opts \\ []) do
    cond do
      is_nil(session.opencode_session_id) ->
        {:error, :no_opencode_session}

      session.status != "running" ->
        {:error, :session_not_active}

      true ->
        OpenCodeClient.execute_command(
          session.opencode_session_id,
          command,
          Keyword.merge(params, opencode_opts)
        )
    end
  end

  @doc """
  Runs a shell command in a session.

  ## Params

    * `:agent` - Optional. Agent to use (default: "default").
    * `:model` - Optional. Model to use.

  ## Examples

      Sessions.run_shell(session, "mix test")
      Sessions.run_shell(session, "git status", agent: "coder")
  """
  def run_shell(session, command, params \\ [], opencode_opts \\ []) do
    cond do
      is_nil(session.opencode_session_id) ->
        {:error, :no_opencode_session}

      session.status != "running" ->
        {:error, :session_not_active}

      true ->
        OpenCodeClient.run_shell(
          session.opencode_session_id,
          command,
          Keyword.merge(params, opencode_opts)
        )
    end
  end

  @doc """
  Sends a text prompt to a session.

  Convenience wrapper around `send_message/3` that constructs a simple
  text message from a string.

  ## Options

    * `:model` - Override the model.
    * `:agent` - Agent to use.
    * `:no_reply` - If true, don't wait for AI response.
  """
  def send_prompt(session, prompt, opts \\ []) when is_binary(prompt) do
    parts = [%{type: "text", text: prompt}]
    params = %{parts: parts}

    agent =
      case session.agent_id do
        nil -> nil
        agent_id -> Agents.get_agent(agent_id)
      end

    model =
      cond do
        opts[:model] ->
          opts[:model]

        agent && is_binary(agent.model) && String.trim(agent.model) != "" ->
          String.trim(agent.model)

        true ->
          nil
      end

    system_override =
      cond do
        opts[:system] ->
          opts[:system]

        agent && is_binary(agent.system_instruction) &&
            String.trim(agent.system_instruction) != "" ->
          String.trim(agent.system_instruction)

        agent ->
          Roles.system_instruction(agent.role, agent.level)

        true ->
          nil
      end

    params = if model, do: Map.put(params, :model, model), else: params
    params = if opts[:agent], do: Map.put(params, :agent, opts[:agent]), else: params
    params = if opts[:no_reply], do: Map.put(params, :no_reply, opts[:no_reply]), else: params
    params = if system_override, do: Map.put(params, :system, system_override), else: params

    send_message(session, params, Keyword.drop(opts, [:model, :agent, :no_reply, :system]))
  end

  @doc """
  Sends a text prompt asynchronously to a session.

  Same as `send_prompt/3` but doesn't wait for a response.
  """
  def send_prompt_async(session, prompt, opts \\ []) when is_binary(prompt) do
    parts = [%{type: "text", text: prompt}]
    params = %{parts: parts}

    agent =
      case session.agent_id do
        nil -> nil
        agent_id -> Agents.get_agent(agent_id)
      end

    model =
      cond do
        opts[:model] ->
          opts[:model]

        agent && is_binary(agent.model) && String.trim(agent.model) != "" ->
          String.trim(agent.model)

        true ->
          nil
      end

    system_override =
      cond do
        opts[:system] ->
          opts[:system]

        agent && is_binary(agent.system_instruction) &&
            String.trim(agent.system_instruction) != "" ->
          String.trim(agent.system_instruction)

        agent ->
          Roles.system_instruction(agent.role, agent.level)

        true ->
          nil
      end

    params = if model, do: Map.put(params, :model, model), else: params
    params = if opts[:agent], do: Map.put(params, :agent, opts[:agent]), else: params
    params = if system_override, do: Map.put(params, :system, system_override), else: params

    send_message_async(session, params, Keyword.drop(opts, [:model, :agent, :system]))
  end

  # ============================================================================
  # Private Helpers
  # ============================================================================

  defp map_opencode_status(%{"status" => "idle"}), do: "running"
  defp map_opencode_status(%{"status" => "running"}), do: "running"
  defp map_opencode_status(%{"status" => "completed"}), do: "completed"
  defp map_opencode_status(%{"status" => "errored"}), do: "failed"
  defp map_opencode_status(%{"status" => "aborted"}), do: "cancelled"
  defp map_opencode_status(_), do: "running"
end
