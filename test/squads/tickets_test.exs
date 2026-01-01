defmodule Squads.TicketsTest do
  use Squads.DataCase, async: true

  alias Squads.Tickets
  alias Squads.Tickets.{Ticket, TicketDependency}
  alias Squads.Projects
  alias Squads.Squads, as: SquadsContext
  alias Squads.Agents
  alias Squads.Sessions

  # Helper to create a project
  defp create_project(tmp_dir) do
    {:ok, project} = Projects.init(tmp_dir, "test-project")
    project
  end

  # Helper to create a squad for agent assignment
  defp create_squad(project) do
    {:ok, squad} =
      SquadsContext.create_squad(%{
        project_id: project.id,
        name: "Test Squad",
        description: "For testing"
      })

    squad
  end

  # Helper to create an agent
  defp create_agent(squad) do
    {:ok, agent} =
      Agents.create_agent(%{
        squad_id: squad.id,
        name: "GreenPanda",
        slug: "green-panda",
        model: "gpt-4"
      })

    agent
  end

  describe "create_ticket/1" do
    @tag :tmp_dir
    test "creates a ticket with valid attrs", %{tmp_dir: tmp_dir} do
      project = create_project(tmp_dir)

      attrs = %{
        project_id: project.id,
        beads_id: "test-123",
        title: "Fix the bug"
      }

      assert {:ok, %Ticket{} = ticket} = Tickets.create_ticket(attrs)
      assert ticket.beads_id == "test-123"
      assert ticket.title == "Fix the bug"
      assert ticket.status == "open"
      assert ticket.priority == 2
      assert ticket.issue_type == "task"
    end

    @tag :tmp_dir
    test "creates a ticket with all fields", %{tmp_dir: tmp_dir} do
      project = create_project(tmp_dir)

      attrs = %{
        project_id: project.id,
        beads_id: "epic-1",
        title: "Big Feature",
        description: "A large feature epic",
        status: "in_progress",
        priority: 1,
        issue_type: "epic"
      }

      assert {:ok, ticket} = Tickets.create_ticket(attrs)
      assert ticket.description == "A large feature epic"
      assert ticket.status == "in_progress"
      assert ticket.priority == 1
      assert ticket.issue_type == "epic"
    end

    @tag :tmp_dir
    test "fails without required fields", %{tmp_dir: tmp_dir} do
      project = create_project(tmp_dir)

      assert {:error, changeset} = Tickets.create_ticket(%{project_id: project.id})
      assert %{beads_id: _, title: _} = errors_on(changeset)
    end

    @tag :tmp_dir
    test "fails with invalid status", %{tmp_dir: tmp_dir} do
      project = create_project(tmp_dir)

      attrs = %{
        project_id: project.id,
        beads_id: "test-1",
        title: "Test",
        status: "invalid"
      }

      assert {:error, changeset} = Tickets.create_ticket(attrs)
      assert %{status: _} = errors_on(changeset)
    end

    @tag :tmp_dir
    test "fails with duplicate beads_id in same project", %{tmp_dir: tmp_dir} do
      project = create_project(tmp_dir)

      attrs = %{project_id: project.id, beads_id: "dup-1", title: "First"}
      assert {:ok, _} = Tickets.create_ticket(attrs)

      assert {:error, changeset} = Tickets.create_ticket(attrs)
      errors = errors_on(changeset)
      # SQLite returns error on first field of unique constraint
      assert errors[:project_id] || errors[:beads_id]
    end
  end

  describe "get_ticket/1 and get_ticket_by_beads_id/2" do
    @tag :tmp_dir
    test "retrieves tickets", %{tmp_dir: tmp_dir} do
      project = create_project(tmp_dir)

      {:ok, ticket} =
        Tickets.create_ticket(%{
          project_id: project.id,
          beads_id: "get-test",
          title: "Get Test"
        })

      assert Tickets.get_ticket(ticket.id).id == ticket.id
      assert Tickets.get_ticket_by_beads_id(project.id, "get-test").id == ticket.id
      assert Tickets.get_ticket_by_beads_id(project.id, "nonexistent") == nil
    end
  end

  describe "update_ticket/2" do
    @tag :tmp_dir
    test "updates a ticket", %{tmp_dir: tmp_dir} do
      project = create_project(tmp_dir)

      {:ok, ticket} =
        Tickets.create_ticket(%{
          project_id: project.id,
          beads_id: "update-1",
          title: "Original"
        })

      assert {:ok, updated} =
               Tickets.update_ticket(ticket, %{
                 title: "Updated Title",
                 status: "in_progress",
                 priority: 0
               })

      assert updated.title == "Updated Title"
      assert updated.status == "in_progress"
      assert updated.priority == 0
    end
  end

  describe "delete_ticket/1" do
    @tag :tmp_dir
    test "deletes a ticket", %{tmp_dir: tmp_dir} do
      project = create_project(tmp_dir)

      {:ok, ticket} =
        Tickets.create_ticket(%{
          project_id: project.id,
          beads_id: "delete-1",
          title: "To Delete"
        })

      assert {:ok, _} = Tickets.delete_ticket(ticket)
      assert Tickets.get_ticket(ticket.id) == nil
    end
  end

  describe "list_tickets/2" do
    @tag :tmp_dir
    test "lists all tickets for a project", %{tmp_dir: tmp_dir} do
      project = create_project(tmp_dir)

      {:ok, _} =
        Tickets.create_ticket(%{project_id: project.id, beads_id: "list-1", title: "First"})

      {:ok, _} =
        Tickets.create_ticket(%{project_id: project.id, beads_id: "list-2", title: "Second"})

      tickets = Tickets.list_tickets(project.id)
      assert length(tickets) == 2
    end

    @tag :tmp_dir
    test "filters by status", %{tmp_dir: tmp_dir} do
      project = create_project(tmp_dir)

      {:ok, _} =
        Tickets.create_ticket(%{
          project_id: project.id,
          beads_id: "f-1",
          title: "Open",
          status: "open"
        })

      {:ok, _} =
        Tickets.create_ticket(%{
          project_id: project.id,
          beads_id: "f-2",
          title: "In Progress",
          status: "in_progress"
        })

      open = Tickets.list_tickets(project.id, status: "open")
      assert length(open) == 1
      assert hd(open).title == "Open"
    end

    @tag :tmp_dir
    test "orders by priority and updated_at", %{tmp_dir: tmp_dir} do
      project = create_project(tmp_dir)

      {:ok, _} =
        Tickets.create_ticket(%{
          project_id: project.id,
          beads_id: "o-1",
          title: "Low",
          priority: 3
        })

      {:ok, _} =
        Tickets.create_ticket(%{
          project_id: project.id,
          beads_id: "o-2",
          title: "High",
          priority: 1
        })

      {:ok, _} =
        Tickets.create_ticket(%{
          project_id: project.id,
          beads_id: "o-3",
          title: "Critical",
          priority: 0
        })

      tickets = Tickets.list_tickets(project.id)
      priorities = Enum.map(tickets, & &1.priority)
      assert priorities == [0, 1, 3]
    end
  end

  describe "list_ready_tickets/1" do
    @tag :tmp_dir
    test "returns open tickets without blocking deps", %{tmp_dir: tmp_dir} do
      project = create_project(tmp_dir)

      {:ok, ready} =
        Tickets.create_ticket(%{
          project_id: project.id,
          beads_id: "r-1",
          title: "Ready",
          status: "open"
        })

      {:ok, blocker} =
        Tickets.create_ticket(%{
          project_id: project.id,
          beads_id: "r-2",
          title: "Blocker",
          status: "open"
        })

      {:ok, blocked} =
        Tickets.create_ticket(%{
          project_id: project.id,
          beads_id: "r-3",
          title: "Blocked",
          status: "open"
        })

      # blocked depends on blocker
      {:ok, _} = Tickets.add_dependency(blocked.id, blocker.id, "blocks")

      ready_tickets = Tickets.list_ready_tickets(project.id)
      ready_ids = Enum.map(ready_tickets, & &1.id)

      assert ready.id in ready_ids
      assert blocker.id in ready_ids
      refute blocked.id in ready_ids
    end

    @tag :tmp_dir
    test "blocked tickets become ready when blocker is closed", %{tmp_dir: tmp_dir} do
      project = create_project(tmp_dir)

      {:ok, blocker} =
        Tickets.create_ticket(%{
          project_id: project.id,
          beads_id: "rb-1",
          title: "Blocker",
          status: "open"
        })

      {:ok, blocked} =
        Tickets.create_ticket(%{
          project_id: project.id,
          beads_id: "rb-2",
          title: "Blocked",
          status: "open"
        })

      {:ok, _} = Tickets.add_dependency(blocked.id, blocker.id, "blocks")

      # Initially blocked
      ready = Tickets.list_ready_tickets(project.id)
      refute Enum.any?(ready, &(&1.id == blocked.id))

      # Close blocker
      {:ok, _} = Tickets.update_ticket(blocker, %{status: "closed"})

      # Now ready
      ready = Tickets.list_ready_tickets(project.id)
      assert Enum.any?(ready, &(&1.id == blocked.id))
    end
  end

  describe "list_in_progress_tickets/1" do
    @tag :tmp_dir
    test "returns in_progress tickets", %{tmp_dir: tmp_dir} do
      project = create_project(tmp_dir)

      {:ok, _} =
        Tickets.create_ticket(%{
          project_id: project.id,
          beads_id: "ip-1",
          title: "Open",
          status: "open"
        })

      {:ok, in_prog} =
        Tickets.create_ticket(%{
          project_id: project.id,
          beads_id: "ip-2",
          title: "Working",
          status: "in_progress"
        })

      result = Tickets.list_in_progress_tickets(project.id)
      assert length(result) == 1
      assert hd(result).id == in_prog.id
    end
  end

  describe "list_blocked_tickets/1" do
    @tag :tmp_dir
    test "returns tickets with blocking deps", %{tmp_dir: tmp_dir} do
      project = create_project(tmp_dir)

      {:ok, blocker} =
        Tickets.create_ticket(%{
          project_id: project.id,
          beads_id: "bl-1",
          title: "Blocker",
          status: "open"
        })

      {:ok, blocked} =
        Tickets.create_ticket(%{
          project_id: project.id,
          beads_id: "bl-2",
          title: "Blocked",
          status: "open"
        })

      {:ok, _} = Tickets.add_dependency(blocked.id, blocker.id, "blocks")

      result = Tickets.list_blocked_tickets(project.id)
      assert length(result) == 1
      assert hd(result).id == blocked.id
    end
  end

  describe "assign_ticket/3 and unassign_ticket/1" do
    @tag :tmp_dir
    test "assigns and unassigns tickets", %{tmp_dir: tmp_dir} do
      project = create_project(tmp_dir)
      squad = create_squad(project)
      agent = create_agent(squad)

      {:ok, ticket} =
        Tickets.create_ticket(%{
          project_id: project.id,
          beads_id: "assign-1",
          title: "Assign Test"
        })

      # Assign
      {:ok, assigned} = Tickets.assign_ticket(ticket, agent.id, "GreenPanda")
      assert assigned.assignee_id == agent.id
      assert assigned.assignee_name == "GreenPanda"

      # Unassign
      {:ok, unassigned} = Tickets.unassign_ticket(assigned)
      assert unassigned.assignee_id == nil
      assert unassigned.assignee_name == nil
    end
  end

  describe "list_agent_tickets/1" do
    @tag :tmp_dir
    test "returns tickets for an agent", %{tmp_dir: tmp_dir} do
      project = create_project(tmp_dir)
      squad = create_squad(project)
      agent = create_agent(squad)

      {:ok, ticket1} =
        Tickets.create_ticket(%{project_id: project.id, beads_id: "at-1", title: "Agent Task 1"})

      {:ok, _ticket2} =
        Tickets.create_ticket(%{project_id: project.id, beads_id: "at-2", title: "Unassigned"})

      {:ok, ticket3} =
        Tickets.create_ticket(%{project_id: project.id, beads_id: "at-3", title: "Agent Task 2"})

      {:ok, _} = Tickets.assign_ticket(ticket1, agent.id)
      {:ok, _} = Tickets.assign_ticket(ticket3, agent.id)

      result = Tickets.list_agent_tickets(agent.id)
      assert length(result) == 2
    end

    @tag :tmp_dir
    test "excludes closed tickets", %{tmp_dir: tmp_dir} do
      project = create_project(tmp_dir)
      squad = create_squad(project)
      agent = create_agent(squad)

      {:ok, open} =
        Tickets.create_ticket(%{
          project_id: project.id,
          beads_id: "ac-1",
          title: "Open",
          status: "open"
        })

      {:ok, closed} =
        Tickets.create_ticket(%{
          project_id: project.id,
          beads_id: "ac-2",
          title: "Closed",
          status: "closed"
        })

      {:ok, _} = Tickets.assign_ticket(open, agent.id)
      {:ok, _} = Tickets.assign_ticket(closed, agent.id)

      result = Tickets.list_agent_tickets(agent.id)
      assert length(result) == 1
      assert hd(result).id == open.id
    end
  end

  describe "parent/child relationships" do
    @tag :tmp_dir
    test "creates parent-child hierarchy", %{tmp_dir: tmp_dir} do
      project = create_project(tmp_dir)

      {:ok, epic} =
        Tickets.create_ticket(%{
          project_id: project.id,
          beads_id: "epic-1",
          title: "Big Epic",
          issue_type: "epic"
        })

      {:ok, child1} =
        Tickets.create_ticket(%{
          project_id: project.id,
          beads_id: "epic-1.1",
          title: "Subtask 1",
          parent_id: epic.id
        })

      {:ok, child2} =
        Tickets.create_ticket(%{
          project_id: project.id,
          beads_id: "epic-1.2",
          title: "Subtask 2",
          parent_id: epic.id
        })

      children = Tickets.list_children(epic.id)
      assert length(children) == 2
      child_ids = Enum.map(children, & &1.id)
      assert child1.id in child_ids
      assert child2.id in child_ids
    end
  end

  describe "dependencies" do
    @tag :tmp_dir
    test "add_dependency/3 creates dependency", %{tmp_dir: tmp_dir} do
      project = create_project(tmp_dir)

      {:ok, t1} =
        Tickets.create_ticket(%{project_id: project.id, beads_id: "d-1", title: "First"})

      {:ok, t2} =
        Tickets.create_ticket(%{project_id: project.id, beads_id: "d-2", title: "Second"})

      assert {:ok, %TicketDependency{}} = Tickets.add_dependency(t2.id, t1.id, "blocks")
    end

    @tag :tmp_dir
    test "list_dependencies/1 returns what a ticket depends on", %{tmp_dir: tmp_dir} do
      project = create_project(tmp_dir)

      {:ok, t1} =
        Tickets.create_ticket(%{project_id: project.id, beads_id: "ld-1", title: "Dep 1"})

      {:ok, t2} =
        Tickets.create_ticket(%{project_id: project.id, beads_id: "ld-2", title: "Dep 2"})

      {:ok, main} =
        Tickets.create_ticket(%{project_id: project.id, beads_id: "ld-main", title: "Main"})

      {:ok, _} = Tickets.add_dependency(main.id, t1.id, "blocks")
      {:ok, _} = Tickets.add_dependency(main.id, t2.id, "blocks")

      deps = Tickets.list_dependencies(main.id)
      assert length(deps) == 2
    end

    @tag :tmp_dir
    test "list_dependents/1 returns what depends on a ticket", %{tmp_dir: tmp_dir} do
      project = create_project(tmp_dir)

      {:ok, blocker} =
        Tickets.create_ticket(%{project_id: project.id, beads_id: "ldt-1", title: "Blocker"})

      {:ok, dep1} =
        Tickets.create_ticket(%{project_id: project.id, beads_id: "ldt-2", title: "Dependent 1"})

      {:ok, dep2} =
        Tickets.create_ticket(%{project_id: project.id, beads_id: "ldt-3", title: "Dependent 2"})

      {:ok, _} = Tickets.add_dependency(dep1.id, blocker.id, "blocks")
      {:ok, _} = Tickets.add_dependency(dep2.id, blocker.id, "blocks")

      dependents = Tickets.list_dependents(blocker.id)
      assert length(dependents) == 2
    end

    @tag :tmp_dir
    test "remove_dependency/2 removes dependency", %{tmp_dir: tmp_dir} do
      project = create_project(tmp_dir)

      {:ok, t1} =
        Tickets.create_ticket(%{project_id: project.id, beads_id: "rd-1", title: "First"})

      {:ok, t2} =
        Tickets.create_ticket(%{project_id: project.id, beads_id: "rd-2", title: "Second"})

      {:ok, _} = Tickets.add_dependency(t2.id, t1.id, "blocks")
      assert length(Tickets.list_dependencies(t2.id)) == 1

      Tickets.remove_dependency(t2.id, t1.id)
      assert length(Tickets.list_dependencies(t2.id)) == 0
    end

    @tag :tmp_dir
    test "prevents self-referential dependency", %{tmp_dir: tmp_dir} do
      project = create_project(tmp_dir)

      {:ok, ticket} =
        Tickets.create_ticket(%{project_id: project.id, beads_id: "self-1", title: "Self"})

      assert {:error, changeset} = Tickets.add_dependency(ticket.id, ticket.id)
      assert %{dependency_id: ["cannot depend on itself"]} = errors_on(changeset)
    end
  end

  describe "Ticket.map_from_beads/1" do
    test "maps beads JSON to ticket attrs" do
      beads_data = %{
        "id" => "opencode-squads-123",
        "title" => "Implement feature",
        "description" => "A detailed description",
        "status" => "in_progress",
        "priority" => 1,
        "issue_type" => "feature",
        "assignee" => "GreenPanda",
        "created_at" => "2025-01-01T10:00:00+00:00",
        "updated_at" => "2025-01-02T15:30:00+00:00"
      }

      attrs = Ticket.map_from_beads(beads_data)

      assert attrs.beads_id == "opencode-squads-123"
      assert attrs.title == "Implement feature"
      assert attrs.description == "A detailed description"
      assert attrs.status == "in_progress"
      assert attrs.priority == 1
      assert attrs.issue_type == "feature"
      assert attrs.assignee_name == "GreenPanda"
      assert %DateTime{} = attrs.beads_created_at
      assert %DateTime{} = attrs.beads_updated_at
    end

    test "handles nil and missing fields" do
      attrs = Ticket.map_from_beads(%{"id" => "test", "title" => "Test"})

      assert attrs.beads_id == "test"
      assert attrs.title == "Test"
      assert attrs.status == "open"
      refute Map.has_key?(attrs, :description)
    end

    test "normalizes unknown status to open" do
      attrs = Ticket.map_from_beads(%{"id" => "t", "title" => "T", "status" => "unknown"})
      assert attrs.status == "open"
    end
  end

  describe "get_ticket_with_sessions/1" do
    @tag :tmp_dir
    test "returns ticket with sessions preloaded", %{tmp_dir: tmp_dir} do
      project = create_project(tmp_dir)
      squad = create_squad(project)
      agent = create_agent(squad)

      {:ok, ticket} =
        Tickets.create_ticket(%{
          project_id: project.id,
          beads_id: "tws-1",
          title: "With Sessions"
        })

      {:ok, _s1} = Sessions.create_session(%{agent_id: agent.id, ticket_id: ticket.id})
      {:ok, _s2} = Sessions.create_session(%{agent_id: agent.id, ticket_id: ticket.id})

      found = Tickets.get_ticket_with_sessions(ticket.id)
      assert found.id == ticket.id
      assert length(found.sessions) == 2
    end

    @tag :tmp_dir
    test "returns ticket with empty sessions list", %{tmp_dir: tmp_dir} do
      project = create_project(tmp_dir)

      {:ok, ticket} =
        Tickets.create_ticket(%{project_id: project.id, beads_id: "tws-2", title: "No Sessions"})

      found = Tickets.get_ticket_with_sessions(ticket.id)
      assert found.id == ticket.id
      assert found.sessions == []
    end

    test "returns nil for unknown ticket" do
      assert Tickets.get_ticket_with_sessions(Ecto.UUID.generate()) == nil
    end
  end

  describe "get_ticket_with_preloads/2" do
    @tag :tmp_dir
    test "returns ticket with default preloads", %{tmp_dir: tmp_dir} do
      project = create_project(tmp_dir)
      squad = create_squad(project)
      agent = create_agent(squad)

      {:ok, ticket} =
        Tickets.create_ticket(%{
          project_id: project.id,
          beads_id: "twp-1",
          title: "With Preloads",
          assignee_id: agent.id
        })

      {:ok, _child} =
        Tickets.create_ticket(%{
          project_id: project.id,
          beads_id: "twp-1.1",
          title: "Child",
          parent_id: ticket.id
        })

      found = Tickets.get_ticket_with_preloads(ticket.id)
      assert found.id == ticket.id
      assert length(found.children) == 1
      assert found.assignee.id == agent.id
      assert found.sessions == []
    end

    @tag :tmp_dir
    test "returns ticket with custom preloads", %{tmp_dir: tmp_dir} do
      project = create_project(tmp_dir)

      {:ok, ticket} =
        Tickets.create_ticket(%{project_id: project.id, beads_id: "twp-2", title: "Custom"})

      found = Tickets.get_ticket_with_preloads(ticket.id, [:project])
      assert found.project.id == project.id
    end
  end
end
