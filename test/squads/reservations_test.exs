defmodule Squads.ReservationsTest do
  use Squads.DataCase, async: true

  alias Squads.{Projects, Squads, Agents, Reservations}

  setup do
    tmp_dir = System.tmp_dir!() |> Path.join("res_test_#{:rand.uniform(1_000_000)}")
    File.mkdir_p!(tmp_dir)
    on_exit(fn -> File.rm_rf!(tmp_dir) end)

    {:ok, project} = Projects.init(tmp_dir, "test-project")
    {:ok, squad} = Squads.create_squad(%{project_id: project.id, name: "Test Squad"})

    {:ok, agent1} =
      Agents.create_agent(%{name: "GreenPanda", slug: "green-panda", squad_id: squad.id})

    {:ok, agent2} =
      Agents.create_agent(%{name: "BlueLake", slug: "blue-lake", squad_id: squad.id})

    %{project: project, agent1: agent1, agent2: agent2}
  end

  test "reserve_paths/4 creates reservations", %{project: project, agent1: agent1} do
    assert {:ok, results} = Reservations.reserve_paths(project.id, agent1.id, ["lib/foo.ex"])
    assert length(results) == 1
    assert hd(results).path_pattern == "lib/foo.ex"
  end

  test "reserve_paths/4 detects exclusive conflicts", %{
    project: project,
    agent1: agent1,
    agent2: agent2
  } do
    {:ok, _} = Reservations.reserve_paths(project.id, agent1.id, ["lib/foo.ex"], exclusive: true)

    assert {:error, {:conflict, ["lib/foo.ex"]}} =
             Reservations.reserve_paths(project.id, agent2.id, ["lib/foo.ex"])
  end

  test "reserve_paths/4 detects shared/exclusive conflicts", %{
    project: project,
    agent1: agent1,
    agent2: agent2
  } do
    {:ok, _} = Reservations.reserve_paths(project.id, agent1.id, ["lib/foo.ex"], exclusive: false)

    assert {:error, {:conflict, ["lib/foo.ex"]}} =
             Reservations.reserve_paths(project.id, agent2.id, ["lib/foo.ex"], exclusive: true)
  end

  test "reserve_paths/4 allows multiple shared reservations", %{
    project: project,
    agent1: agent1,
    agent2: agent2
  } do
    {:ok, _} = Reservations.reserve_paths(project.id, agent1.id, ["lib/foo.ex"], exclusive: false)

    assert {:ok, _} =
             Reservations.reserve_paths(project.id, agent2.id, ["lib/foo.ex"], exclusive: false)
  end

  test "release_reservations/2 removes reservations", %{project: project, agent1: agent1} do
    {:ok, _} = Reservations.reserve_paths(project.id, agent1.id, ["lib/foo.ex"])
    assert length(Reservations.list_active_reservations(project.id)) == 1

    Reservations.release_reservations(agent1.id, ["lib/foo.ex"])
    assert length(Reservations.list_active_reservations(project.id)) == 0
  end
end
