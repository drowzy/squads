defmodule Squads.MCPArtifactsTest do
  use Squads.DataCase, async: false

  alias Squads.Artifacts
  alias Squads.MCP
  alias Squads.Projects
  alias Squads.Reviews

  @tag :tmp_dir
  test "list_tools exposes artifacts tools" do
    assert {:ok, %{tools: tools}} = MCP.handle_request("artifacts", %{"method" => "list_tools"})

    names = Enum.map(tools, & &1.name)
    assert "create_issue" in names
    assert "create_review" in names
    assert "submit_review" in names
  end

  @tag :tmp_dir
  test "create_issue creates an issue file", %{tmp_dir: tmp_dir} do
    {:ok, project} =
      Projects.init(tmp_dir, "test-project")

    assert {:ok, %{content: [%{type: "text", text: text}]}} =
             MCP.handle_request("artifacts", %{
               "method" => "call_tool",
               "params" => %{
                 "name" => "create_issue",
                 "arguments" => %{
                   "project_id" => project.id,
                   "title" => "Hello",
                   "body_md" => "Body"
                 }
               }
             })

    payload = Jason.decode!(text)
    assert String.starts_with?(payload["id"], "iss_")
    assert payload["title"] == "Hello"

    {:ok, issue} = Artifacts.get_issue(tmp_dir, payload["id"])
    assert issue.title == "Hello"
  end

  @tag :tmp_dir
  test "create_review + submit_review update review file", %{tmp_dir: tmp_dir} do
    {:ok, project} =
      Projects.init(tmp_dir, "test-project")

    assert {:ok, %{content: [%{type: "text", text: created_text}]}} =
             MCP.handle_request("artifacts", %{
               "method" => "call_tool",
               "params" => %{
                 "name" => "create_review",
                 "arguments" => %{
                   "project_id" => project.id,
                   "title" => "Review",
                   "summary" => "Summary",
                   "worktree_path" => tmp_dir,
                   "base_sha" => "abc",
                   "head_sha" => "def",
                   "files_changed" => [%{"path" => "README.md", "status" => "modified"}]
                 }
               }
             })

    created = Jason.decode!(created_text)
    review_id = created["id"]

    assert {:ok, %{content: [%{type: "text", text: submitted_text}]}} =
             MCP.handle_request("artifacts", %{
               "method" => "call_tool",
               "params" => %{
                 "name" => "submit_review",
                 "arguments" => %{
                   "project_id" => project.id,
                   "review_id" => review_id,
                   "status" => "approved",
                   "feedback" => "LGTM"
                 }
               }
             })

    submitted = Jason.decode!(submitted_text)
    assert submitted["id"] == review_id
    assert submitted["status"] == "approved"

    {:ok, stored} = Reviews.get_review(review_id)
    assert stored.status == "approved"
    assert Enum.any?(stored.comments, &(&1.body == "LGTM"))
  end
end
