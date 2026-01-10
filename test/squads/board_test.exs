defmodule Squads.BoardTest do
  use Squads.DataCase, async: true

  alias Squads.Agents
  alias Squads.Board
  alias Squads.Board.Card
  alias Squads.Projects
  alias Squads.Repo
  alias Squads.Squads, as: SquadsContext

  setup do
    tmp_dir = System.tmp_dir!() |> Path.join("board_test_#{:rand.uniform(1_000_000)}")
    File.mkdir_p!(tmp_dir)
    on_exit(fn -> File.rm_rf!(tmp_dir) end)

    {:ok, project} = Projects.init(tmp_dir, "test-project")
    {:ok, squad} = SquadsContext.create_squad(%{project_id: project.id, name: "Test Squad"})

    {:ok, agent} =
      Agents.create_agent(%{squad_id: squad.id, name: "GreenPanda", slug: "green-panda"})

    %{project: project, squad: squad, agent: agent}
  end

  defp insert_card(attrs) do
    %Card{}
    |> Card.changeset(attrs)
    |> Repo.insert()
  end

  test "approved moves card to done when pr_url is set", %{project: project, squad: squad} do
    {:ok, card} =
      insert_card(%{
        project_id: project.id,
        squad_id: squad.id,
        lane: "review",
        body: "Ship it",
        pr_url: "https://github.com/owner/repo/pull/123"
      })

    assert {:ok, updated} = Board.submit_human_review(card.id, "approved", "LGTM")
    assert updated.lane == "done"
    assert updated.human_review_status == "approved"
  end

  test "approved requires pr_url", %{project: project, squad: squad} do
    {:ok, card} =
      insert_card(%{
        project_id: project.id,
        squad_id: squad.id,
        lane: "review",
        body: "Ship it"
      })

    assert {:error, :missing_pr_url} = Board.submit_human_review(card.id, "approved")
  end

  test "changes_requested moves card back to build", %{project: project, squad: squad} do
    {:ok, card} =
      insert_card(%{
        project_id: project.id,
        squad_id: squad.id,
        lane: "review",
        body: "Ship it",
        pr_url: "https://github.com/owner/repo/pull/123"
      })

    assert {:ok, updated} = Board.submit_human_review(card.id, "changes_requested", "Fix tests")
    assert updated.lane == "build"
    assert updated.human_review_status == "changes_requested"
  end

  test "move_card forbids moving directly to done", %{project: project, squad: squad} do
    {:ok, card} =
      insert_card(%{
        project_id: project.id,
        squad_id: squad.id,
        lane: "todo",
        body: "Do it"
      })

    assert {:error, :forbidden} = Board.move_card(card.id, "done")
  end
end
