defmodule Squads.SessionsTest do
  use Squads.DataCase, async: true

  alias Squads.Sessions
  alias Squads.Sessions.Session
  alias Squads.Agents
  alias Squads.Projects
  alias Squads.Squads, as: SquadsContext
  alias Squads.Tickets

  # Helper to create an agent for testing
  defp create_test_agent(_context \\ %{}) do
    # Create a temp project and squad first
    tmp_dir = System.tmp_dir!() |> Path.join("squads_test_#{:rand.uniform(1_000_000)}")
    File.mkdir_p!(tmp_dir)

    on_exit(fn -> File.rm_rf!(tmp_dir) end)

    {:ok, project} = Projects.init(tmp_dir, "test-project")
    {:ok, squad} = SquadsContext.create_squad(%{project_id: project.id, name: "Test Squad"})

    {:ok, agent} =
      Agents.create_agent(%{squad_id: squad.id, name: "BlueOcean", slug: "blue-ocean"})

    %{agent: agent, project: project, squad: squad}
  end

  # Helper to create a ticket for testing
  defp create_test_ticket(project_id) do
    {:ok, ticket} =
      Tickets.create_ticket(%{
        project_id: project_id,
        beads_id: "bd-#{:rand.uniform(1_000_000)}",
        title: "Test Ticket"
      })

    ticket
  end

  describe "list_sessions/0" do
    test "returns empty list when no sessions" do
      assert Sessions.list_sessions() == []
    end

    test "returns all sessions" do
      %{agent: agent} = create_test_agent()

      {:ok, _session1} = Sessions.create_session(%{agent_id: agent.id, ticket_key: "bd-1"})
      {:ok, _session2} = Sessions.create_session(%{agent_id: agent.id, ticket_key: "bd-2"})

      sessions = Sessions.list_sessions()
      assert length(sessions) == 2
      # Verify both ticket_keys are present
      ticket_keys = Enum.map(sessions, & &1.ticket_key)
      assert "bd-1" in ticket_keys
      assert "bd-2" in ticket_keys
    end
  end

  describe "list_sessions_for_agent/1" do
    test "returns sessions for specific agent only" do
      %{agent: agent1, squad: squad} = create_test_agent()

      {:ok, agent2} =
        Agents.create_agent(%{squad_id: squad.id, name: "RedLake", slug: "red-lake"})

      {:ok, _s1} = Sessions.create_session(%{agent_id: agent1.id, ticket_key: "bd-1"})
      {:ok, _s2} = Sessions.create_session(%{agent_id: agent2.id, ticket_key: "bd-2"})

      sessions = Sessions.list_sessions_for_agent(agent1.id)
      assert length(sessions) == 1
      assert hd(sessions).agent_id == agent1.id
    end
  end

  describe "list_sessions_by_status/1" do
    test "returns sessions filtered by status" do
      %{agent: agent} = create_test_agent()

      {:ok, s1} = Sessions.create_session(%{agent_id: agent.id, ticket_key: "bd-1"})

      {:ok, _s2} =
        Sessions.create_session(%{agent_id: agent.id, ticket_key: "bd-2", status: "running"})

      pending = Sessions.list_sessions_by_status("pending")
      running = Sessions.list_sessions_by_status("running")

      assert length(pending) == 1
      assert hd(pending).id == s1.id
      assert length(running) == 1
    end
  end

  describe "list_running_sessions/0" do
    test "returns only running sessions" do
      %{agent: agent} = create_test_agent()

      {:ok, _} = Sessions.create_session(%{agent_id: agent.id, status: "pending"})
      {:ok, running} = Sessions.create_session(%{agent_id: agent.id, status: "running"})

      sessions = Sessions.list_running_sessions()
      assert length(sessions) == 1
      assert hd(sessions).id == running.id
    end
  end

  describe "get_session!/1" do
    test "returns session by id" do
      %{agent: agent} = create_test_agent()
      {:ok, session} = Sessions.create_session(%{agent_id: agent.id})

      found = Sessions.get_session!(session.id)
      assert found.id == session.id
    end

    test "raises for unknown id" do
      assert_raise Ecto.NoResultsError, fn ->
        Sessions.get_session!(Ecto.UUID.generate())
      end
    end
  end

  describe "get_session/1" do
    test "returns nil for unknown id" do
      assert Sessions.get_session(Ecto.UUID.generate()) == nil
    end
  end

  describe "get_session_by_opencode_id/1" do
    test "returns session by opencode_session_id" do
      %{agent: agent} = create_test_agent()

      {:ok, session} =
        Sessions.create_session(%{agent_id: agent.id, opencode_session_id: "oc-123"})

      found = Sessions.get_session_by_opencode_id("oc-123")
      assert found.id == session.id
    end

    test "returns nil for unknown opencode_session_id" do
      assert Sessions.get_session_by_opencode_id("unknown") == nil
    end
  end

  describe "create_session/1" do
    test "creates session with required fields" do
      %{agent: agent} = create_test_agent()

      assert {:ok, session} = Sessions.create_session(%{agent_id: agent.id})
      assert session.agent_id == agent.id
      assert session.status == "pending"
    end

    test "creates session with optional fields" do
      %{agent: agent} = create_test_agent()

      attrs = %{
        agent_id: agent.id,
        ticket_key: "bd-42",
        worktree_path: "/tmp/worktree",
        branch: "feature/test",
        metadata: %{"custom" => "data"}
      }

      assert {:ok, session} = Sessions.create_session(attrs)
      assert session.ticket_key == "bd-42"
      assert session.worktree_path == "/tmp/worktree"
      assert session.branch == "feature/test"
      assert session.metadata == %{"custom" => "data"}
    end

    test "fails without agent_id" do
      assert {:error, changeset} = Sessions.create_session(%{})
      assert "can't be blank" in errors_on(changeset).agent_id
    end

    test "fails with invalid status" do
      %{agent: agent} = create_test_agent()

      assert {:error, changeset} =
               Sessions.create_session(%{agent_id: agent.id, status: "invalid"})

      assert "is invalid" in errors_on(changeset).status
    end
  end

  describe "cancel_session/1" do
    test "cancels a pending session" do
      %{agent: agent} = create_test_agent()
      {:ok, session} = Sessions.create_session(%{agent_id: agent.id})

      assert {:ok, cancelled} = Sessions.cancel_session(session)
      assert cancelled.status == "cancelled"
    end

    test "fails to cancel a running session" do
      %{agent: agent} = create_test_agent()
      {:ok, session} = Sessions.create_session(%{agent_id: agent.id, status: "running"})

      assert {:error, :already_started} = Sessions.cancel_session(session)
    end
  end

  describe "pause_session/1" do
    test "pauses a running session" do
      %{agent: agent} = create_test_agent()
      {:ok, session} = Sessions.create_session(%{agent_id: agent.id, status: "running"})

      assert {:ok, paused} = Sessions.pause_session(session)
      assert paused.status == "paused"
    end

    test "fails to pause a non-running session" do
      %{agent: agent} = create_test_agent()
      {:ok, session} = Sessions.create_session(%{agent_id: agent.id})

      assert {:error, :not_running} = Sessions.pause_session(session)
    end
  end

  describe "resume_session/1" do
    test "resumes a paused session" do
      %{agent: agent} = create_test_agent()
      {:ok, session} = Sessions.create_session(%{agent_id: agent.id, status: "paused"})

      assert {:ok, resumed} = Sessions.resume_session(session)
      assert resumed.status == "running"
    end

    test "fails to resume a non-paused session" do
      %{agent: agent} = create_test_agent()
      {:ok, session} = Sessions.create_session(%{agent_id: agent.id, status: "running"})

      assert {:error, :not_paused} = Sessions.resume_session(session)
    end
  end

  describe "Session.start_changeset/2" do
    test "marks session as running with started_at" do
      %{agent: agent} = create_test_agent()
      {:ok, session} = Sessions.create_session(%{agent_id: agent.id})

      changeset = Session.start_changeset(session, %{opencode_session_id: "oc-123"})
      assert changeset.changes.status == "running"
      assert changeset.changes.started_at != nil
      assert changeset.changes.opencode_session_id == "oc-123"
    end
  end

  describe "Session.finish_changeset/2" do
    test "marks session as completed with exit_code 0" do
      %{agent: agent} = create_test_agent()
      {:ok, session} = Sessions.create_session(%{agent_id: agent.id, status: "running"})

      changeset = Session.finish_changeset(session, 0)
      assert changeset.changes.status == "completed"
      assert changeset.changes.exit_code == 0
      assert changeset.changes.finished_at != nil
    end

    test "marks session as failed with non-zero exit_code" do
      %{agent: agent} = create_test_agent()
      {:ok, session} = Sessions.create_session(%{agent_id: agent.id, status: "running"})

      changeset = Session.finish_changeset(session, 1)
      assert changeset.changes.status == "failed"
      assert changeset.changes.exit_code == 1
    end
  end

  # ============================================================================
  # Dispatch Tests (without OpenCode server)
  # ============================================================================

  describe "execute_command/4" do
    test "returns error when session has no opencode_session_id" do
      %{agent: agent} = create_test_agent()
      {:ok, session} = Sessions.create_session(%{agent_id: agent.id, status: "running"})

      assert {:error, :no_opencode_session} = Sessions.execute_command(session, "/compact")
    end

    test "returns error when session is not running" do
      %{agent: agent} = create_test_agent()

      {:ok, session} =
        Sessions.create_session(%{
          agent_id: agent.id,
          status: "pending",
          opencode_session_id: "ses_123"
        })

      assert {:error, :session_not_active} = Sessions.execute_command(session, "/compact")
    end
  end

  describe "run_shell/4" do
    test "returns error when session has no opencode_session_id" do
      %{agent: agent} = create_test_agent()
      {:ok, session} = Sessions.create_session(%{agent_id: agent.id, status: "running"})

      assert {:error, :no_opencode_session} = Sessions.run_shell(session, "mix test")
    end

    test "returns error when session is not running" do
      %{agent: agent} = create_test_agent()

      {:ok, session} =
        Sessions.create_session(%{
          agent_id: agent.id,
          status: "completed",
          opencode_session_id: "ses_123"
        })

      assert {:error, :session_not_active} = Sessions.run_shell(session, "mix test")
    end
  end

  describe "send_prompt/3" do
    test "returns error when session is not active" do
      %{agent: agent} = create_test_agent()
      {:ok, session} = Sessions.create_session(%{agent_id: agent.id, status: "pending"})

      assert {:error, :no_opencode_session} = Sessions.send_prompt(session, "Hello")
    end

    test "returns error when session has no opencode_session_id" do
      %{agent: agent} = create_test_agent()
      {:ok, session} = Sessions.create_session(%{agent_id: agent.id, status: "running"})

      assert {:error, :no_opencode_session} = Sessions.send_prompt(session, "Hello")
    end
  end

  describe "send_prompt_async/3" do
    test "returns error when session is not active" do
      %{agent: agent} = create_test_agent()
      {:ok, session} = Sessions.create_session(%{agent_id: agent.id, status: "pending"})

      assert {:error, :no_opencode_session} = Sessions.send_prompt_async(session, "Hello")
    end
  end

  # ============================================================================
  # Ticket-Session Linking Tests
  # ============================================================================

  describe "list_sessions_for_ticket/1" do
    test "returns empty list when no sessions for ticket" do
      %{project: project} = create_test_agent()
      ticket = create_test_ticket(project.id)

      assert Sessions.list_sessions_for_ticket(ticket.id) == []
    end

    test "returns sessions linked to a ticket" do
      %{agent: agent, project: project} = create_test_agent()
      ticket = create_test_ticket(project.id)

      {:ok, s1} = Sessions.create_session(%{agent_id: agent.id, ticket_id: ticket.id})
      {:ok, _s2} = Sessions.create_session(%{agent_id: agent.id})

      sessions = Sessions.list_sessions_for_ticket(ticket.id)
      assert length(sessions) == 1
      assert hd(sessions).id == s1.id
    end

    test "returns multiple sessions for same ticket" do
      %{agent: agent, project: project} = create_test_agent()
      ticket = create_test_ticket(project.id)

      {:ok, _s1} = Sessions.create_session(%{agent_id: agent.id, ticket_id: ticket.id})
      {:ok, _s2} = Sessions.create_session(%{agent_id: agent.id, ticket_id: ticket.id})

      sessions = Sessions.list_sessions_for_ticket(ticket.id)
      assert length(sessions) == 2
    end
  end

  describe "link_session_to_ticket/2" do
    test "links a session to a ticket" do
      %{agent: agent, project: project} = create_test_agent()
      ticket = create_test_ticket(project.id)
      {:ok, session} = Sessions.create_session(%{agent_id: agent.id})

      assert session.ticket_id == nil

      assert {:ok, updated} = Sessions.link_session_to_ticket(session.id, ticket.id)
      assert updated.ticket_id == ticket.id
    end

    test "returns not_found for unknown session" do
      %{project: project} = create_test_agent()
      ticket = create_test_ticket(project.id)

      assert {:error, :not_found} =
               Sessions.link_session_to_ticket(Ecto.UUID.generate(), ticket.id)
    end
  end

  describe "unlink_session_from_ticket/1" do
    test "unlinks a session from its ticket" do
      %{agent: agent, project: project} = create_test_agent()
      ticket = create_test_ticket(project.id)
      {:ok, session} = Sessions.create_session(%{agent_id: agent.id, ticket_id: ticket.id})

      assert session.ticket_id == ticket.id

      assert {:ok, updated} = Sessions.unlink_session_from_ticket(session.id)
      assert updated.ticket_id == nil
    end

    test "returns not_found for unknown session" do
      assert {:error, :not_found} = Sessions.unlink_session_from_ticket(Ecto.UUID.generate())
    end
  end

  describe "create_session_for_ticket/2" do
    test "creates a session linked to a ticket" do
      %{agent: agent, project: project} = create_test_agent()
      ticket = create_test_ticket(project.id)

      assert {:ok, session} =
               Sessions.create_session_for_ticket(ticket.id, %{agent_id: agent.id})

      assert session.ticket_id == ticket.id
      assert session.agent_id == agent.id
    end

    test "accepts a ticket struct" do
      %{agent: agent, project: project} = create_test_agent()
      ticket = create_test_ticket(project.id)

      assert {:ok, session} = Sessions.create_session_for_ticket(ticket, %{agent_id: agent.id})
      assert session.ticket_id == ticket.id
    end
  end

  describe "get_session_with_ticket/1" do
    test "returns session with ticket preloaded" do
      %{agent: agent, project: project} = create_test_agent()
      ticket = create_test_ticket(project.id)
      {:ok, session} = Sessions.create_session(%{agent_id: agent.id, ticket_id: ticket.id})

      found = Sessions.get_session_with_ticket(session.id)
      assert found.id == session.id
      assert found.ticket.id == ticket.id
      assert found.ticket.title == "Test Ticket"
    end

    test "returns session with nil ticket when not linked" do
      %{agent: agent} = create_test_agent()
      {:ok, session} = Sessions.create_session(%{agent_id: agent.id})

      found = Sessions.get_session_with_ticket(session.id)
      assert found.id == session.id
      assert found.ticket == nil
    end

    test "returns nil for unknown session" do
      assert Sessions.get_session_with_ticket(Ecto.UUID.generate()) == nil
    end
  end
end
