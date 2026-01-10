defmodule SquadsWeb.API.SquadConnectionControllerTest do
  use SquadsWeb.ConnCase

  alias Squads.Projects
  alias Squads.Squads

  @create_attrs %{
    status: "active",
    notes: "some notes",
    metadata: %{}
  }

  setup %{conn: conn} do
    {:ok, conn: put_req_header(conn, "accept", "application/json")}
  end

  describe "index" do
    test "lists all connections for a project", %{conn: conn} do
      project1 = project_fixture()
      project2 = project_fixture()

      squad1 = squad_fixture(project_id: project1.id)
      squad2 = squad_fixture(project_id: project2.id)

      {:ok, connection} =
        Squads.create_connection(%{
          from_squad_id: squad1.id,
          to_squad_id: squad2.id
        })

      conn = get(conn, ~p"/api/fleet/connections?project_id=#{project1.id}")

      assert [
               %{
                 "id" => id,
                 "from_squad_id" => from_squad_id,
                 "to_squad_id" => to_squad_id
               }
             ] = json_response(conn, 200)["data"]

      assert id == connection.id
      assert from_squad_id == squad1.id
      assert to_squad_id == squad2.id
    end
  end

  describe "create connection" do
    test "renders connection when data is valid", %{conn: conn} do
      project1 = project_fixture()
      project2 = project_fixture()

      squad1 = squad_fixture(project_id: project1.id)
      squad2 = squad_fixture(project_id: project2.id)

      attrs =
        @create_attrs
        |> Map.put(:from_squad_id, squad1.id)
        |> Map.put(:to_squad_id, squad2.id)

      conn = post(conn, ~p"/api/fleet/connections", squad_connection: attrs)
      assert %{"id" => id} = json_response(conn, 201)["data"]

      conn = get(conn, ~p"/api/fleet/connections?project_id=#{project1.id}")

      assert [
               %{
                 "id" => ^id,
                 "status" => "active",
                 "notes" => "some notes"
               }
             ] = json_response(conn, 200)["data"]
    end
  end

  describe "delete connection" do
    setup do
      project1 = project_fixture()
      project2 = project_fixture()

      squad1 = squad_fixture(project_id: project1.id)
      squad2 = squad_fixture(project_id: project2.id)

      {:ok, connection} =
        Squads.create_connection(%{
          from_squad_id: squad1.id,
          to_squad_id: squad2.id
        })

      %{connection: connection}
    end

    test "deletes chosen connection", %{conn: conn, connection: connection} do
      conn = delete(conn, ~p"/api/fleet/connections/#{connection.id}")
      assert response(conn, 204)

      assert Squads.get_connection(connection.id) == nil
    end
  end

  # Helper fixtures
  defp project_fixture(attrs \\ %{}) do
    unique_suffix = System.unique_integer([:positive])

    attrs =
      attrs
      |> Enum.into(%{
        name: "Project #{unique_suffix}",
        path: "/tmp/project_#{unique_suffix}",
        description: "Test project"
      })

    {:ok, project} = Projects.create_project(attrs)
    project
  end

  defp squad_fixture(attrs) do
    unique_suffix = System.unique_integer([:positive])

    attrs =
      attrs
      |> Enum.into(%{
        name: "Squad #{unique_suffix}",
        description: "Test squad"
      })

    if !attrs[:project_id] do
      raise "project_id is required for squad_fixture"
    end

    {:ok, squad} = Squads.create_squad(attrs)
    squad
  end
end
