defmodule SquadsWeb.API.ProjectControllerTest do
  use SquadsWeb.ConnCase, async: true

  alias Squads.Projects
  alias Squads.Squads

  describe "GET /api/projects" do
    @tag :tmp_dir
    test "returns empty list when no projects", %{conn: conn} do
      conn = get(conn, ~p"/api/projects")
      assert json_response(conn, 200)["data"] == []
    end

    @tag :tmp_dir
    test "returns list of projects", %{conn: conn, tmp_dir: tmp_dir} do
      {:ok, _project} = Projects.init(tmp_dir, "test-project")

      conn = get(conn, ~p"/api/projects")
      response = json_response(conn, 200)

      assert length(response["data"]) >= 1
      assert Enum.any?(response["data"], fn p -> p["name"] == "test-project" end)
    end
  end

  describe "GET /api/projects/:id" do
    @tag :tmp_dir
    test "returns project by id", %{conn: conn, tmp_dir: tmp_dir} do
      {:ok, project} = Projects.init(tmp_dir, "test-project")

      conn = get(conn, ~p"/api/projects/#{project.id}")
      response = json_response(conn, 200)

      assert response["data"]["id"] == project.id
      assert response["data"]["name"] == "test-project"
      assert response["data"]["path"] == tmp_dir
    end

    test "returns 404 for unknown id", %{conn: conn} do
      conn = get(conn, ~p"/api/projects/#{Ecto.UUID.generate()}")
      assert json_response(conn, 404)["errors"]["detail"] == "Not Found"
    end
  end

  describe "POST /api/projects" do
    @tag :tmp_dir
    test "creates a new project", %{conn: conn, tmp_dir: tmp_dir} do
      conn =
        post(conn, ~p"/api/projects", %{
          "path" => tmp_dir,
          "name" => "new-project"
        })

      response = json_response(conn, 201)
      assert response["data"]["name"] == "new-project"
      assert response["data"]["path"] == tmp_dir

      # Verify files were created
      assert File.exists?(Path.join(tmp_dir, ".squads/config.json"))
    end

    @tag :tmp_dir
    test "accepts config overrides", %{conn: conn, tmp_dir: tmp_dir} do
      conn =
        post(conn, ~p"/api/projects", %{
          "path" => tmp_dir,
          "name" => "new-project",
          "config" => %{"orchestration" => %{"max_parallel_agents" => 8}}
        })

      response = json_response(conn, 201)
      assert response["data"]["config"]["orchestration"]["max_parallel_agents"] == 8
    end

    @tag :tmp_dir
    test "returns error for already initialized project", %{conn: conn, tmp_dir: tmp_dir} do
      {:ok, _} = Projects.init(tmp_dir, "first")

      conn =
        post(conn, ~p"/api/projects", %{
          "path" => tmp_dir,
          "name" => "second"
        })

      response = json_response(conn, 422)
      # The unique_constraint on path returns this error
      assert response["errors"]["path"] != nil
    end

    test "returns error for invalid path", %{conn: conn} do
      conn =
        post(conn, ~p"/api/projects", %{
          "path" => "/nonexistent/path",
          "name" => "test"
        })

      response = json_response(conn, 422)
      assert response["errors"]["detail"] =~ "does not exist"
    end
  end

  describe "GET /api/projects/:project_id/squads" do
    @tag :tmp_dir
    test "returns empty list when no squads", %{conn: conn, tmp_dir: tmp_dir} do
      {:ok, project} = Projects.init(tmp_dir, "test")

      conn = get(conn, ~p"/api/projects/#{project.id}/squads")
      assert json_response(conn, 200)["data"] == []
    end

    @tag :tmp_dir
    test "returns list of squads for project", %{conn: conn, tmp_dir: tmp_dir} do
      {:ok, project} = Projects.init(tmp_dir, "test")
      {:ok, _squad} = Squads.create_squad(%{project_id: project.id, name: "Alpha Squad"})

      conn = get(conn, ~p"/api/projects/#{project.id}/squads")
      response = json_response(conn, 200)

      assert length(response["data"]) == 1
      assert hd(response["data"])["name"] == "Alpha Squad"
    end

    test "returns 404 for unknown project", %{conn: conn} do
      conn = get(conn, ~p"/api/projects/#{Ecto.UUID.generate()}/squads")
      assert json_response(conn, 404)
    end
  end
end
