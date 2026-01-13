defmodule SquadsWeb.API.FsIssueControllerTest do
  use SquadsWeb.ConnCase, async: true

  alias Squads.Projects

  describe "filesystem issues" do
    @tag :tmp_dir
    test "lists empty issues", %{conn: conn, tmp_dir: tmp_dir} do
      {:ok, project} =
        Projects.init(tmp_dir, "test-project")

      conn = get(conn, ~p"/api/projects/#{project.id}/fs/issues")
      assert json_response(conn, 200)["data"] == []
    end

    @tag :tmp_dir
    test "creates and fetches an issue", %{conn: conn, tmp_dir: tmp_dir} do
      {:ok, project} =
        Projects.init(tmp_dir, "test-project")

      conn =
        post(conn, ~p"/api/projects/#{project.id}/fs/issues", %{
          "title" => "Hello",
          "body_md" => "## Description\n\nWorld",
          "priority" => 2,
          "labels" => ["type:feature"]
        })

      response = json_response(conn, 201)["data"]
      assert String.starts_with?(response["id"], "iss_")
      assert response["title"] == "Hello"
      assert response["status"] == "open"
      assert String.starts_with?(response["path"], ".squads/issues/")

      issue_id = response["id"]

      conn = get(recycle(conn), ~p"/api/projects/#{project.id}/fs/issues/#{issue_id}")
      show = json_response(conn, 200)["data"]

      assert show["id"] == issue_id
      assert show["frontmatter"]["status"] == "open"
      assert String.contains?(show["body_md"], "# Hello")
    end

    @tag :tmp_dir
    test "updates issue status", %{conn: conn, tmp_dir: tmp_dir} do
      {:ok, project} =
        Projects.init(tmp_dir, "test-project")

      conn =
        post(conn, ~p"/api/projects/#{project.id}/fs/issues", %{
          "title" => "Hello",
          "body_md" => "Body"
        })

      issue_id = json_response(conn, 201)["data"]["id"]

      conn =
        patch(recycle(conn), ~p"/api/projects/#{project.id}/fs/issues/#{issue_id}", %{
          "status" => "done"
        })

      updated = json_response(conn, 200)["data"]
      assert updated["id"] == issue_id
      assert updated["status"] == "done"
    end

    test "returns 404 for invalid project id", %{conn: conn} do
      conn = get(conn, ~p"/api/projects/not-a-uuid/fs/issues")
      assert json_response(conn, 404)["errors"]["detail"] == "Not Found"
    end
  end
end
