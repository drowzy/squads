defmodule Squads.EventsTest do
  use Squads.DataCase, async: true

  alias Squads.Events
  alias Squads.Events.Event
  alias Squads.Projects
  alias Squads.Squads, as: SquadsContext
  alias Squads.Agents
  alias Squads.Sessions

  # Helper to create a project for testing
  defp create_test_project(_context \\ %{}) do
    tmp_dir = System.tmp_dir!() |> Path.join("squads_test_#{:rand.uniform(1_000_000)}")
    File.mkdir_p!(tmp_dir)

    on_exit(fn -> File.rm_rf!(tmp_dir) end)

    {:ok, project} = Projects.init(tmp_dir, "test-project")
    %{project: project}
  end

  # Helper to create a full test hierarchy
  defp create_test_hierarchy(context \\ %{}) do
    %{project: project} = create_test_project(context)
    {:ok, squad} = SquadsContext.create_squad(%{project_id: project.id, name: "Test Squad"})

    {:ok, agent} =
      Agents.create_agent(%{squad_id: squad.id, name: "BlueOcean", slug: "blue-ocean"})

    {:ok, session} = Sessions.create_session(%{agent_id: agent.id, ticket_key: "bd-1"})

    %{project: project, squad: squad, agent: agent, session: session}
  end

  describe "create_event/1" do
    test "creates event with required fields" do
      %{project: project} = create_test_project()

      attrs = %{
        kind: "session.started",
        project_id: project.id
      }

      assert {:ok, event} = Events.create_event(attrs)
      assert event.kind == "session.started"
      assert event.project_id == project.id
      assert event.occurred_at != nil
    end

    test "creates event with all fields" do
      %{project: project, agent: agent, session: session} = create_test_hierarchy()

      attrs = %{
        kind: "session.completed",
        project_id: project.id,
        agent_id: agent.id,
        session_id: session.id,
        payload: %{"exit_code" => 0, "duration_ms" => 5000}
      }

      assert {:ok, event} = Events.create_event(attrs)
      assert event.kind == "session.completed"
      assert event.agent_id == agent.id
      assert event.session_id == session.id
      assert event.payload["exit_code"] == 0
    end

    test "fails without project_id" do
      assert {:error, changeset} = Events.create_event(%{kind: "session.started"})
      assert "can't be blank" in errors_on(changeset).project_id
    end

    test "fails without kind" do
      %{project: project} = create_test_project()

      assert {:error, changeset} = Events.create_event(%{project_id: project.id})
      assert "can't be blank" in errors_on(changeset).kind
    end

    test "fails with invalid kind" do
      %{project: project} = create_test_project()

      attrs = %{kind: "invalid.event.kind", project_id: project.id}
      assert {:error, changeset} = Events.create_event(attrs)
      assert "is invalid" in errors_on(changeset).kind
    end

    test "sets occurred_at automatically if not provided" do
      %{project: project} = create_test_project()

      attrs = %{kind: "session.started", project_id: project.id}
      {:ok, event} = Events.create_event(attrs)

      assert event.occurred_at != nil
      # Should be recent (within last minute)
      diff = DateTime.diff(DateTime.utc_now(), event.occurred_at, :second)
      assert diff < 60
    end

    test "respects custom occurred_at" do
      %{project: project} = create_test_project()
      custom_time = ~U[2025-01-01 12:00:00Z]

      attrs = %{kind: "session.started", project_id: project.id, occurred_at: custom_time}
      {:ok, event} = Events.create_event(attrs)

      assert event.occurred_at == custom_time
    end
  end

  describe "create_event!/1" do
    test "creates event or raises" do
      %{project: project} = create_test_project()

      event = Events.create_event!(%{kind: "session.started", project_id: project.id})
      assert event.kind == "session.started"
    end

    test "raises on invalid attrs" do
      assert_raise Ecto.InvalidChangesetError, fn ->
        Events.create_event!(%{kind: "invalid"})
      end
    end
  end

  describe "list_events_for_project/2" do
    test "returns events for project in descending order" do
      %{project: project} = create_test_project()

      # Use explicit timestamps to ensure ordering
      old_time = ~U[2025-01-01 10:00:00Z]
      new_time = ~U[2025-01-01 11:00:00Z]

      {:ok, _e1} =
        Events.create_event(%{
          kind: "session.started",
          project_id: project.id,
          occurred_at: old_time
        })

      {:ok, e2} =
        Events.create_event(%{
          kind: "session.completed",
          project_id: project.id,
          occurred_at: new_time
        })

      events = Events.list_events_for_project(project.id)
      assert length(events) == 2
      # Most recent first
      assert hd(events).id == e2.id
    end

    test "respects limit option" do
      %{project: project} = create_test_project()

      for _ <- 1..5 do
        Events.create_event!(%{kind: "session.started", project_id: project.id})
      end

      events = Events.list_events_for_project(project.id, limit: 3)
      assert length(events) == 3
    end

    test "returns empty list for unknown project" do
      events = Events.list_events_for_project(Ecto.UUID.generate())
      assert events == []
    end
  end

  describe "list_events_for_session/2" do
    test "returns events for specific session" do
      %{project: project, agent: agent} = create_test_hierarchy()
      {:ok, session1} = Sessions.create_session(%{agent_id: agent.id})
      {:ok, session2} = Sessions.create_session(%{agent_id: agent.id})

      {:ok, _} =
        Events.create_event(%{
          kind: "session.started",
          project_id: project.id,
          session_id: session1.id
        })

      {:ok, _} =
        Events.create_event(%{
          kind: "session.started",
          project_id: project.id,
          session_id: session2.id
        })

      events = Events.list_events_for_session(session1.id)
      assert length(events) == 1
      assert hd(events).session_id == session1.id
    end
  end

  describe "list_events_for_agent/2" do
    test "returns events for specific agent" do
      %{project: project, squad: squad, agent: agent1} = create_test_hierarchy()

      {:ok, agent2} =
        Agents.create_agent(%{squad_id: squad.id, name: "RedLake", slug: "red-lake"})

      {:ok, _} =
        Events.create_event(%{
          kind: "agent.created",
          project_id: project.id,
          agent_id: agent1.id
        })

      {:ok, _} =
        Events.create_event(%{
          kind: "agent.created",
          project_id: project.id,
          agent_id: agent2.id
        })

      events = Events.list_events_for_agent(agent1.id)
      assert length(events) == 1
      assert hd(events).agent_id == agent1.id
    end
  end

  describe "list_events_by_kind/2" do
    test "returns events filtered by kind" do
      %{project: project} = create_test_project()

      {:ok, _} = Events.create_event(%{kind: "session.started", project_id: project.id})
      {:ok, _} = Events.create_event(%{kind: "session.completed", project_id: project.id})
      {:ok, _} = Events.create_event(%{kind: "session.started", project_id: project.id})

      started_events = Events.list_events_by_kind("session.started")
      assert length(started_events) == 2
      assert Enum.all?(started_events, &(&1.kind == "session.started"))
    end

    test "filters by project_id when provided" do
      %{project: project1} = create_test_project()
      %{project: project2} = create_test_project()

      {:ok, _} = Events.create_event(%{kind: "session.started", project_id: project1.id})
      {:ok, _} = Events.create_event(%{kind: "session.started", project_id: project2.id})

      events = Events.list_events_by_kind("session.started", project_id: project1.id)
      assert length(events) == 1
      assert hd(events).project_id == project1.id
    end
  end

  describe "list_events_since/2" do
    test "returns events after given timestamp" do
      %{project: project} = create_test_project()

      old_time = ~U[2025-01-01 10:00:00Z]
      cutoff = ~U[2025-01-01 11:00:00Z]
      new_time = ~U[2025-01-01 12:00:00Z]

      {:ok, _old} =
        Events.create_event(%{
          kind: "session.started",
          project_id: project.id,
          occurred_at: old_time
        })

      {:ok, new} =
        Events.create_event(%{
          kind: "session.completed",
          project_id: project.id,
          occurred_at: new_time
        })

      events = Events.list_events_since(cutoff)
      assert length(events) == 1
      assert hd(events).id == new.id
    end

    test "returns events in ascending order" do
      %{project: project} = create_test_project()
      cutoff = ~U[2024-12-31 00:00:00Z]

      old_time = ~U[2025-01-01 10:00:00Z]
      new_time = ~U[2025-01-01 11:00:00Z]

      {:ok, e1} =
        Events.create_event(%{
          kind: "session.started",
          project_id: project.id,
          occurred_at: old_time
        })

      {:ok, _e2} =
        Events.create_event(%{
          kind: "session.completed",
          project_id: project.id,
          occurred_at: new_time
        })

      events = Events.list_events_since(cutoff)
      assert length(events) == 2
      # Oldest first
      assert hd(events).id == e1.id
    end
  end

  describe "count_events_by_kind/1" do
    test "returns counts grouped by kind" do
      %{project: project} = create_test_project()

      for _ <- 1..3 do
        Events.create_event!(%{kind: "session.started", project_id: project.id})
      end

      for _ <- 1..2 do
        Events.create_event!(%{kind: "session.completed", project_id: project.id})
      end

      Events.create_event!(%{kind: "session.failed", project_id: project.id})

      counts = Events.count_events_by_kind(project.id)

      assert counts["session.started"] == 3
      assert counts["session.completed"] == 2
      assert counts["session.failed"] == 1
    end

    test "returns empty map for project with no events" do
      counts = Events.count_events_by_kind(Ecto.UUID.generate())
      assert counts == %{}
    end
  end

  describe "Event.kinds/0" do
    test "returns list of valid event kinds" do
      kinds = Event.kinds()
      assert is_list(kinds)
      assert "session.started" in kinds
      assert "session.completed" in kinds
      assert "agent.created" in kinds
    end
  end
end
