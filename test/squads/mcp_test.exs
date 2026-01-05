defmodule Squads.MCPTest do
  use Squads.DataCase, async: false

  alias Squads.MCP
  alias Squads.Projects
  alias Squads.Squads

  defmodule DockerCLIStub do
    def available?, do: {:ok, true}
    def server_enable(_name), do: {:ok, "enabled"}
    def server_disable(_name), do: {:ok, "disabled"}
    def server_ls, do: {:ok, "NAME STATUS\nnotion running\nother stopped"}

    def tools_ls do
      {:ok, [%{"server" => "notion", "name" => "notion.search"}]}
    end
  end

  defmodule CatalogStub do
    def list(_opts), do: {:ok, [%{name: "notion"}]}
  end

  setup do
    # Clear any cached catalog entries from persistent_term
    :persistent_term.erase({MCP.Catalog, :catalog})

    Application.put_env(:squads, MCP,
      docker_cli: __MODULE__.DockerCLIStub,
      catalog: __MODULE__.CatalogStub
    )

    on_exit(fn -> Application.delete_env(:squads, MCP) end)
    :ok
  end

  describe "handle_request list_tools" do
    test "returns the list of tools for agent_mail" do
      assert {:ok, %{tools: tools}} =
               MCP.handle_request("agent_mail", %{"method" => "list_tools"})

      assert is_list(tools)
      assert Enum.any?(tools, &(&1.name == "send_message"))
      assert Enum.any?(tools, &(&1.name == "list_inbox"))
    end
  end

  describe "handle_request call_tool" do
    test "unknown method returns error" do
      assert {:error, %{code: -32601}} = MCP.handle_request("unknown", %{"method" => "call_tool"})
    end

    test "send_message tool calls Mail.send_message" do
      args = %{
        "project_id" => "proj-1",
        "subject" => "Hello",
        "body_md" => "World",
        "to" => ["agent-1"]
      }

      assert_raise Ecto.ConstraintError, fn ->
        MCP.handle_request("agent_mail", %{
          "method" => "call_tool",
          "params" => %{"name" => "send_message", "arguments" => args}
        })
      end
    end

    test "squads_status returns status summary" do
      assert {:ok, %{content: [%{type: "text", text: text}]}} =
               MCP.handle_request("agent_mail", %{
                 "method" => "call_tool",
                 "params" => %{
                   "name" => "squads_status",
                   "arguments" => %{"squad_id" => "squad-1"}
                 }
               })

      assert is_binary(text)
      assert {:ok, _} = Jason.decode(text)
    end
  end

  describe "mcp servers" do
    defp create_squad(tmp_dir) do
      {:ok, project} = Projects.init(tmp_dir, "test-project")
      {:ok, squad} = Squads.create_squad(%{name: "Alpha", project_id: project.id})
      squad
    end

    defp create_server(squad, attrs \\ %{}) do
      base = %{squad_id: squad.id, name: "notion", source: "registry", type: "container"}
      MCP.create_server(Map.merge(base, attrs))
    end

    @tag :tmp_dir
    test "create_server validates source and type", %{tmp_dir: tmp_dir} do
      squad = create_squad(tmp_dir)

      {:error, changeset} =
        MCP.create_server(%{squad_id: squad.id, name: "bad", source: "nope", type: "bad"})

      errors = errors_on(changeset)
      assert "is invalid" in errors.source
      assert "is invalid" in errors.type
    end

    @tag :tmp_dir
    test "list_servers returns servers for squad", %{tmp_dir: tmp_dir} do
      squad = create_squad(tmp_dir)
      {:ok, _} = create_server(squad, %{name: "alpha"})
      {:ok, _} = create_server(squad, %{name: "beta"})

      servers = MCP.list_servers(squad.id)
      assert Enum.map(servers, & &1.name) == ["alpha", "beta"]
    end

    @tag :tmp_dir
    test "enable_server updates enabled flag", %{tmp_dir: tmp_dir} do
      squad = create_squad(tmp_dir)
      {:ok, server} = create_server(squad, %{enabled: false})

      {:ok, updated} = MCP.enable_server(squad.id, server.name)
      assert updated.enabled
    end

    @tag :tmp_dir
    test "sync_status updates server status", %{tmp_dir: tmp_dir} do
      squad = create_squad(tmp_dir)
      {:ok, server} = create_server(squad, %{status: "unknown"})

      {:ok, _} = MCP.sync_status(squad.id)
      updated = MCP.get_server(server.id)
      assert updated.status == "running"
    end

    @tag :tmp_dir
    test "sync_tools stores tool metadata", %{tmp_dir: tmp_dir} do
      squad = create_squad(tmp_dir)
      {:ok, server} = create_server(squad)

      {:ok, _} = MCP.sync_tools(squad.id)
      updated = MCP.get_server(server.id)

      assert updated.tools == %{
               "items" => [%{"name" => "notion.search", "server" => "notion"}]
             }
    end
  end

  test "list_catalog proxies through catalog adapter" do
    assert {:ok, [%{name: "notion"}]} = MCP.list_catalog()
  end

  test "cli_status reports availability" do
    assert {:ok, true} = MCP.cli_status()
  end
end
