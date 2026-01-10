defmodule Squads.Sessions.Helpers do
  @moduledoc """
  Shared helper functions for Session modules.
  """

  alias Squads.Repo
  alias Squads.OpenCode.Resolver
  alias Squads.OpenCode.Server

  require Logger

  def with_base_url(session, opts) do
    cond do
      Keyword.has_key?(opts, :base_url) ->
        opts

      not has_opencode_session?(session) ->
        opts

      true ->
        case get_base_url_for_session(session) do
          nil -> opts
          url -> Keyword.put_new(opts, :base_url, url)
        end
    end
  end

  def get_base_url_for_session(session) do
    Logger.debug("Getting base URL for session #{session.id}")

    with agent_id when not is_nil(agent_id) <- session.agent_id,
         {:ok, agent} <- fetch_agent_for_resolution(agent_id),
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

          case Resolver.resolve_base_url(project.path,
                 base_url: metadata_base_url(session.metadata)
               ) do
            {:ok, base_url} ->
              Logger.debug(
                "Discovered OpenCode base URL for project #{squad.project_id}: #{base_url}"
              )

              maybe_persist_base_url(session, base_url)
              base_url

            {:error, _reason} ->
              Logger.info("No running OpenCode instance found; starting one",
                project_id: squad.project_id,
                project_path: project.path
              )

              case Server.ensure_running(squad.project_id, project.path) do
                {:ok, base_url} ->
                  maybe_persist_base_url(session, base_url)
                  base_url

                {:error, reason} ->
                  Logger.error("Failed to start OpenCode server for project",
                    project_id: squad.project_id,
                    reason: inspect(reason)
                  )

                  nil
              end
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

  def maybe_persist_base_url(session, base_url) do
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

  def metadata_base_url(%{"opencode_base_url" => base_url}), do: base_url
  def metadata_base_url(_), do: nil

  defp has_opencode_session?(%{opencode_session_id: opencode_session_id})
       when is_binary(opencode_session_id) do
    String.starts_with?(opencode_session_id, "ses")
  end

  defp has_opencode_session?(_), do: false

  defp fetch_agent_for_resolution(agent_id) do
    case Repo.get(Squads.Agents.Agent, agent_id) do
      nil -> {:error, :not_found}
      agent -> {:ok, agent}
    end
  end
end
