defmodule Squads.WorktreesTest do
  use Squads.DataCase, async: true

  alias Squads.Worktrees
  alias Squads.Projects
  alias Squads.Squads, as: SquadsContext
  alias Squads.Agents
  alias Squads.Tickets

  setup do
    tmp_dir = System.tmp_dir!() |> Path.join("worktree_test_#{:rand.uniform(1_000_000)}")
    File.mkdir_p!(tmp_dir)
    on_exit(fn -> File.rm_rf!(tmp_dir) end)

    {:ok, project} = Projects.init(tmp_dir, "test-project")

    System.cmd("git", ["init"], cd: tmp_dir, stderr_to_stdout: true)

    System.cmd("git", ["config", "user.email", "test@example.com"],
      cd: tmp_dir,
      stderr_to_stdout: true
    )

    System.cmd("git", ["config", "user.name", "Test"], cd: tmp_dir, stderr_to_stdout: true)
    File.write!(Path.join(tmp_dir, "README.md"), "# Test")
    System.cmd("git", ["add", "."], cd: tmp_dir, stderr_to_stdout: true)
    System.cmd("git", ["commit", "-m", "initial"], cd: tmp_dir, stderr_to_stdout: true)

    {:ok, squad} = SquadsContext.create_squad(%{project_id: project.id, name: "Test Squad"})

    {:ok, agent} =
      Agents.create_agent(%{squad_id: squad.id, name: "GreenPanda", slug: "green-panda"})

    {:ok, ticket} =
      Tickets.create_ticket(%{
        project_id: project.id,
        beads_id: "test-123",
        title: "Test Ticket"
      })

    %{
      project: project,
      agent: agent,
      ticket: ticket,
      tmp_dir: tmp_dir
    }
  end

  describe "worktree naming" do
    test "worktree name follows agent-slug-ticket-id format", %{
      agent: agent,
      ticket: ticket
    } do
      worktree_name = "#{agent.slug}-#{ticket.id}"
      assert worktree_name == "green-panda-#{ticket.id}"
    end

    test "branch name uses squads prefix", %{
      agent: agent,
      ticket: ticket
    } do
      worktree_name = "#{agent.slug}-#{ticket.id}"
      branch_name = "squads/#{worktree_name}"
      assert branch_name == "squads/green-panda-#{ticket.id}"
    end
  end

  describe "ensure_worktree/3" do
    test "creates worktree successfully", %{
      project: project,
      agent: agent,
      ticket: ticket
    } do
      {:ok, path} = Worktrees.ensure_worktree(project.id, agent.id, ticket.id)

      assert path =~ ".squads/worktrees"
      assert path =~ agent.slug
      assert path =~ ticket.id
      assert File.exists?(path)
    end

    test "returns existing worktree path if already exists", %{
      project: project,
      agent: agent,
      ticket: ticket
    } do
      {:ok, path1} = Worktrees.ensure_worktree(project.id, agent.id, ticket.id)
      {:ok, path2} = Worktrees.ensure_worktree(project.id, agent.id, ticket.id)

      assert path1 == path2
    end
  end

  describe "list_worktrees/1" do
    test "returns empty list when no worktrees exist", %{project: project} do
      worktrees = Worktrees.list_worktrees(project.id)
      assert worktrees == []
    end

    test "lists created worktrees", %{
      project: project,
      agent: agent,
      ticket: ticket
    } do
      {:ok, _path} = Worktrees.ensure_worktree(project.id, agent.id, ticket.id)

      worktrees = Worktrees.list_worktrees(project.id)
      assert length(worktrees) == 1
      assert hd(worktrees).name =~ agent.slug
    end
  end

  describe "remove_worktree/2" do
    test "removes worktree successfully", %{
      project: project,
      agent: agent,
      ticket: ticket
    } do
      {:ok, path} = Worktrees.ensure_worktree(project.id, agent.id, ticket.id)
      assert File.exists?(path)

      worktree_name = "#{agent.slug}-#{ticket.id}"
      {:ok, :removed} = Worktrees.remove_worktree(project.id, worktree_name)
      refute File.exists?(path)
    end
  end
end
