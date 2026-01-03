defmodule SquadsWeb.API.ProviderControllerTest do
  use SquadsWeb.ConnCase, async: true

  setup %{conn: conn} do
    project =
      Squads.Repo.insert!(%Squads.Projects.Project{
        name: "Test Project",
        path: "/tmp/test"
      })

    {:ok, conn: put_req_header(conn, "accept", "application/json"), project: project}
  end

  describe "index" do
    test "lists all providers for a project", %{conn: conn, project: project} do
      # Insert a provider manually
      {:ok, _provider} =
        Squads.Providers.create_provider(%{
          project_id: project.id,
          provider_id: "anthropic",
          name: "Anthropic",
          status: "connected",
          models: [%{id: "claude-3-5-sonnet-20241022", name: "Claude 3.5 Sonnet"}]
        })

      conn = get(conn, ~p"/api/projects/#{project.id}/providers")
      assert json_response(conn, 200)["data"] != []
      assert hd(json_response(conn, 200)["data"])["provider_id"] == "anthropic"
    end

    test "returns empty list for invalid project id", %{conn: conn} do
      conn = get(conn, ~p"/api/projects/invalid-uuid/providers")
      assert json_response(conn, 200)["data"] == []
    end
  end

  describe "show" do
    test "returns provider by id", %{conn: conn, project: project} do
      {:ok, provider} =
        Squads.Providers.create_provider(%{
          project_id: project.id,
          provider_id: "openai",
          name: "OpenAI",
          status: "connected"
        })

      conn = get(conn, ~p"/api/providers/#{provider.id}")
      assert json_response(conn, 200)["data"]["id"] == provider.id
    end

    test "returns 404 for non-existent provider", %{conn: conn} do
      provider_id = Ecto.UUID.generate()
      conn = get(conn, ~p"/api/providers/#{provider_id}")
      assert json_response(conn, 404)["errors"] != %{}
    end

    test "returns 404 for invalid id", %{conn: conn} do
      conn = get(conn, ~p"/api/providers/invalid-id")
      assert json_response(conn, 404)["errors"] != %{}
    end
  end

  describe "models" do
    test "lists all models for a project", %{conn: conn, project: project} do
      {:ok, _provider} =
        Squads.Providers.create_provider(%{
          project_id: project.id,
          provider_id: "anthropic",
          name: "Anthropic",
          status: "connected",
          models: [
            %{"id" => "claude-3-5-sonnet", "name" => "Claude 3.5 Sonnet"},
            %{"id" => "claude-3-opus", "name" => "Claude 3 Opus"}
          ]
        })

      conn = get(conn, ~p"/api/projects/#{project.id}/models")
      data = json_response(conn, 200)["data"]
      assert length(data) == 2
      assert Enum.any?(data, fn m -> m["model_id"] == "claude-3-5-sonnet" end)
    end
  end

  describe "sync" do
    test "returns 200 even if OpenCode server is not available (using mocked or fallback data)",
         %{conn: conn, project: project} do
      # It seems Providers.sync_from_opencode/2 has some fallback logic or 
      # the test environment provides some default providers.
      conn = post(conn, ~p"/api/projects/#{project.id}/providers/sync")
      assert response(conn, 200)
      assert json_response(conn, 200)["data"] != []
    end
  end
end
