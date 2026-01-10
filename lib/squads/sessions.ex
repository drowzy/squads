defmodule Squads.Sessions do
  @moduledoc """
  The Sessions context manages OpenCode session lifecycle.

  Sessions represent work being done by agents. This context provides
  functions to create, start, stop, and query sessions, integrating with the
  OpenCode server via the HTTP client.
  """

  alias Squads.Sessions.Queries
  alias Squads.Sessions.Lifecycle
  alias Squads.Sessions.Messages
  alias Squads.Sessions.Operations
  alias Squads.Sessions.Helpers
  alias Squads.Sessions.Transcripts

  # ============================================================================
  # Public API Redirections
  # ============================================================================

  defdelegate with_base_url(session, opts), to: Helpers
  defdelegate get_base_url_for_session(session), to: Helpers

  # ============================================================================
  # Session Queries
  # ============================================================================

  defdelegate list_sessions, to: Queries
  defdelegate list_sessions_for_agent(agent_id), to: Queries
  defdelegate list_sessions_by_status(status), to: Queries
  defdelegate list_sessions_by_agent_and_status(agent_id, status), to: Queries
  defdelegate list_running_sessions, to: Queries
  defdelegate get_session!(id), to: Queries
  defdelegate get_session(id), to: Queries
  defdelegate get_session_by_opencode_id(opencode_session_id), to: Queries
  defdelegate fetch_session(id), to: Queries
  defdelegate fetch_session_by_opencode_id(opencode_session_id), to: Queries

  # ============================================================================
  # Lifecycle
  # ============================================================================

  defdelegate normalize_params(params), to: Lifecycle
  defdelegate create_session(attrs), to: Lifecycle
  defdelegate create_and_start_session(attrs, opencode_opts \\ []), to: Lifecycle
  defdelegate start_session(session, opencode_opts \\ []), to: Lifecycle
  defdelegate stop_session(session, exit_code \\ 0, opts \\ []), to: Lifecycle
  defdelegate abort_session(session, opencode_opts \\ []), to: Lifecycle
  defdelegate archive_session(session, opencode_opts \\ []), to: Lifecycle
  defdelegate cancel_session(session), to: Lifecycle
  defdelegate pause_session(session), to: Lifecycle
  defdelegate resume_session(session), to: Lifecycle
  defdelegate new_session_for_agent(agent_id, attrs \\ %{}), to: Lifecycle
  defdelegate ensure_session_running(session, opencode_opts \\ []), to: Lifecycle
  defdelegate sync_session_status(session), to: Lifecycle

  # ============================================================================
  # Session Messages
  # ============================================================================

  defdelegate send_message(session, params, opencode_opts \\ []), to: Messages
  defdelegate send_message_async(session, params, opencode_opts \\ []), to: Messages
  defdelegate get_messages(session, opts \\ []), to: Messages
  defdelegate get_diff(session, opts \\ []), to: Messages
  defdelegate get_todos(session, opts \\ []), to: Messages

  # ==========================================================================
  # Persisted transcripts
  # ==========================================================================

  defdelegate sync_session_transcript(session, opts \\ []), to: Transcripts

  defdelegate list_transcript_entries(session_id, opts \\ []),
    to: Transcripts,
    as: :list_entries_for_session

  defdelegate list_transcript_entries_for_sessions(session_ids, opts \\ []),
    to: Transcripts,
    as: :list_entries_for_sessions

  # ============================================================================
  # Operations & Commands
  # ============================================================================

  defdelegate dispatch_prompt(id, prompt, opts \\ []), to: Operations
  defdelegate dispatch_prompt_async(id, prompt, opts \\ []), to: Operations
  defdelegate dispatch_command(id, command, opts \\ []), to: Operations
  defdelegate dispatch_shell(id, command, opts \\ []), to: Operations
  defdelegate dispatch_abort(id, opts \\ []), to: Operations
  defdelegate dispatch_archive(id, opts \\ []), to: Operations
  defdelegate local_command?(command), to: Operations
  defdelegate execute_command(session, command, params \\ [], opencode_opts \\ []), to: Operations
  defdelegate run_shell(session, command, params \\ [], opencode_opts \\ []), to: Operations
  defdelegate send_prompt(session, prompt, opts \\ []), to: Operations
  defdelegate send_prompt_async(session, prompt, opts \\ []), to: Operations

  defdelegate get_squad_status(squad_id), to: Operations
end
