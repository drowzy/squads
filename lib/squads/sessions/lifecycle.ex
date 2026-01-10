defmodule Squads.Sessions.Lifecycle do
  @moduledoc """
  Lifecycle management for Sessions (create, start, stop, etc.).
  """

  import Ecto.Query, warn: false
  alias Squads.Repo
  alias Squads.Sessions.Session
  alias Squads.Sessions.Helpers
  alias Squads.OpenCode.Client, as: OpenCodeClient

  require Logger

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

  @doc """
  Creates a new session for an agent.
  """
  def create_session(attrs) do
    %Session{}
    |> Session.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Creates a session and starts it on the OpenCode server.
  """
  def create_and_start_session(attrs, opencode_opts \\ []) do
    Ecto.Multi.new()
    |> Ecto.Multi.insert(:session, Session.changeset(%Session{}, attrs))
    |> Ecto.Multi.run(:opencode_startup, fn _repo, %{session: session} ->
      start_opencode_session_orchestration(session, attrs, opencode_opts)
    end)
    |> Ecto.Multi.update(:updated_session, fn %{
                                                session: session,
                                                opencode_startup: %{
                                                  opencode_id: opencode_id,
                                                  base_url: base_url,
                                                  directory: directory
                                                }
                                              } ->
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

      {:error, :opencode_startup, reason, _changes} ->
        Logger.error("Failed to start OpenCode session: #{inspect(reason)}")
        {:error, {:opencode_error, reason}}

      {:error, _step, reason, _changes} ->
        {:error, reason}
    end
  end

  @doc """
  Starts a pending session on the OpenCode server.
  """
  def start_session(session, opencode_opts \\ []) do
    if session.status != "pending" do
      {:error, :already_started}
    else
      case start_opencode_session_orchestration(session, opencode_opts, opencode_opts) do
        {:ok, %{opencode_id: opencode_id, base_url: base_url, directory: directory}} ->
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
        session
        |> Session.finish_changeset(exit_code)
        |> add_termination_metadata(opts)
        |> Repo.update()

      true ->
        opencode_opts = Helpers.with_base_url(session, [])

        case OpenCodeClient.client().abort_session(session.opencode_session_id, opencode_opts) do
          {:ok, _} ->
            session
            |> Session.finish_changeset(exit_code)
            |> add_termination_metadata(opts)
            |> Repo.update()

          {:error, {:not_found, _}} ->
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

      true ->
        opts = Helpers.with_base_url(session, opencode_opts)

        case OpenCodeClient.client().abort_session(session.opencode_session_id, opts) do
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

      true ->
        opts = Helpers.with_base_url(session, opencode_opts)
        payload = %{time: %{archived: DateTime.to_unix(archived_at, :millisecond)}}

        case OpenCodeClient.client().update_session(session.opencode_session_id, payload, opts) do
          {:ok, _} ->
            apply_local_archive.()

          {:error, {:not_found, _}} ->
            apply_local_archive.()

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

  @doc """
  Starts a new session for an agent without stopping existing sessions.
  """
  def new_session_for_agent(agent_id, attrs \\ %{}) do
    create_and_start_session(Map.put(attrs, :agent_id, agent_id))
  end

  @doc """
  Ensures a session is running on OpenCode, resuming if necessary.
  """
  def ensure_session_running(session, opencode_opts \\ []) do
    cond do
      session.status in ["completed", "failed", "cancelled", "pending"] ->
        {:error, :session_not_active}

      is_nil(session.opencode_session_id) ->
        {:error, :no_opencode_session}

      not String.starts_with?(session.opencode_session_id, "ses") ->
        {:error, :no_opencode_session}

      session.status == "running" ->
        {:ok, session}

      true ->
        opts = Helpers.with_base_url(session, opencode_opts)

        case OpenCodeClient.client().get_session(session.opencode_session_id, opts) do
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

  @doc """
  Syncs the local session status with OpenCode server.
  """
  def sync_session_status(session) do
    if session.opencode_session_id do
      opts = Helpers.with_base_url(session, [])

      case OpenCodeClient.client().get_sessions_status(opts) do
        {:ok, statuses} ->
          case Map.get(statuses, session.opencode_session_id) do
            nil ->
              {:ok, session}

            opencode_status ->
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
  # Helpers
  # ============================================================================

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

  defp map_opencode_status(%{"status" => "idle"}), do: "running"
  defp map_opencode_status(%{"status" => "starting"}), do: "running"
  defp map_opencode_status(%{"status" => "running"}), do: "running"
  defp map_opencode_status(%{"status" => "paused"}), do: "paused"
  defp map_opencode_status(%{"status" => "completed"}), do: "completed"
  defp map_opencode_status(%{"status" => "errored"}), do: "failed"
  defp map_opencode_status(%{"status" => "aborted"}), do: "cancelled"
  defp map_opencode_status(_), do: "unknown"

  defp start_opencode_session_orchestration(session, attrs, opencode_opts) do
    with {:ok, agent} <- fetch_agent_for_resolution(session.agent_id),
         agent <- Repo.preload(agent, squad: :project),
         squad when not is_nil(squad) <- agent.squad,
         {:ok, base_url} <-
           Squads.OpenCode.Server.ensure_running(squad.project_id, squad.project.path) do
      title = attrs[:title] || "Session #{session.id}"
      directory = resolve_session_directory(session, attrs[:worktree_path])

      opts =
        opencode_opts
        |> Keyword.merge(title: title, base_url: base_url)
        |> Keyword.put(:directory, directory)

      case OpenCodeClient.client().create_session(opts) do
        {:ok, %{"id" => opencode_id}} ->
          {:ok, %{opencode_id: opencode_id, base_url: base_url, directory: directory}}

        {:error, reason} ->
          {:error, reason}
      end
    else
      {:error, :not_found} -> {:error, :agent_or_squad_not_found}
      nil -> {:error, :agent_or_squad_not_found}
      {:error, reason} -> {:error, reason}
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
      session =
        case Repo.get(Session, session.id, lock: "FOR UPDATE") do
          nil -> Repo.rollback(:not_found)
          session -> session
        end

      if session.status == "running" do
        session
      else
        case Helpers.get_base_url_for_session(session) do
          nil ->
            Repo.rollback(:no_opencode_server)

          base_url ->
            title = session.metadata["title"] || "Session #{session.id}"
            directory = resolve_session_directory(session, opencode_opts[:worktree_path])

            opts =
              opencode_opts
              |> Keyword.merge(title: title, base_url: base_url)
              |> Keyword.put(:directory, directory)

            case OpenCodeClient.client().create_session(opts) do
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

  defp resolve_session_directory(session, explicit_worktree_path) do
    cond do
      is_binary(explicit_worktree_path) and explicit_worktree_path != "" ->
        explicit_worktree_path

      is_binary(session.worktree_path) and session.worktree_path != "" ->
        session.worktree_path

      true ->
        with agent_id when not is_nil(agent_id) <- session.agent_id,
             {:ok, agent} <- fetch_agent_for_resolution(agent_id),
             squad when not is_nil(squad) <- Repo.get(Squads.Squads.Squad, agent.squad_id),
             project when not is_nil(project) <-
               Repo.get(Squads.Projects.Project, squad.project_id) do
          project.path
        else
          _ -> nil
        end
    end
  end

  defp fetch_agent_for_resolution(agent_id) do
    case Repo.get(Squads.Agents.Agent, agent_id) do
      nil -> {:error, :not_found}
      agent -> {:ok, agent}
    end
  end
end
