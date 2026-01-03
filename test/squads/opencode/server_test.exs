defmodule Squads.OpenCode.ServerTest do
  use Squads.DataCase
  alias Squads.OpenCode.Server

  # We need to mock the external command execution to test this properly without actually running opencode
  # But for now, let's just test the process structure and blocking behavior if possible.
  # Since :exec is used, it's hard to mock without dependency injection or Mox.

  # However, the goal is to refactor. Let's start by observing the current blocking behavior.
  # We can't easily reproduce the 60s block in a test without a slow command.

  # Instead of full integration test, let's trust the analysis:
  # handle_call calls start_project_server which calls wait_for_healthy which sleeps.
  # This definitely blocks the GenServer.

  # The plan is:
  # 1. Add Task.Supervisor to the supervision tree.
  # 2. Modify Server to use Task.Supervisor.async_nolink (or simply start_child) to run the startup.
  # 3. Handle the result in handle_info or similar.
  # 4. Handle concurrent requests for the same project_id.

  test "starts successfully" do
    # Just a placeholder to ensure the module compiles
    assert Code.ensure_loaded?(Squads.OpenCode.Server)
  end
end
