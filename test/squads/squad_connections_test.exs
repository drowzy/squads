defmodule Squads.SquadConnectionsTest do
  use Squads.DataCase

  alias Squads.Events
  alias Squads.Projects
  alias Squads.Squads.SquadConnection
  alias Squads.Squads

  describe "squad_connections" do
    @valid_attrs %{status: "active", notes: "Collaboration on API", metadata: %{}}
    @update_attrs %{status: "disabled", notes: "Collaboration paused"}
    @invalid_attrs %{status: nil}

    setup do
      {:ok, project1} =
        Projects.create_project(%{
          name: "Project A",
          path: "/tmp/project_a",
          description: "Test project A"
        })

      {:ok, project2} =
        Projects.create_project(%{
          name: "Project B",
          path: "/tmp/project_b",
          description: "Test project B"
        })

      {:ok, squad1} =
        Squads.create_squad(%{
          name: "Squad 1",
          project_id: project1.id,
          description: "Backend squad"
        })

      {:ok, squad2} =
        Squads.create_squad(%{
          name: "Squad 2",
          project_id: project2.id,
          description: "Frontend squad"
        })

      %{squad1: squad1, squad2: squad2, project1: project1, project2: project2}
    end

    test "create_connection/1 with valid data creates a connection", %{
      squad1: squad1,
      squad2: squad2
    } do
      attrs =
        @valid_attrs
        |> Map.put(:from_squad_id, squad1.id)
        |> Map.put(:to_squad_id, squad2.id)

      assert {:ok, %SquadConnection{} = connection} = Squads.create_connection(attrs)
      assert connection.status == "active"
      assert connection.notes == "Collaboration on API"
      assert connection.from_squad_id == squad1.id
      assert connection.to_squad_id == squad2.id
    end

    test "create_connection/1 emits events", %{
      squad1: squad1,
      squad2: squad2,
      project1: project1,
      project2: project2
    } do
      Events.subscribe(project1.id)
      Events.subscribe(project2.id)

      attrs =
        @valid_attrs
        |> Map.put(:from_squad_id, squad1.id)
        |> Map.put(:to_squad_id, squad2.id)

      {:ok, connection} = Squads.create_connection(attrs)

      assert_receive {:event, %{kind: "squad.connected", project_id: pid1, payload: payload1}}
      assert pid1 == project1.id
      assert payload1.connection_id == connection.id
      assert payload1.from_squad_id == squad1.id
      assert payload1.to_squad_id == squad2.id

      assert_receive {:event, %{kind: "squad.connected", project_id: pid2, payload: payload2}}
      assert pid2 == project2.id
      assert payload2.connection_id == connection.id
    end

    test "create_connection/1 prevents self-connection", %{squad1: squad1} do
      attrs =
        @valid_attrs
        |> Map.put(:from_squad_id, squad1.id)
        |> Map.put(:to_squad_id, squad1.id)

      assert {:error, changeset} = Squads.create_connection(attrs)
      assert "cannot connect to itself" in errors_on(changeset).from_squad_id
    end

    test "create_connection/1 enforces uniqueness", %{squad1: squad1, squad2: squad2} do
      attrs =
        @valid_attrs
        |> Map.put(:from_squad_id, squad1.id)
        |> Map.put(:to_squad_id, squad2.id)

      {:ok, _} = Squads.create_connection(attrs)
      assert {:error, changeset} = Squads.create_connection(attrs)
      assert "has already been taken" in errors_on(changeset).from_squad_id
    end

    test "list_connections_for_squad/1 returns all connections for a squad", %{
      squad1: squad1,
      squad2: squad2
    } do
      attrs =
        @valid_attrs
        |> Map.put(:from_squad_id, squad1.id)
        |> Map.put(:to_squad_id, squad2.id)

      {:ok, connection} = Squads.create_connection(attrs)

      connections = Squads.list_connections_for_squad(squad1.id)
      assert length(connections) == 1
      assert hd(connections).id == connection.id

      connections = Squads.list_connections_for_squad(squad2.id)
      assert length(connections) == 1
      assert hd(connections).id == connection.id
    end

    test "list_connections_for_project/1 returns all connections for a project", %{
      squad1: squad1,
      squad2: squad2,
      project1: project1
    } do
      attrs =
        @valid_attrs
        |> Map.put(:from_squad_id, squad1.id)
        |> Map.put(:to_squad_id, squad2.id)

      {:ok, connection} = Squads.create_connection(attrs)

      connections = Squads.list_connections_for_project(project1.id)
      assert length(connections) == 1
      assert hd(connections).id == connection.id
    end

    test "update_connection/2 updates the connection", %{squad1: squad1, squad2: squad2} do
      attrs =
        @valid_attrs
        |> Map.put(:from_squad_id, squad1.id)
        |> Map.put(:to_squad_id, squad2.id)

      {:ok, connection} = Squads.create_connection(attrs)

      assert {:ok, %SquadConnection{} = updated_connection} =
               Squads.update_connection(connection, @update_attrs)

      assert updated_connection.status == "disabled"
      assert updated_connection.notes == "Collaboration paused"
    end

    test "delete_connection/1 deletes the connection and emits events", %{
      squad1: squad1,
      squad2: squad2,
      project1: project1,
      project2: project2
    } do
      Events.subscribe(project1.id)
      Events.subscribe(project2.id)

      attrs =
        @valid_attrs
        |> Map.put(:from_squad_id, squad1.id)
        |> Map.put(:to_squad_id, squad2.id)

      {:ok, connection} = Squads.create_connection(attrs)

      # Clear creation events
      assert_receive {:event, _}
      assert_receive {:event, _}

      assert {:ok, %SquadConnection{}} = Squads.delete_connection(connection)

      # Check deletion events
      assert_receive {:event, %{kind: "squad.disconnected", project_id: pid1}}
      assert pid1 == project1.id

      assert_receive {:event, %{kind: "squad.disconnected", project_id: pid2}}
      assert pid2 == project2.id

      assert Squads.list_connections_for_squad(squad1.id) == []
    end
  end
end
