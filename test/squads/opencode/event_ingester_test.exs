defmodule Squads.OpenCode.EventIngesterTest do
  use Squads.DataCase
  alias Squads.OpenCode.EventIngester
  alias Squads.Projects

  setup do
    # Create a project fixture
    # We use a dummy path, existence doesn't matter for this test as long as we don't start the real OpenCode server
    {:ok, project} = Projects.create_project(%{name: "Test Project", path: "/tmp/test"})
    {:ok, project: project}
  end

  test "starts successfully with auto_connect: false", %{project: project} do
    # Just ensuring it starts
    assert {:ok, _pid} = EventIngester.start_link(project_id: project.id, auto_connect: false)
  end
end
