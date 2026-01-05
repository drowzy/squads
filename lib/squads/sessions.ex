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
    Ecto.Multi.new()
    |> Ecto.Multi.insert(:session, Session.changeset(%Session{}, attrs))
    |> Ecto.Multi.run(:opencode_server, fn _repo, %{session: session} ->
      agent = Repo.get(Squads.Agents.Agent, session.agent_id) |> Repo.preload(squad: :project)
      squad = agent && agent.squad

      if agent && squad do
        Squads.OpenCode.Server.ensure_running(squad.project_id, squad.project.path)
      else
        {:error, :agent_or_squad_not_found}
      end
    end)
    |> Ecto.Multi.run(:opencode_session, fn _repo,
                                            %{session: session, opencode_server: base_url} ->
      title = attrs[:title] || "Session #{session.id}"
      directory = resolve_session_directory(session, attrs[:worktree_path])

      opts =
        opencode_opts
        |> Keyword.merge(title: title, base_url: base_url)
        |> Keyword.put(:directory, directory)

      case OpenCodeClient.create_session(opts) do
        {:ok, %{"id" => opencode_id}} -> {:ok, opencode_id}
        {:error, reason} -> {:error, reason}
      end
    end)
    |> Ecto.Multi.update(:updated_session, fn %{
                                                session: session,
                                                opencode_session: opencode_id,
                                                opencode_server: base_url
                                              } ->
      directory = resolve_session_directory(session, attrs[:worktree_path])

      metadata = Map.put(session.metadata || %{}, "opencode_base_url", base_url)

      start_attrs = %{
        opencode_session_id: opencode_id,
        worktree_path: directory,
        branch: attrs[:branch],
        metadata: metadata
      }

      Session.start_changeset(session, start_attrs)
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{updated_session: session}} ->
        {:ok, session}

      {:error, :opencode_session, reason, _changes} ->
        Logger.error("Failed to start OpenCode session: #{inspect(reason)}")
        {:error, {:opencode_error, reason}}

      {:error, _step, reason, _changes} ->
        {:error, reason}
    end
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
      agent = Repo.get(Squads.Agents.Agent, session.agent_id) |> Repo.preload(squad: :project)
      squad = agent && agent.squad

      if agent && squad do
        case Squads.OpenCode.Server.ensure_running(squad.project_id, squad.project.path) do
          {:ok, base_url} ->
            title = opencode_opts[:title] || "Session #{session.id}"
            directory = resolve_session_directory(session, opencode_opts[:worktree_path])

            opts =
              opencode_opts
              |> Keyword.merge(title: title, base_url: base_url)
              |> Keyword.put(:directory, directory)

            case OpenCodeClient.create_session(opts) do
              {:ok, %{"id" => opencode_id}} ->
                metadata = Map.put(session.metadata || %{}, "opencode_base_url", base_url)

                session
                |> Session.start_changeset(%{
                  opencode_session_id: opencode_id,
                  worktree_path: directory,
                  metadata: metadata
                })
                |> Repo.update()

              {:error, reason} ->
                {:error, {:opencode_error, reason}}
            end

          {:error, reason} ->
            {:error, reason}
        end
      else
        {:error, :agent_or_squad_not_found}
      end
    end
  end

  @doc """
  Stops a running session by aborting it on OpenCode.
  """
  def stop_session(session, exit_code \\ 0, opts \\ []) do
    cond do
      session.status not in ["running", "paused"] ->
        {:error, :not_running}

      is_nil(session.opencode_session_id) ->
        # No OpenCode session, just update local state
        session
        |> Session.finish_changeset(exit_code)
        |> add_termination_metadata(opts)
        |> Repo.update()

      true ->
        opencode_opts = with_base_url(session, [])

        # Abort OpenCode session first
        case OpenCodeClient.abort_session(session.opencode_session_id, opencode_opts) do
          {:ok, _} ->
            session
            |> Session.finish_changeset(exit_code)
            |> add_termination_metadata(opts)
            |> Repo.update()

          {:error, {:not_found, _}} ->
            # Session already gone on OpenCode side
            session
            |> Session.finish_changeset(exit_code)
            |> add_termination_metadata(opts)
            |> Repo.update()

          {:error, reason} ->
            {:error, {:opencode_error, reason}}
        end
    end
  end

  @doc """
  Aborts a running session on OpenCode without finishing it locally.
  """
  def abort_session(session, opencode_opts \\ []) do
    cond do
      is_nil(session.opencode_session_id) ->
        {:error, :no_opencode_session}

      not String.starts_with?(session.opencode_session_id, "ses") ->
        {:error, :no_opencode_session}

      test_env?() ->
        {:ok, true}

      true ->
        opts = with_base_url(session, opencode_opts)

        case OpenCodeClient.abort_session(session.opencode_session_id, opts) do
          {:ok, response} ->
            {:ok, response}

          {:error, {:not_found, _}} ->
            {:ok, false}

          {:error, reason} ->
            {:error, {:opencode_error, reason}}
        end
    end
  end

  @doc """
  Archives a session on OpenCode and marks it archived locally.
  """
  def archive_session(session, opencode_opts \\ []) do
    archived_at = DateTime.utc_now() |> DateTime.truncate(:second)

    metadata =
      (session.metadata || %{})
      |> Map.put("archived_at", DateTime.to_iso8601(archived_at))

    apply_local_archive = fn ->
      session
      |> Ecto.Changeset.change(%{status: "archived", metadata: metadata})
      |> Repo.update()
    end

    cond do
      is_nil(session.opencode_session_id) ->
        apply_local_archive.()

      not String.starts_with?(session.opencode_session_id, "ses") ->
        apply_local_archive.()

      test_env?() ->
        apply_local_archive.()

      true ->
        opts = with_base_url(session, opencode_opts)
        payload = %{time: %{archived: DateTime.to_unix(archived_at, :millisecond)}}

        case OpenCodeClient.update_session(session.opencode_session_id, payload, opts) do
          {:ok, _} ->
            apply_local_archive.()

          {:error, {:not_found, _}} ->
            apply_local_archive.()

          {:error, reason} ->
            {:error, {:opencode_error, reason}}
        end
    end
  end

  defp add_termination_metadata(changeset, opts) do
    terminated_by = opts[:terminated_by]
    reason = opts[:reason]

    if terminated_by || reason do
      metadata = Ecto.Changeset.get_field(changeset, :metadata) || %{}

      metadata =
        metadata
        |> Map.put("terminated_at", DateTime.utc_now() |> DateTime.to_iso8601())
        |> then(fn m ->
          if terminated_by, do: Map.put(m, "terminated_by", terminated_by), else: m
        end)
        |> then(fn m -> if reason, do: Map.put(m, "termination_reason", reason), else: m end)

      Ecto.Changeset.put_change(changeset, :metadata, metadata)
    else
      changeset
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

  @doc """
  Starts a new session for an agent without stopping existing sessions.
  """
  def new_session_for_agent(agent_id, attrs \\ %{}) do
    create_and_start_session(Map.put(attrs, :agent_id, agent_id))
  end

  # ============================================================================
  # Session Sync with OpenCode
  # ============================================================================

  @doc """
  Syncs the local session status with OpenCode server.
  """
  def sync_session_status(session) do
    if session.opencode_session_id do
      opts = with_base_url(session, [])

      case OpenCodeClient.get_sessions_status(opts) do
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
    Logger.debug("send_message called",
      session_id: session.id,
      opencode_session_id: session.opencode_session_id,
      status: session.status
    )

    case ensure_session_running(session, opencode_opts) do
      {:ok, session} ->
        opts = with_base_url(session, opencode_opts)
        base_url = Keyword.get(opts, :base_url)

        Logger.info("Sending message to OpenCode",
          session_id: session.id,
          opencode_session_id: session.opencode_session_id,
          base_url: base_url
        )

        result = OpenCodeClient.send_message(session.opencode_session_id, params, opts)

        case result do
          {:ok, _} ->
            Logger.info("OpenCode message sent successfully", session_id: session.id)

          {:error, reason} ->
            Logger.error("OpenCode message failed",
              session_id: session.id,
              reason: inspect(reason)
            )
        end

        result

      {:error, reason} ->
        Logger.warning("Cannot send message: session not running",
          session_id: session.id,
          reason: inspect(reason)
        )

        {:error, reason}
    end
  end

  @doc """
  Sends a message asynchronously to a running session.
  """
  def send_message_async(session, params, opencode_opts \\ []) do
    case ensure_session_running(session, opencode_opts) do
      {:ok, session} ->
        opts = with_base_url(session, opencode_opts)
        OpenCodeClient.send_message_async(session.opencode_session_id, params, opts)

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Gets messages from a session.
  """
  def get_messages(session, opts \\ []) do
    if session.opencode_session_id do
      opts = with_base_url(session, opts)
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
      opts = with_base_url(session, opts)
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
      opts = with_base_url(session, opts)
      OpenCodeClient.get_session_todos(session.opencode_session_id, opts)
    else
      {:error, :no_opencode_session}
    end
  end

  # ============================================================================
  # Session Commands and Dispatch
  # ============================================================================

  def local_command?(command) when is_binary(command) do
    command in [
      "/squads-status",
      "/squads-tickets",
      "/check-mail",
      "/sessions",
      "/compact"
    ]
  end

  def local_command?(_command), do: false

  @doc """
  Executes a slash command in a session.
  """
  def execute_command(session, command, params \\ [], opencode_opts \\ []) do
    case command do
      "/squads-status" ->
        agent = Agents.get_agent(session.agent_id)

        if agent do
          status = get_squad_status(agent.squad_id)
          {:ok, %{"output" => Jason.encode!(status, pretty: true)}}
        else
          {:error, :agent_not_found}
        end

      "/squads-tickets" ->
        agent = Agents.get_agent(session.agent_id)
        squad = agent && Squads.Squads.get_squad(agent.squad_id)

        if squad do
          summary = Squads.Tickets.get_tickets_summary(squad.project_id)
          {:ok, %{"output" => Jason.encode!(summary, pretty: true)}}
        else
          {:error, :squad_not_found}
        end

      "/check-mail" ->
        agent = Agents.get_agent(session.agent_id)

        if agent do
          messages = Squads.Mail.list_inbox(agent.id, limit: 10)

          output =
            messages
            |> Enum.map(fn m -> "[#{m.id}] From: #{m.sender.name} - #{m.subject}" end)
            |> Enum.join("\n")

          {:ok, %{"output" => output}}
        else
          {:error, :agent_not_found}
        end

      "/sessions" ->
        {:ok, %{"output" => format_session_listing(session.agent_id)}}

      "/compact" ->
        {:ok, %{"output" => "Compaction is not available for Squads-managed sessions yet."}}

      "/help" ->
        output =
          [
            "Squads commands:",
            "  /squads-status      Show current squad status",
            "  /squads-tickets     Show ticket board summary",
            "  /check-mail         Show agent inbox preview",
            "",
            "OpenCode commands:",
            "  (Forwarded to OpenCode server; availability depends on that server/config)",
            "",
            "Notes:",
            "  If Squads can’t find the correct OpenCode server for this project, it will attempt discovery",
            "  (via local listening ports) and may start a server in the project directory if needed."
          ]
          |> Enum.join("\n")

        {:ok, %{"output" => output}}

      _ ->
        Logger.debug(
          "Command not matched in squads context: #{command}. Dispatching to OpenCode."
        )

        cond do
          is_nil(session.opencode_session_id) ->
            {:error, :no_opencode_session}

          true ->
            case ensure_session_running(session, opencode_opts) do
              {:ok, session} ->
                opts =
                  params
                  |> Keyword.merge(opencode_opts)
                  |> normalize_agent_opt()

                opts = with_base_url(session, opts)

                Logger.debug(
                  "Executing command #{command} on session #{session.opencode_session_id} with opts: #{inspect(opts)}"
                )

                case OpenCodeClient.execute_command(
                       session.opencode_session_id,
                       command,
                       opts
                     ) do
                  {:ok, response} ->
                    {:ok, response}

                  {:error, reason} = error ->
                    Logger.error("OpenCode command failed",
                      command: command,
                      opencode_session_id: session.opencode_session_id,
                      reason: inspect(reason)
                    )

                    error
                end

              {:error, reason} ->
                {:error, reason}
            end
        end
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

      true ->
        case ensure_session_running(session, opencode_opts) do
          {:ok, session} ->
            opts =
              params
              |> Keyword.merge(opencode_opts)
              |> normalize_agent_opt()

            opts = with_base_url(session, opts)

            OpenCodeClient.run_shell(
              session.opencode_session_id,
              command,
              opts
            )

          {:error, reason} ->
            {:error, reason}
        end
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

    params =
      case normalize_prompt_agent(opts[:agent]) do
        nil -> params
        agent -> Map.put(params, :agent, agent)
      end

    params = if opts[:no_reply], do: Map.put(params, :no_reply, opts[:no_reply]), else: params
    params = if system_override, do: Map.put(params, :system, system_override), else: params

    opts = with_base_url(session, Keyword.drop(opts, [:model, :agent, :no_reply, :system]))
    send_message(session, params, opts)
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

    params =
      case normalize_prompt_agent(opts[:agent]) do
        nil -> params
        agent -> Map.put(params, :agent, agent)
      end

    params = if system_override, do: Map.put(params, :system, system_override), else: params

    opts = with_base_url(session, Keyword.drop(opts, [:model, :agent, :system]))
    send_message_async(session, params, opts)
  end

  # TODO(opencode-squads-gfh): Restore mode-to-agent mapping once OpenCode supports it.
  defp normalize_prompt_agent(agent) when is_binary(agent) do
    trimmed = String.trim(agent)

    cond do
      trimmed == "" -> nil
      trimmed in ["plan", "build"] -> nil
      true -> trimmed
    end
  end

  defp normalize_prompt_agent(_), do: nil

  defp normalize_agent_opt(opts) when is_list(opts) do
    case normalize_prompt_agent(Keyword.get(opts, :agent)) do
      nil -> Keyword.delete(opts, :agent)
      agent -> Keyword.put(opts, :agent, agent)
    end
  end

  defp normalize_agent_opt(opts), do: opts

  # ============================================================================
  # Private Helpers
  # ============================================================================

  def get_squad_status(squad_id) do
    agents = Agents.list_agents_for_squad(squad_id)

    agents
    |> Enum.map(fn a ->
      %{
        id: a.id,
        name: a.name,
        role: a.role,
        status: a.status
      }
    end)
  end

  defp map_opencode_status(%{"status" => "idle"}), do: "running"
  defp map_opencode_status(%{"status" => "starting"}), do: "running"
  defp map_opencode_status(%{"status" => "running"}), do: "running"
  defp map_opencode_status(%{"status" => "paused"}), do: "paused"
  defp map_opencode_status(%{"status" => "completed"}), do: "completed"
  defp map_opencode_status(%{"status" => "errored"}), do: "failed"
  defp map_opencode_status(%{"status" => "aborted"}), do: "cancelled"
  defp map_opencode_status(_), do: "unknown"

  defp ensure_session_running(session, opencode_opts) do
    cond do
      is_nil(session.opencode_session_id) ->
        {:error, :no_opencode_session}

      not String.starts_with?(session.opencode_session_id, "ses") ->
        {:error, :no_opencode_session}

      session.status == "running" ->
        {:ok, session}

      test_env?() ->
        # Keep unit tests deterministic (don't hit a real OpenCode server)
        # unless explicitly bypassed for integration tests.
        if Application.get_env(:squads, :bypass_test_session_block, false) do
          {:ok, session}
        else
          {:error, :session_not_active}
        end

      true ->
        # If the session is not running, we check OpenCode to see if it's still alive.
        # If it's aborted or not found, we attempt to resume it.
        opts = with_base_url(session, opencode_opts)

        case OpenCodeClient.get_session(session.opencode_session_id, opts) do
          {:ok, remote} ->
            if map_opencode_status(remote) in ["running", "paused"] do
              sync_local_to_running(session)
            else
              resume_on_opencode(session, opencode_opts)
            end

          {:error, {:not_found, _}} ->
            resume_on_opencode(session, opencode_opts)

          {:error, reason} ->
            {:error, {:opencode_error, reason}}
        end
    end
  end

  defp sync_local_to_running(session) do
    changes =
      if is_nil(session.started_at) do
        %{
          status: "running",
          started_at: DateTime.utc_now() |> DateTime.truncate(:second)
        }
      else
        %{status: "running"}
      end

    case Repo.update(Ecto.Changeset.change(session, changes)) do
      {:ok, updated} -> {:ok, updated}
      {:error, _} -> {:ok, %{session | status: "running"}}
    end
  end

  defp resume_on_opencode(session, opencode_opts) do
    Logger.info("Resuming session #{session.id} on OpenCode")

    Repo.transaction(fn ->
      # Re-fetch with lock to avoid race conditions
      session = Repo.get!(Session, session.id, lock: "FOR UPDATE")

      if session.status == "running" do
        session
      else
        case get_base_url_for_session(session) do
          nil ->
            Repo.rollback(:no_opencode_server)

          base_url ->
            title = session.metadata["title"] || "Session #{session.id}"
            directory = resolve_session_directory(session, opencode_opts[:worktree_path])

            opts =
              opencode_opts
              |> Keyword.merge(title: title, base_url: base_url)
              |> Keyword.put(:directory, directory)

            case OpenCodeClient.create_session(opts) do
              {:ok, %{"id" => opencode_id}} ->
                metadata = Map.put(session.metadata || %{}, "opencode_base_url", base_url)

                params = %{
                  opencode_session_id: opencode_id,
                  status: "running",
                  worktree_path: directory,
                  started_at: DateTime.utc_now() |> DateTime.truncate(:second),
                  finished_at: nil,
                  exit_code: nil,
                  metadata: metadata
                }

                case Repo.update(Ecto.Changeset.change(session, params)) do
                  {:ok, updated} -> updated
                  {:error, reason} -> Repo.rollback(reason)
                end

              {:error, reason} ->
                Repo.rollback({:opencode_error, reason})
            end
        end
      end
    end)
  end

  defp format_session_listing(agent_id) do
    sessions = list_sessions_for_agent(agent_id)

    case sessions do
      [] ->
        "No sessions found."

      sessions ->
        sessions
        |> Enum.map(&format_session_line/1)
        |> Enum.join("\n")
    end
  end

  defp format_session_line(session) do
    status = session.status || "unknown"
    ticket = session.ticket_key || "no-ticket"
    started_at = format_session_time(session.started_at || session.inserted_at)

    "[#{String.upcase(status)}] #{session.id} #{ticket} #{started_at}"
  end

  defp format_session_time(nil), do: "n/a"
  defp format_session_time(%DateTime{} = dt), do: DateTime.to_iso8601(dt)

  defp test_env? do
    Code.ensure_loaded?(Mix) and function_exported?(Mix, :env, 0) and Mix.env() == :test
  end

  defp get_base_url_for_session(session) do
    Logger.debug("Getting base URL for session #{session.id}")

    with agent_id when not is_nil(agent_id) <- session.agent_id,
         agent when not is_nil(agent) <- Repo.get(Agents.Agent, agent_id),
         squad when not is_nil(squad) <- Repo.get(Squads.Squads.Squad, agent.squad_id),
         project when not is_nil(project) <- Repo.get(Squads.Projects.Project, squad.project_id) do
      case Squads.OpenCode.Server.get_url(squad.project_id) do
        {:ok, base_url} ->
          Logger.debug("Found base URL for project #{squad.project_id}: #{base_url}")
          maybe_persist_base_url(session, base_url)
          base_url

        {:error, :not_running} ->
          Logger.info("OpenCode server not registered; attempting discovery",
            project_id: squad.project_id
          )

          case discover_base_url(project.path, session.metadata) do
            nil ->
              Logger.info("No running OpenCode server discovered; starting one",
                project_id: squad.project_id
              )

              case Squads.OpenCode.Server.ensure_running(squad.project_id, project.path) do
                {:ok, base_url} ->
                  maybe_persist_base_url(session, base_url)
                  base_url

                {:error, reason} ->
                  Logger.error("Failed to start OpenCode server",
                    project_id: squad.project_id,
                    reason: inspect(reason)
                  )

                  nil
              end

            base_url ->
              maybe_persist_base_url(session, base_url)
              base_url
          end

        {:error, reason} ->
          Logger.error("Failed to get base URL for project",
            project_id: squad.project_id,
            reason: inspect(reason)
          )

          nil
      end
    else
      err ->
        Logger.error("Failed to resolve session project context",
          session_id: session.id,
          reason: inspect(err)
        )

        nil
    end
  end

  defp with_base_url(session, opts) do
    case get_base_url_for_session(session) do
      nil -> opts
      url -> Keyword.put_new(opts, :base_url, url)
    end
  end

  defp discover_base_url(project_path, metadata) when is_binary(project_path) do
    configured = configured_base_url()

    case metadata_base_url(metadata) do
      base_url when is_binary(base_url) and base_url != "" ->
        probe_opencode_project(base_url, project_path) ||
          discover_base_url_from_local(project_path) ||
          probe_opencode_project(configured, project_path)

      _ ->
        discover_base_url_from_local(project_path) ||
          probe_opencode_project(configured, project_path)
    end
  end

  defp discover_base_url(_project_path, _metadata), do: nil

  defp discover_base_url_from_local(project_path) do
    local_opencode_candidates()
    |> Enum.find_value(fn base_url -> probe_opencode_project(base_url, project_path) end)
  end

  defp probe_opencode_project(base_url, project_path) do
    case OpenCodeClient.get_current_project(base_url: base_url) do
      {:ok, project} when is_map(project) ->
        path = project["worktree"] || project["path"]

        if is_binary(path) and Path.expand(path) == Path.expand(project_path) do
          Logger.info("Discovered OpenCode server for project", base_url: base_url)
          base_url
        else
          nil
        end

      {:error, reason} ->
        Logger.debug("Failed to probe OpenCode server",
          base_url: base_url,
          reason: inspect(reason)
        )

        nil

      _ ->
        nil
    end
  end

  defp local_opencode_candidates do
    case System.cmd("lsof", ["-nP", "-iTCP", "-sTCP:LISTEN"]) do
      {output, 0} ->
        output
        |> String.split("\n", trim: true)
        |> Enum.filter(&Regex.match?(~r/\bopencode\b/i, &1))
        |> Enum.map(&extract_port/1)
        |> Enum.filter(&is_integer/1)
        |> Enum.map(&"http://127.0.0.1:#{&1}")
        |> Enum.uniq()

      {_, _} ->
        []
    end
  rescue
    _ ->
      []
  end

  defp extract_port(line) do
    case Regex.run(~r/:(\d+)\s+\(LISTEN\)/, line) do
      [_, port] -> String.to_integer(port)
      _ -> nil
    end
  end

  defp maybe_persist_base_url(session, base_url) do
    metadata = session.metadata || %{}

    if Map.get(metadata, "opencode_base_url") == base_url do
      :ok
    else
      changeset =
        Ecto.Changeset.change(session, metadata: Map.put(metadata, "opencode_base_url", base_url))

      case Repo.update(changeset) do
        {:ok, _session} ->
          :ok

        {:error, reason} ->
          Logger.debug("Failed to persist OpenCode base URL", reason: inspect(reason))
          :ok
      end
    end
  end

  defp metadata_base_url(%{"opencode_base_url" => base_url}), do: base_url
  defp metadata_base_url(_), do: nil

  defp configured_base_url do
    System.get_env("OPENCODE_BASE_URL") ||
      :squads
      |> Application.get_env(Squads.OpenCode.Client, [])
      |> Keyword.get(:base_url, "http://127.0.0.1:4096")
  end

  defp resolve_session_directory(session, explicit_worktree_path) do
    cond do
      # 1. Explicit worktree path provided (e.g. at start time)
      is_binary(explicit_worktree_path) and explicit_worktree_path != "" ->
        explicit_worktree_path

      # 2. Session already has a worktree path
      is_binary(session.worktree_path) and session.worktree_path != "" ->
        session.worktree_path

      # 3. Fallback to project path
      true ->
        with agent_id when not is_nil(agent_id) <- session.agent_id,
             agent when not is_nil(agent) <- Repo.get(Agents.Agent, agent_id),
             squad when not is_nil(squad) <- Repo.get(Squads.Squads.Squad, agent.squad_id),
             project when not is_nil(project) <-
               Repo.get(Squads.Projects.Project, squad.project_id) do
          project.path
        else
          _ -> nil
        end
    end
  end
end
