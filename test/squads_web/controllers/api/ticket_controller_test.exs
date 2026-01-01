defmodule SquadsWeb.API.TicketControllerTest do
  use SquadsWeb.ConnCase, async: true

  alias Squads.Projects
  alias Squads.Tickets

  # Helper to create a project
  defp create_project(tmp_dir) do
    {:ok, project} = Projects.init(tmp_dir, "test-project")
    project
  end

  # Helper to create a ticket
  defp create_ticket(project, attrs \\ %{}) do
    base = %{
      project_id: project.id,
      beads_id: "test-#{System.unique_integer([:positive])}",
      title: "Test Ticket"
    }

    {:ok, ticket} = Tickets.create_ticket(Map.merge(base, attrs))
    ticket
  end

  describe "GET /api/projects/:project_id/tickets" do
    @tag :tmp_dir
    test "returns empty list when no tickets", %{conn: conn, tmp_dir: tmp_dir} do
      project = create_project(tmp_dir)

      conn = get(conn, ~p"/api/projects/#{project.id}/tickets")
      assert json_response(conn, 200)["data"] == []
    end

    @tag :tmp_dir
    test "returns list of tickets", %{conn: conn, tmp_dir: tmp_dir} do
      project = create_project(tmp_dir)
      _ticket1 = create_ticket(project, %{title: "First Ticket"})
      _ticket2 = create_ticket(project, %{title: "Second Ticket"})

      conn = get(conn, ~p"/api/projects/#{project.id}/tickets")
      response = json_response(conn, 200)

      assert length(response["data"]) == 2
    end

    @tag :tmp_dir
    test "filters by status", %{conn: conn, tmp_dir: tmp_dir} do
      project = create_project(tmp_dir)
      _open = create_ticket(project, %{status: "open", title: "Open"})
      _in_prog = create_ticket(project, %{status: "in_progress", title: "In Progress"})

      conn = get(conn, ~p"/api/projects/#{project.id}/tickets?status=open")
      response = json_response(conn, 200)

      assert length(response["data"]) == 1
      assert hd(response["data"])["title"] == "Open"
    end

    @tag :tmp_dir
    test "filters by issue_type", %{conn: conn, tmp_dir: tmp_dir} do
      project = create_project(tmp_dir)
      _bug = create_ticket(project, %{issue_type: "bug", title: "A Bug"})
      _feature = create_ticket(project, %{issue_type: "feature", title: "A Feature"})

      conn = get(conn, ~p"/api/projects/#{project.id}/tickets?issue_type=bug")
      response = json_response(conn, 200)

      assert length(response["data"]) == 1
      assert hd(response["data"])["title"] == "A Bug"
    end

    @tag :tmp_dir
    test "filters by priority", %{conn: conn, tmp_dir: tmp_dir} do
      project = create_project(tmp_dir)
      _high = create_ticket(project, %{priority: 1, title: "High Priority"})
      _low = create_ticket(project, %{priority: 3, title: "Low Priority"})

      conn = get(conn, ~p"/api/projects/#{project.id}/tickets?priority=1")
      response = json_response(conn, 200)

      assert length(response["data"]) == 1
      assert hd(response["data"])["title"] == "High Priority"
    end

    test "returns 404 for unknown project", %{conn: conn} do
      conn = get(conn, ~p"/api/projects/#{Ecto.UUID.generate()}/tickets")
      assert json_response(conn, 404)
    end
  end

  describe "GET /api/tickets/:id" do
    @tag :tmp_dir
    test "returns ticket by id", %{conn: conn, tmp_dir: tmp_dir} do
      project = create_project(tmp_dir)
      ticket = create_ticket(project, %{title: "My Ticket", beads_id: "test-123"})

      conn = get(conn, ~p"/api/tickets/#{ticket.id}")
      response = json_response(conn, 200)

      assert response["data"]["id"] == ticket.id
      assert response["data"]["title"] == "My Ticket"
      assert response["data"]["beads_id"] == "test-123"
    end

    test "returns 404 for unknown id", %{conn: conn} do
      conn = get(conn, ~p"/api/tickets/#{Ecto.UUID.generate()}")
      assert json_response(conn, 404)
    end
  end

  describe "GET /api/projects/:project_id/tickets/beads/:beads_id" do
    @tag :tmp_dir
    test "returns ticket by beads_id", %{conn: conn, tmp_dir: tmp_dir} do
      project = create_project(tmp_dir)
      _ticket = create_ticket(project, %{title: "Beads Ticket", beads_id: "bd-456"})

      conn = get(conn, ~p"/api/projects/#{project.id}/tickets/beads/bd-456")
      response = json_response(conn, 200)

      assert response["data"]["beads_id"] == "bd-456"
      assert response["data"]["title"] == "Beads Ticket"
    end

    @tag :tmp_dir
    test "returns 404 for unknown beads_id", %{conn: conn, tmp_dir: tmp_dir} do
      project = create_project(tmp_dir)

      conn = get(conn, ~p"/api/projects/#{project.id}/tickets/beads/nonexistent")
      assert json_response(conn, 404)
    end
  end

  describe "GET /api/projects/:project_id/tickets/ready" do
    @tag :tmp_dir
    test "returns ready tickets", %{conn: conn, tmp_dir: tmp_dir} do
      project = create_project(tmp_dir)
      ready = create_ticket(project, %{status: "open", title: "Ready"})
      blocker = create_ticket(project, %{status: "open", title: "Blocker"})
      blocked = create_ticket(project, %{status: "open", title: "Blocked"})

      # blocked depends on blocker
      {:ok, _} = Tickets.add_dependency(blocked.id, blocker.id, "blocks")

      conn = get(conn, ~p"/api/projects/#{project.id}/tickets/ready")
      response = json_response(conn, 200)

      ids = Enum.map(response["data"], & &1["id"])
      assert ready.id in ids
      assert blocker.id in ids
      refute blocked.id in ids
    end
  end

  describe "GET /api/projects/:project_id/tickets/in_progress" do
    @tag :tmp_dir
    test "returns in_progress tickets", %{conn: conn, tmp_dir: tmp_dir} do
      project = create_project(tmp_dir)
      _open = create_ticket(project, %{status: "open", title: "Open"})
      in_prog = create_ticket(project, %{status: "in_progress", title: "Working"})

      conn = get(conn, ~p"/api/projects/#{project.id}/tickets/in_progress")
      response = json_response(conn, 200)

      assert length(response["data"]) == 1
      assert hd(response["data"])["id"] == in_prog.id
    end
  end

  describe "GET /api/projects/:project_id/tickets/blocked" do
    @tag :tmp_dir
    test "returns blocked tickets", %{conn: conn, tmp_dir: tmp_dir} do
      project = create_project(tmp_dir)
      blocker = create_ticket(project, %{status: "open", title: "Blocker"})
      blocked = create_ticket(project, %{status: "open", title: "Blocked"})

      {:ok, _} = Tickets.add_dependency(blocked.id, blocker.id, "blocks")

      conn = get(conn, ~p"/api/projects/#{project.id}/tickets/blocked")
      response = json_response(conn, 200)

      assert length(response["data"]) == 1
      assert hd(response["data"])["id"] == blocked.id
    end
  end

  describe "GET /api/projects/:project_id/tickets/board" do
    @tag :tmp_dir
    test "returns board with tickets grouped by status", %{conn: conn, tmp_dir: tmp_dir} do
      project = create_project(tmp_dir)

      # Create tickets in different states
      ready = create_ticket(project, %{status: "open", title: "Ready"})
      in_prog = create_ticket(project, %{status: "in_progress", title: "In Progress"})
      closed = create_ticket(project, %{status: "closed", title: "Done"})

      # Create a blocked ticket
      blocker = create_ticket(project, %{status: "open", title: "Blocker"})
      blocked = create_ticket(project, %{status: "open", title: "Blocked"})
      {:ok, _} = Tickets.add_dependency(blocked.id, blocker.id, "blocks")

      conn = get(conn, ~p"/api/projects/#{project.id}/board")
      response = json_response(conn, 200)

      data = response["data"]

      # Check ready column (ready + blocker)
      ready_ids = Enum.map(data["ready"], & &1["id"])
      assert ready.id in ready_ids
      assert blocker.id in ready_ids
      refute blocked.id in ready_ids

      # Check in_progress column
      in_progress_ids = Enum.map(data["in_progress"], & &1["id"])
      assert in_prog.id in in_progress_ids

      # Check blocked column
      blocked_ids = Enum.map(data["blocked"], & &1["id"])
      assert blocked.id in blocked_ids

      # Check closed column
      closed_ids = Enum.map(data["closed"], & &1["id"])
      assert closed.id in closed_ids
    end
  end

  describe "GET /api/tickets/:id/children" do
    @tag :tmp_dir
    test "returns child tickets", %{conn: conn, tmp_dir: tmp_dir} do
      project = create_project(tmp_dir)
      parent = create_ticket(project, %{issue_type: "epic", title: "Epic"})
      child1 = create_ticket(project, %{parent_id: parent.id, title: "Subtask 1"})
      child2 = create_ticket(project, %{parent_id: parent.id, title: "Subtask 2"})

      conn = get(conn, ~p"/api/tickets/#{parent.id}/children")
      response = json_response(conn, 200)

      assert length(response["data"]) == 2
      ids = Enum.map(response["data"], & &1["id"])
      assert child1.id in ids
      assert child2.id in ids
    end

    test "returns 404 for unknown parent", %{conn: conn} do
      conn = get(conn, ~p"/api/tickets/#{Ecto.UUID.generate()}/children")
      assert json_response(conn, 404)
    end
  end

  describe "ticket data structure" do
    @tag :tmp_dir
    test "returns all expected fields", %{conn: conn, tmp_dir: tmp_dir} do
      project = create_project(tmp_dir)

      _ticket =
        create_ticket(project, %{
          beads_id: "test-full",
          title: "Full Ticket",
          description: "A description",
          status: "in_progress",
          priority: 1,
          issue_type: "feature"
        })

      conn = get(conn, ~p"/api/projects/#{project.id}/tickets")
      response = json_response(conn, 200)
      ticket_data = hd(response["data"])

      assert Map.has_key?(ticket_data, "id")
      assert Map.has_key?(ticket_data, "beads_id")
      assert Map.has_key?(ticket_data, "title")
      assert Map.has_key?(ticket_data, "description")
      assert Map.has_key?(ticket_data, "status")
      assert Map.has_key?(ticket_data, "priority")
      assert Map.has_key?(ticket_data, "issue_type")
      assert Map.has_key?(ticket_data, "assignee_id")
      assert Map.has_key?(ticket_data, "assignee_name")
      assert Map.has_key?(ticket_data, "parent_id")
      assert Map.has_key?(ticket_data, "project_id")
      assert Map.has_key?(ticket_data, "inserted_at")
      assert Map.has_key?(ticket_data, "updated_at")
    end
  end

  describe "POST /api/tickets/:id/claim" do
    @tag :tmp_dir
    test "returns 400 when missing agent_id", %{conn: conn, tmp_dir: tmp_dir} do
      project = create_project(tmp_dir)
      ticket = create_ticket(project, %{title: "Claim Test"})

      conn = post(conn, ~p"/api/tickets/#{ticket.id}/claim", %{"agent_name" => "GreenPanda"})
      response = json_response(conn, 400)

      assert response["error"] == "missing_params"
    end

    @tag :tmp_dir
    test "returns 400 when missing agent_name", %{conn: conn, tmp_dir: tmp_dir} do
      project = create_project(tmp_dir)
      ticket = create_ticket(project, %{title: "Claim Test"})

      conn =
        post(conn, ~p"/api/tickets/#{ticket.id}/claim", %{"agent_id" => Ecto.UUID.generate()})

      response = json_response(conn, 400)

      assert response["error"] == "missing_params"
    end

    test "returns 404 for unknown ticket", %{conn: conn} do
      conn =
        post(conn, ~p"/api/tickets/#{Ecto.UUID.generate()}/claim", %{
          "agent_id" => Ecto.UUID.generate(),
          "agent_name" => "GreenPanda"
        })

      assert json_response(conn, 404)
    end
  end

  describe "POST /api/tickets/:id/unclaim" do
    test "returns 404 for unknown ticket", %{conn: conn} do
      conn = post(conn, ~p"/api/tickets/#{Ecto.UUID.generate()}/unclaim")
      assert json_response(conn, 404)
    end
  end

  describe "PATCH /api/tickets/:id/status" do
    @tag :tmp_dir
    test "returns 400 when missing status", %{conn: conn, tmp_dir: tmp_dir} do
      project = create_project(tmp_dir)
      ticket = create_ticket(project, %{title: "Status Test"})

      conn = patch(conn, ~p"/api/tickets/#{ticket.id}/status", %{})
      response = json_response(conn, 400)

      assert response["error"] == "missing_status"
    end

    test "returns 404 for unknown ticket", %{conn: conn} do
      conn =
        patch(conn, ~p"/api/tickets/#{Ecto.UUID.generate()}/status", %{"status" => "in_progress"})

      assert json_response(conn, 404)
    end
  end

  describe "POST /api/tickets/:id/close" do
    test "returns 404 for unknown ticket", %{conn: conn} do
      conn = post(conn, ~p"/api/tickets/#{Ecto.UUID.generate()}/close")
      assert json_response(conn, 404)
    end
  end

  describe "POST /api/projects/:project_id/tickets (create)" do
    @tag :tmp_dir
    test "returns 400 when missing title", %{conn: conn, tmp_dir: tmp_dir} do
      project = create_project(tmp_dir)

      conn = post(conn, ~p"/api/projects/#{project.id}/tickets", %{})
      response = json_response(conn, 400)

      assert response["error"] == "missing_title"
    end

    test "returns 404 for unknown project", %{conn: conn} do
      conn = post(conn, ~p"/api/projects/#{Ecto.UUID.generate()}/tickets", %{"title" => "Test"})
      assert json_response(conn, 404)
    end
  end
end
