defmodule SquadsWeb.API.EventControllerTest do
  use SquadsWeb.ConnCase, async: true

  alias Squads.Events
  alias Squads.Projects
  alias Squads.Sessions
  alias Squads.Squads, as: SquadsContext
  alias Squads.Agents

  setup %{conn: conn} do
    {:ok, conn: put_req_header(conn, "accept", "application/json")}
  end

  defp create_setup(context) do
    tmp_dir =
      context[:tmp_dir] ||
        System.tmp_dir!() |> Path.join("event_test_#{:rand.uniform(1_000_000)}")

    File.mkdir_p!(tmp_dir)

    {:ok, project} = Projects.init(tmp_dir, "test-project")
    {:ok, squad} = SquadsContext.create_squad(%{project_id: project.id, name: "Test Squad"})

    {:ok, agent} =
      Agents.create_agent(%{
        squad_id: squad.id,
        name: "BluePanda",
        slug: "blue-panda",
        role: "backend_engineer"
      })

    {:ok, session} = Sessions.create_session(%{agent_id: agent.id})

    %{project: project, agent: agent, session: session, tmp_dir: tmp_dir}
  end

  describe "GET /api/events" do
    @tag :tmp_dir
    test "lists events for project", %{conn: conn} = context do
      %{project: project} = create_setup(context)

      {:ok, _event} =
        Events.create_event(%{
          project_id: project.id,
          kind: "agent.created",
          payload: %{foo: "bar"}
        })

      conn = get(conn, ~p"/api/events", %{"project_id" => project.id})
      response = json_response(conn, 200)["data"]
      assert Enum.any?(response, &(&1["kind"] == "agent.created"))
    end

    @tag :tmp_dir
    test "lists events for session", %{conn: conn} = context do
      %{project: project, session: session} = create_setup(context)

      {:ok, _event} =
        Events.create_event(%{
          project_id: project.id,
          kind: "session.started",
          payload: %{},
          session_id: session.id
        })

      conn = get(conn, ~p"/api/events", %{"session_id" => session.id})
      response = json_response(conn, 200)["data"]
      assert Enum.any?(response, &(&1["kind"] == "session.started"))
    end

    @tag :tmp_dir
    test "lists events for agent", %{conn: conn} = context do
      %{project: project, agent: agent} = create_setup(context)

      {:ok, _event} =
        Events.create_event(%{
          project_id: project.id,
          kind: "agent.status_changed",
          payload: %{},
          agent_id: agent.id
        })

      conn = get(conn, ~p"/api/events", %{"agent_id" => agent.id})
      response = json_response(conn, 200)["data"]
      assert Enum.any?(response, &(&1["kind"] == "agent.status_changed"))
    end

    test "returns empty list if no filter", %{conn: conn} do
      conn = get(conn, ~p"/api/events")
      assert json_response(conn, 200)["data"] == []
    end

    test "returns empty list for invalid UUID", %{conn: conn} do
      conn = get(conn, ~p"/api/events", %{"project_id" => "not-a-uuid"})
      assert json_response(conn, 200)["data"] == []
    end
  end
end
