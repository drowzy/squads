defmodule SquadsWeb.API.MCPControllerTest do
  use SquadsWeb.ConnCase, async: false

  alias Squads.MCP
  alias Squads.Projects
  alias Squads.Squads

  defmodule DockerCLIStub do
    def available?, do: {:ok, true}
    def server_enable(_name), do: {:ok, "enabled"}
    def server_disable(_name), do: {:ok, "disabled"}
  end

  defmodule CatalogStub do
    def list(_opts), do: {:ok, [%{name: "notion"}]}
  end

  setup %{conn: conn} do
    Application.put_env(:squads, MCP,
      docker_cli: __MODULE__.DockerCLIStub,
      catalog: __MODULE__.CatalogStub
    )

    on_exit(fn -> Application.delete_env(:squads, MCP) end)

    {:ok, conn: put_req_header(conn, "accept", "application/json")}
  end

  defp create_squad(tmp_dir) do
    {:ok, project} = Projects.init(tmp_dir, "test-project")
    {:ok, squad} = Squads.create_squad(%{name: "Alpha", project_id: project.id})
    squad
  end

  defp create_server(squad, attrs \\ %{}) do
    base = %{squad_id: squad.id, name: "notion", source: "registry", type: "container"}
    {:ok, server} = MCP.create_server(Map.merge(base, attrs))
    server
  end

  describe "index" do
    test "requires squad_id", %{conn: conn} do
      conn = get(conn, ~p"/api/mcp")
      assert json_response(conn, 400)["error"] == "missing_squad_id"
    end

    @tag :tmp_dir
    test "lists mcp servers for squad", %{conn: conn, tmp_dir: tmp_dir} do
      squad = create_squad(tmp_dir)
      _server = create_server(squad)

      conn = get(conn, ~p"/api/mcp?squad_id=#{squad.id}")
      response = json_response(conn, 200)

      assert length(response["data"]) == 1
      assert hd(response["data"])["name"] == "notion"
    end
  end

  describe "create" do
    test "requires squad_id", %{conn: conn} do
      conn = post(conn, ~p"/api/mcp", %{})
      assert json_response(conn, 400)["error"] == "missing_squad_id"
    end

    @tag :tmp_dir
    test "creates mcp server", %{conn: conn, tmp_dir: tmp_dir} do
      squad = create_squad(tmp_dir)

      params = %{name: "notion", source: "registry", type: "container"}
      conn = post(conn, ~p"/api/mcp?squad_id=#{squad.id}", params)

      response = json_response(conn, 201)
      assert response["data"]["name"] == "notion"
    end
  end

  describe "update" do
    @tag :tmp_dir
    test "updates mcp server", %{conn: conn, tmp_dir: tmp_dir} do
      squad = create_squad(tmp_dir)
      _server = create_server(squad, %{enabled: false})

      conn = patch(conn, ~p"/api/mcp/notion?squad_id=#{squad.id}", %{enabled: true})
      response = json_response(conn, 200)

      assert response["data"]["enabled"] == true
    end
  end

  describe "connect/disconnect" do
    @tag :tmp_dir
    test "connect enables the server", %{conn: conn, tmp_dir: tmp_dir} do
      squad = create_squad(tmp_dir)
      _server = create_server(squad, %{enabled: false})

      conn = post(conn, ~p"/api/mcp/notion/connect?squad_id=#{squad.id}")
      response = json_response(conn, 200)

      assert response["data"]["enabled"] == true
    end

    @tag :tmp_dir
    test "disconnect disables the server", %{conn: conn, tmp_dir: tmp_dir} do
      squad = create_squad(tmp_dir)
      _server = create_server(squad, %{enabled: true})

      conn = post(conn, ~p"/api/mcp/notion/disconnect?squad_id=#{squad.id}")
      response = json_response(conn, 200)

      assert response["data"]["enabled"] == false
    end
  end

  describe "catalog" do
    test "returns catalog entries", %{conn: conn} do
      conn = get(conn, ~p"/api/mcp/catalog")
      response = json_response(conn, 200)

      assert response["data"] == [%{"name" => "notion"}]
    end
  end

  describe "cli" do
    test "reports CLI availability", %{conn: conn} do
      conn = get(conn, ~p"/api/mcp/cli")
      response = json_response(conn, 200)

      assert response["available"] == true
    end
  end

  describe "auth" do
    test "starts auth flow", %{conn: conn} do
      conn = get(conn, ~p"/api/mcp/test/auth")
      assert json_response(conn, 200) == %{"status" => "ok"}
    end

    test "handles auth callback", %{conn: conn} do
      conn = post(conn, ~p"/api/mcp/test/auth/callback")
      assert json_response(conn, 200) == %{"status" => "ok"}
    end
  end

  describe "agent_mail rpc" do
    test "list_tools returns tools", %{conn: conn} do
      payload = %{
        jsonrpc: "2.0",
        id: 1,
        method: "list_tools"
      }

      conn = post(conn, ~p"/api/mcp/agent_mail/connect", payload)
      response = json_response(conn, 200)

      assert response["id"] == 1
      assert response["result"]["tools"] |> is_list()
      assert Enum.any?(response["result"]["tools"], &(&1["name"] == "send_message"))
    end
  end
end
