defmodule SquadsWeb.API.AgentControllerTest do
  use SquadsWeb.ConnCase, async: true

  alias Squads.Projects
  alias Squads.Squads, as: SquadsContext
  alias Squads.Agents

  defp create_project_and_squad(context) do
    tmp_dir =
      context[:tmp_dir] ||
        System.tmp_dir!() |> Path.join("agent_test_#{:rand.uniform(1_000_000)}")

    File.mkdir_p!(tmp_dir)

    {:ok, project} = Projects.init(tmp_dir, "test-project")
    {:ok, squad} = SquadsContext.create_squad(%{project_id: project.id, name: "Test Squad"})

    %{project: project, squad: squad, tmp_dir: tmp_dir}
  end

  defp create_agent(squad, attrs \\ %{}) do
    attrs =
      Enum.into(attrs, %{
        squad_id: squad.id,
        name: "BluePanda",
        slug: "blue-panda",
        role: "backend_engineer",
        level: "senior"
      })

    Agents.create_agent(attrs)
  end

  describe "GET /api/agents/roles" do
    test "returns roles configuration", %{conn: conn} do
      conn = get(conn, ~p"/api/agents/roles")
      response = json_response(conn, 200)["data"]
      assert Map.has_key?(response, "roles")
      assert Map.has_key?(response, "levels")
      assert Map.has_key?(response, "defaults")
      assert Map.has_key?(response, "system_instructions")
    end
  end

  describe "GET /api/squads/:squad_id/agents" do
    @tag :tmp_dir
    test "lists agents for a squad", %{conn: conn} = context do
      %{squad: squad} = create_project_and_squad(context)
      {:ok, _agent} = create_agent(squad)

      conn = get(conn, ~p"/api/squads/#{squad.id}/agents")
      assert length(json_response(conn, 200)["data"]) == 1
    end

    test "returns 404 for non-existent squad", %{conn: conn} do
      conn = get(conn, ~p"/api/squads/#{Ecto.UUID.generate()}/agents")
      assert json_response(conn, 404)
    end
  end

  describe "GET /api/projects/:project_id/agents" do
    @tag :tmp_dir
    test "lists agents for a project", %{conn: conn} = context do
      %{project: project, squad: squad} = create_project_and_squad(context)
      {:ok, _agent} = create_agent(squad)

      conn = get(conn, ~p"/api/projects/#{project.id}/agents")
      assert length(json_response(conn, 200)["data"]) == 1
    end
  end

  describe "GET /api/agents/:id" do
    @tag :tmp_dir
    test "shows agent", %{conn: conn} = context do
      %{squad: squad} = create_project_and_squad(context)
      {:ok, agent} = create_agent(squad)

      conn = get(conn, ~p"/api/agents/#{agent.id}")
      assert json_response(conn, 200)["data"]["id"] == agent.id
    end

    test "returns 404 for non-existent agent", %{conn: conn} do
      conn = get(conn, ~p"/api/agents/#{Ecto.UUID.generate()}")
      assert json_response(conn, 404)
    end
  end

  describe "POST /api/squads/:squad_id/agents" do
    @tag :tmp_dir
    test "creates agent with auto-generated name", %{conn: conn} = context do
      %{squad: squad} = create_project_and_squad(context)

      conn = post(conn, ~p"/api/squads/#{squad.id}/agents", %{"model" => "gpt-4"})
      assert json_response(conn, 201)["data"]["model"] == "gpt-4"
    end

    @tag :tmp_dir
    test "creates agent with explicit name", %{conn: conn} = context do
      %{squad: squad} = create_project_and_squad(context)

      conn =
        post(conn, ~p"/api/squads/#{squad.id}/agents", %{
          "name" => "CustomAgent",
          "slug" => "custom-agent",
          "model" => "gpt-4"
        })

      assert json_response(conn, 201)["data"]["name"] == "CustomAgent"
    end
  end

  describe "PATCH /api/agents/:id" do
    @tag :tmp_dir
    test "updates agent", %{conn: conn} = context do
      %{squad: squad} = create_project_and_squad(context)
      {:ok, agent} = create_agent(squad)

      conn = patch(conn, ~p"/api/agents/#{agent.id}", %{"status" => "working"})
      assert json_response(conn, 200)["data"]["status"] == "working"
    end
  end

  describe "DELETE /api/agents/:id" do
    @tag :tmp_dir
    test "deletes agent", %{conn: conn} = context do
      %{squad: squad} = create_project_and_squad(context)
      {:ok, agent} = create_agent(squad)

      conn = delete(conn, ~p"/api/agents/#{agent.id}")
      assert response(conn, 204)
    end
  end

  describe "PATCH /api/agents/:id/status" do
    @tag :tmp_dir
    test "updates agent status via specific endpoint", %{conn: conn} = context do
      %{squad: squad} = create_project_and_squad(context)
      {:ok, agent} = create_agent(squad)

      # Note: The controller expects "agent_id" in params but the route uses ":id"
      # Looking at router.ex might be needed, but let's try with :id first
      conn = patch(conn, ~p"/api/agents/#{agent.id}/status", %{"status" => "working"})
      assert json_response(conn, 200)["data"]["status"] == "working"
    end
  end
end
