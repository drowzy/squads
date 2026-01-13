defmodule Squads.Sessions.Operations do
  import Ecto.Query, warn: false

  @moduledoc """
  Session commands, dispatch logic and slash commands.
  """

  alias Squads.Agents
  alias Squads.Agents.Roles
  alias Squads.Sessions.Session
  alias Squads.Sessions.Queries
  alias Squads.Sessions.Lifecycle
  alias Squads.Sessions.Messages
  alias Squads.Sessions.Helpers
  alias Squads.OpenCode.Client, as: OpenCodeClient
  alias Squads.Squads, as: SquadsContext

  require Logger

  @doc """
  Dispatches a prompt to a session (local or external).
  """
  def dispatch_prompt(id, prompt, opts \\ []) do
    with {:ok, target} <- resolve_target(id, opts) do
      case target do
        %Session{} = session ->
          send_prompt(session, prompt, opts)

        base_url when is_binary(base_url) ->
          opencode_opts = Keyword.put(opts, :base_url, base_url)

          OpenCodeClient.client().send_message(
            id,
            %{parts: [%{type: "text", text: prompt}]},
            opencode_opts
          )
      end
    else
      {:error, :not_found} -> {:error, :not_found}
    end
  end

  @doc """
  Dispatches a prompt asynchronously to a session (local or external).
  """
  def dispatch_prompt_async(id, prompt, opts \\ []) do
    with {:ok, target} <- resolve_target(id, opts) do
      case target do
        %Session{} = session ->
          send_prompt_async(session, prompt, opts)

        base_url when is_binary(base_url) ->
          opencode_opts = Keyword.put(opts, :base_url, base_url)

          OpenCodeClient.client().send_message_async(
            id,
            %{parts: [%{type: "text", text: prompt}]},
            opencode_opts
          )
      end
    end
  end

  @doc """
  Dispatches a command to a session (local or external).
  """
  def dispatch_command(id, command, opts \\ []) do
    with {:ok, target} <- resolve_target(id, opts) do
      case target do
        %Session{} = session ->
          execute_command(session, command, opts)

        base_url when is_binary(base_url) ->
          opencode_opts = Keyword.put(opts, :base_url, base_url)
          OpenCodeClient.client().execute_command(id, command, opencode_opts)
      end
    end
  end

  @doc """
  Dispatches a shell command to a session (local or external).
  """
  def dispatch_shell(id, command, opts \\ []) do
    with {:ok, target} <- resolve_target(id, opts) do
      case target do
        %Session{} = session ->
          run_shell(session, command, opts)

        base_url when is_binary(base_url) ->
          opencode_opts = Keyword.put(opts, :base_url, base_url)
          OpenCodeClient.client().run_shell(id, command, opencode_opts)
      end
    end
  end

  @doc """
  Dispatches an abort request to a session (local or external).
  """
  def dispatch_abort(id, opts \\ []) do
    with {:ok, target} <- resolve_target(id, opts) do
      case target do
        %Session{} = session ->
          Lifecycle.abort_session(session, opts)

        base_url when is_binary(base_url) ->
          opencode_opts = Keyword.put(opts, :base_url, base_url)
          OpenCodeClient.client().abort_session(id, opencode_opts)
      end
    end
  end

  @doc """
  Dispatches an archive request to a session (local or external).
  """
  def dispatch_archive(id, opts \\ []) do
    with {:ok, target} <- resolve_target(id, opts) do
      case target do
        %Session{} = session ->
          Lifecycle.archive_session(session, opts)

        base_url when is_binary(base_url) ->
          archived_at = DateTime.utc_now() |> DateTime.truncate(:second)
          payload = %{time: %{archived: DateTime.to_unix(archived_at, :millisecond)}}
          opencode_opts = Keyword.put(opts, :base_url, base_url)
          OpenCodeClient.client().update_session(id, payload, opencode_opts)
      end
    end
  end

  def resolve_target(id, opts) do
    node_url = opts[:node_url]

    cond do
      is_binary(node_url) and node_url != "" ->
        {:ok, node_url}

      true ->
        case Queries.fetch_session(id) do
          {:ok, session} ->
            {:ok, session}

          {:error, :not_found} ->
            case Queries.fetch_session_by_opencode_id(id) do
              {:ok, session} -> {:ok, session}
              {:error, :not_found} -> {:error, :not_found}
            end
        end
    end
  end

  def local_command?(command) when is_binary(command) do
    command in [
      "/squads-status",
      "/check-mail",
      "/sessions",
      "/compact",
      "/help"
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

        cond do
          is_nil(session.opencode_session_id) or session.status == "pending" ->
            if session.status == "pending" do
              {:error, :session_not_active}
            else
              {:error, :no_opencode_session}
            end

          is_nil(agent) ->
            {:error, :agent_not_found}

          true ->
            status = get_squad_status(agent.squad_id)
            {:ok, %{"output" => Jason.encode!(status, pretty: true)}}
        end

      "/check-mail" ->
        agent = Agents.get_agent(session.agent_id)

        cond do
          is_nil(session.opencode_session_id) or session.status == "pending" ->
            if session.status == "pending" do
              {:error, :session_not_active}
            else
              {:error, :no_opencode_session}
            end

          is_nil(agent) ->
            {:error, :agent_not_found}

          true ->
            messages = Squads.Mail.list_inbox(agent.id, limit: 10)

            output =
              messages
              |> Enum.map(fn m -> "[#{m.id}] From: #{m.sender.name} - #{m.subject}" end)
              |> Enum.join("\n")

            {:ok, %{"output" => output}}
        end

      "/sessions" ->
        cond do
          is_nil(session.opencode_session_id) or session.status == "pending" ->
            if session.status == "pending" do
              {:error, :session_not_active}
            else
              {:error, :no_opencode_session}
            end

          true ->
            {:ok, %{"output" => format_session_listing(session.agent_id)}}
        end

      "/compact" ->
        cond do
          is_nil(session.opencode_session_id) or session.status == "pending" ->
            if session.status == "pending" do
              {:error, :session_not_active}
            else
              {:error, :no_opencode_session}
            end

          true ->
            {:ok, %{"output" => "Compaction is not available for Squads-managed sessions yet."}}
        end

      "/help" ->
        cond do
          is_nil(session.opencode_session_id) or session.status == "pending" ->
            if session.status == "pending" do
              {:error, :session_not_active}
            else
              {:error, :no_opencode_session}
            end

          true ->
            output =
              [
                "Squads commands:",
                "  /squads-status      Show current squad status",
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
        end

      _ ->
        Logger.debug(
          "Command not matched in squads context: #{command}. Dispatching to OpenCode."
        )

        cond do
          is_nil(session.opencode_session_id) ->
            {:error, :no_opencode_session}

          true ->
            case Lifecycle.ensure_session_running(session, opencode_opts) do
              {:ok, session} ->
                opts = Helpers.with_base_url(session, Keyword.merge(params, opencode_opts))

                Logger.debug(
                  "Executing command #{command} on session #{session.opencode_session_id} with opts: #{inspect(opts)}"
                )

                case OpenCodeClient.client().execute_command(
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
  """
  def run_shell(session, command, params \\ [], opencode_opts \\ []) do
    case Lifecycle.ensure_session_running(session, opencode_opts) do
      {:ok, session} ->
        opts = Helpers.with_base_url(session, Keyword.merge(params, opencode_opts))

        OpenCodeClient.client().run_shell(
          session.opencode_session_id,
          command,
          opts
        )

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Sends a text prompt to a session.
  """
  def send_prompt(session, prompt, opts \\ []) when is_binary(prompt) do
    if is_nil(prompt) || String.trim(prompt) == "" do
      {:error, :missing_prompt}
    else
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

      project_context =
        case agent do
          %{squad_id: squad_id} when not is_nil(squad_id) ->
            squad = SquadsContext.get_squad(squad_id)
            project = if squad, do: squad.project, else: nil

            worktree_path =
              cond do
                is_binary(session.worktree_path) and String.trim(session.worktree_path) != "" ->
                  session.worktree_path

                project && is_binary(project.path) ->
                  project.path

                true ->
                  nil
              end

            if project do
              """
              Squads project context:
              - project_id: #{project.id}
              - project_name: #{project.name}
              - project_path: #{project.path}
              - worktree_path: #{worktree_path || ""}

              MCP usage requirements:
              - When calling MCP tools under `artifacts.*` (create_review/create_issue/submit_review), ALWAYS set `project_id` to exactly `#{project.id}`.
              - Do NOT guess `project_id` from directory names.
              - For filesystem reviews (`artifacts.create_review`), ALWAYS include `worktree_path` and set it to the worktree directory shown above.
              """
              |> String.trim()
            else
              nil
            end

          _ ->
            nil
        end

      base_system_override =
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

      system_override =
        [base_system_override, project_context]
        |> Enum.reject(&is_nil/1)
        |> Enum.join("\n\n")
        |> case do
          "" -> nil
          text -> text
        end

      params = if model, do: Map.put(params, :model, model), else: params
      params = if opts[:agent], do: Map.put(params, :agent, opts[:agent]), else: params

      params = if opts[:no_reply], do: Map.put(params, :no_reply, opts[:no_reply]), else: params
      params = if system_override, do: Map.put(params, :system, system_override), else: params

      opts =
        Helpers.with_base_url(session, Keyword.drop(opts, [:model, :agent, :no_reply, :system]))

      Messages.send_message(session, params, opts)
    end
  end

  @doc """
  Sends a text prompt asynchronously to a session.
  """
  def send_prompt_async(session, prompt, opts \\ []) when is_binary(prompt) do
    if is_nil(prompt) || String.trim(prompt) == "" do
      {:error, :missing_prompt}
    else
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

      project_context =
        case agent do
          %{squad_id: squad_id} when not is_nil(squad_id) ->
            squad = SquadsContext.get_squad(squad_id)
            project = if squad, do: squad.project, else: nil

            worktree_path =
              cond do
                is_binary(session.worktree_path) and String.trim(session.worktree_path) != "" ->
                  session.worktree_path

                project && is_binary(project.path) ->
                  project.path

                true ->
                  nil
              end

            if project do
              """
              Squads project context:
              - project_id: #{project.id}
              - project_name: #{project.name}
              - project_path: #{project.path}
              - worktree_path: #{worktree_path || ""}

              MCP usage requirements:
              - When calling MCP tools under `artifacts.*` (create_review/create_issue/submit_review), ALWAYS set `project_id` to exactly `#{project.id}`.
              - Do NOT guess `project_id` from directory names.
              - For filesystem reviews (`artifacts.create_review`), ALWAYS include `worktree_path` and set it to the worktree directory shown above.
              """
              |> String.trim()
            else
              nil
            end

          _ ->
            nil
        end

      base_system_override =
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

      system_override =
        [base_system_override, project_context]
        |> Enum.reject(&is_nil/1)
        |> Enum.join("\n\n")
        |> case do
          "" -> nil
          text -> text
        end

      params = if model, do: Map.put(params, :model, model), else: params
      params = if opts[:agent], do: Map.put(params, :agent, opts[:agent]), else: params

      params = if system_override, do: Map.put(params, :system, system_override), else: params

      opts = Helpers.with_base_url(session, Keyword.drop(opts, [:model, :agent, :system]))
      Messages.send_message_async(session, params, opts)
    end
  end

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

  def format_session_listing(agent_id) do
    sessions = Queries.list_sessions_for_agent(agent_id)

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

    "[#{String.upcase(status)}] #{Ecto.UUID.cast!(session.id)} #{ticket} #{started_at}"
  end

  defp format_session_time(nil), do: "n/a"
  defp format_session_time(%DateTime{} = dt), do: DateTime.to_iso8601(dt)
end
