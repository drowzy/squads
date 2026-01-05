defmodule Squads.Sessions.Messages do
  @moduledoc """
  Messaging functions for Sessions.
  """

  alias Squads.OpenCode.Client, as: OpenCodeClient
  alias Squads.Sessions.Helpers
  alias Squads.Sessions.Lifecycle

  require Logger

  @doc """
  Sends a message/prompt to a running session.
  """
  def send_message(session, params, opencode_opts \\ []) do
    Logger.debug("send_message called",
      session_id: session.id,
      opencode_session_id: session.opencode_session_id,
      status: session.status
    )

    case Lifecycle.ensure_session_running(session, opencode_opts) do
      {:ok, session} ->
        opts = Helpers.with_base_url(session, opencode_opts)
        base_url = Keyword.get(opts, :base_url)

        Logger.info("Sending message to OpenCode",
          session_id: session.id,
          opencode_session_id: session.opencode_session_id,
          base_url: base_url
        )

        result = OpenCodeClient.client().send_message(session.opencode_session_id, params, opts)

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
    case Lifecycle.ensure_session_running(session, opencode_opts) do
      {:ok, session} ->
        opts = Helpers.with_base_url(session, opencode_opts)
        OpenCodeClient.client().send_message_async(session.opencode_session_id, params, opts)

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Gets messages from a session.
  """
  def get_messages(session, opts \\ []) do
    if session.opencode_session_id do
      opts = Helpers.with_base_url(session, opts)
      OpenCodeClient.client().list_messages(session.opencode_session_id, opts)
    else
      {:error, :no_opencode_session}
    end
  end

  @doc """
  Gets the diff for a session.
  """
  def get_diff(session, opts \\ []) do
    if session.opencode_session_id do
      opts = Helpers.with_base_url(session, opts)
      OpenCodeClient.client().get_session_diff(session.opencode_session_id, opts)
    else
      {:error, :no_opencode_session}
    end
  end

  @doc """
  Gets the todo list for a session.
  """
  def get_todos(session, opts \\ []) do
    if session.opencode_session_id do
      opts = Helpers.with_base_url(session, opts)
      OpenCodeClient.client().get_session_todos(session.opencode_session_id, opts)
    else
      {:error, :no_opencode_session}
    end
  end
end
