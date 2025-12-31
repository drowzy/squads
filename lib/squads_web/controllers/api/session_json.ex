defmodule SquadsWeb.API.SessionJSON do
  @moduledoc """
  JSON rendering for sessions.
  """

  alias Squads.Sessions.Session

  @doc """
  Renders a list of sessions.
  """
  def index(%{sessions: sessions}) do
    %{data: for(session <- sessions, do: data(session))}
  end

  @doc """
  Renders a single session.
  """
  def show(%{session: session}) do
    %{data: data(session)}
  end

  defp data(%Session{} = session) do
    %{
      id: session.id,
      agent_id: session.agent_id,
      opencode_session_id: session.opencode_session_id,
      ticket_key: session.ticket_key,
      status: session.status,
      worktree_path: session.worktree_path,
      branch: session.branch,
      started_at: session.started_at,
      finished_at: session.finished_at,
      exit_code: session.exit_code,
      metadata: session.metadata,
      inserted_at: session.inserted_at,
      updated_at: session.updated_at
    }
  end
end
