defmodule SquadsWeb.API.WorktreeControllerTest do
  use SquadsWeb.ConnCase, async: true

  alias Squads.Projects
  alias Squads.Agents
  alias Squads.Squads, as: SquadsContext
  alias Squads.Tickets
  alias Squads.Worktrees

  setup %{conn: conn} do
    tmp_dir =
      System.tmp_dir!() |> Path.join("worktree_controller_test_#{:rand.uniform(1_000_000)}")

    File.mkdir_p!(tmp_dir)
    on_exit(fn -> File.rm_rf!(tmp_dir) end)

    # Initialize git repo in tmp dir
    System.cmd("git", ["init"], cd: tmp_dir, stderr_to_stdout: true)
    System.cmd("git", ["config", "user.email", "test@example.com"], cd: tmp_dir)
    System.cmd("git", ["config", "user.name", "Test"], cd: tmp_dir)
    File.write!(Path.join(tmp_dir, "README.md"), "# Test")
    System.cmd("git", ["add", "."], cd: tmp_dir)
    System.cmd("git", ["commit", "-m", "initial"], cd: tmp_dir)

    {:ok, project} = Projects.init(tmp_dir, "test-project")
    {:ok, squad} = SquadsContext.create_squad(%{project_id: project.id, name: "Test Squad"})

    {:ok, agent} =
      Agents.create_agent(%{squad_id: squad.id, name: "GreenPanda", slug: "green-panda"})

    {:ok, ticket} =
      Tickets.create_ticket(%{project_id: project.id, beads_id: "test-123", title: "Test Ticket"})

    {:ok,
     conn: put_req_header(conn, "accept", "application/json"),
     project: project,
     agent: agent,
     ticket: ticket}
  end

  describe "index" do
    test "lists all worktrees for a project", %{conn: conn, project: project} do
      conn = get(conn, ~p"/api/projects/#{project.id}/worktrees")
      assert json_response(conn, 200)["data"] == []
    end

    test "returns 404 for invalid project id", %{conn: conn} do
      conn = get(conn, ~p"/api/projects/invalid-id/worktrees")
      assert json_response(conn, 404)["errors"]["detail"] == "Not Found"
    end
  end

  describe "create" do
    test "creates a worktree for an agent working on a ticket", %{
      conn: conn,
      project: project,
      agent: agent,
      ticket: ticket
    } do
      conn =
        post(conn, ~p"/api/projects/#{project.id}/worktrees", %{
          "agent_id" => agent.id,
          "ticket_id" => ticket.id
        })

      assert response(conn, 201)
      assert json_response(conn, 201)["data"]["path"] =~ agent.slug
    end
  end

  describe "delete" do
    test "removes a worktree", %{
      conn: conn,
      project: project,
      agent: agent,
      ticket: ticket
    } do
      # Create first
      {:ok, _path} = Worktrees.ensure_worktree(project.id, agent.id, ticket.id)
      worktree_name = "#{agent.slug}-#{ticket.id}"

      conn = delete(conn, ~p"/api/projects/#{project.id}/worktrees/#{worktree_name}")
      assert response(conn, 204)
    end
  end
end
