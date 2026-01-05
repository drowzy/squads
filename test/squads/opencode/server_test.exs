defmodule Squads.OpenCode.ServerTest do
  use Squads.DataCase
  alias Squads.OpenCode.{Server, ProjectServer, ServerRegistry, ProjectSupervisor}
  alias Squads.Projects.Project
  alias Squads.Repo

  setup do
    # Clear registry
    Registry.unregister_match(ServerRegistry, :_, :_)
    :ok
  end

  test "ensure_running returns error if project not found" do
    assert {:error, :project_not_found} = Server.ensure_running(Ecto.UUID.generate())
  end

  test "ensure_running returns url if already running" do
    project_id = Ecto.UUID.generate()
    url = "http://127.0.0.1:1234"

    # Manually register in registry to simulate running
    {:ok, _} = Registry.register(ServerRegistry, project_id, url)

    # Mock project in DB
    project = %Project{id: project_id, path: "/tmp/fake", name: "Fake Project"}
    Repo.insert!(project)

    assert {:ok, ^url} = Server.ensure_running(project_id)
  end
end
