defmodule Squads.OrchestrationIntegrationTest do
  use Squads.DataCase

  alias Squads.Projects, as: Projects
  alias Squads.Squads, as: SquadsContext
  alias Squads.Agents, as: Agents
  alias Squads.Sessions, as: Sessions
  alias Squads.OpenCode.Server, as: OpenCodeServer

  @tag :tmp_dir
  @tag timeout: 180_000
  @tag :integration
  @tag :skip
  test "full orchestration lifecycle: project -> squad -> agent -> session -> server", %{
    tmp_dir: tmp_dir
  } do
    # Allow the server process to access the database connection
    # We use a loop because start_link might be async or the name might not be registered yet
    # though application start should have handled it.
    pid = Process.whereis(Squads.OpenCode.Server)

    if pid do
      Ecto.Adapters.SQL.Sandbox.allow(Squads.Repo, self(), pid)
    end

    # 1. Initialize project
    assert {:ok, project} = Projects.init(tmp_dir, "orchestration-test")

    # 2. Create squad
    assert {:ok, squad} =
             SquadsContext.create_squad(%{
               project_id: project.id,
               name: "Test Squad"
             })

    # 3. Create agent
    assert {:ok, agent} =
             Agents.create_agent(%{
               squad_id: squad.id,
               name: "GreenPanda",
               slug: "green-panda",
               role: "fullstack_engineer",
               level: "senior"
             })

    # 4. Create and start session (this triggers ensure_running)
    # We use a longer timeout for the transaction if needed, but the GenServer call
    # inside ensure_running now has 60s timeout.
    assert {:ok, session} =
             Sessions.create_and_start_session(%{
               agent_id: agent.id,
               title: "Orchestration Test Session"
             })

    assert session.status == "running"
    assert session.opencode_session_id != nil

    # 5. Verify server is actually running for this project
    assert {:ok, url} = OpenCodeServer.get_url(project.id)
    assert String.starts_with?(url, "http://127.0.0.1:")

    # 6. Verify OS process exists via erlexec (internal state check)
    # We can check the Registry for the mapping
    assert [{_pid, ^url}] = Registry.lookup(Squads.OpenCode.ServerRegistry, project.id)

    # 7. Test stopping the session
    assert {:ok, _} = Sessions.stop_session(session)

    # Note: Server keeps running for the project even if session stops
    assert {:ok, _} = OpenCodeServer.get_url(project.id)

    # 8. Verify session directory (Ticket opencode-squads-6is)
    # The server should have been started in the tmp_dir
    assert session.worktree_path == tmp_dir
  end
end
