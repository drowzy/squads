defmodule SquadsWeb.API.FsReviewControllerTest do
  use SquadsWeb.ConnCase, async: true

  alias Squads.Projects

  describe "filesystem reviews" do
    @tag :tmp_dir
    test "creates and fetches a review with diff", %{conn: conn, tmp_dir: tmp_dir} do
      {:ok, project} =
        Projects.init(tmp_dir, "test-project")

      System.cmd("git", ["init"], cd: tmp_dir, stderr_to_stdout: true)

      System.cmd("git", ["config", "user.email", "test@example.com"],
        cd: tmp_dir,
        stderr_to_stdout: true
      )

      System.cmd("git", ["config", "user.name", "Test"], cd: tmp_dir, stderr_to_stdout: true)

      File.write!(Path.join(tmp_dir, "README.md"), "# Base\n")
      System.cmd("git", ["add", "."], cd: tmp_dir, stderr_to_stdout: true)
      System.cmd("git", ["commit", "-m", "base"], cd: tmp_dir, stderr_to_stdout: true)

      {base_sha, 0} =
        System.cmd("git", ["rev-parse", "HEAD"], cd: tmp_dir, stderr_to_stdout: true)

      base_sha = String.trim(base_sha)

      File.write!(Path.join(tmp_dir, "README.md"), "# Base\n\nChange\n")
      System.cmd("git", ["add", "."], cd: tmp_dir, stderr_to_stdout: true)
      System.cmd("git", ["commit", "-m", "change"], cd: tmp_dir, stderr_to_stdout: true)

      {head_sha, 0} =
        System.cmd("git", ["rev-parse", "HEAD"], cd: tmp_dir, stderr_to_stdout: true)

      head_sha = String.trim(head_sha)

      conn =
        post(conn, ~p"/api/projects/#{project.id}/fs/reviews", %{
          "title" => "Review",
          "summary" => "Summary",
          "highlights" => ["A"],
          "worktree_path" => tmp_dir,
          "base_sha" => base_sha,
          "head_sha" => head_sha,
          "files_changed" => [%{"path" => "README.md", "status" => "modified"}]
        })

      created = json_response(conn, 201)["data"]
      review_id = created["id"]

      conn = get(recycle(conn), ~p"/api/projects/#{project.id}/fs/reviews/#{review_id}")
      data = json_response(conn, 200)["data"]

      assert data["review"]["id"] == review_id
      assert is_binary(data["diff"])
      assert data["diff"] != ""
      assert String.contains?(data["diff"], "README.md")
      assert data["diff_error"] == nil
    end

    @tag :tmp_dir
    test "creates and fetches a review with worktree diff (uncommitted)", %{
      conn: conn,
      tmp_dir: tmp_dir
    } do
      {:ok, project} =
        Projects.init(tmp_dir, "test-project")

      System.cmd("git", ["init"], cd: tmp_dir, stderr_to_stdout: true)

      System.cmd("git", ["config", "user.email", "test@example.com"],
        cd: tmp_dir,
        stderr_to_stdout: true
      )

      System.cmd("git", ["config", "user.name", "Test"], cd: tmp_dir, stderr_to_stdout: true)

      File.write!(Path.join(tmp_dir, "README.md"), "# Base\n")
      System.cmd("git", ["add", "."], cd: tmp_dir, stderr_to_stdout: true)
      System.cmd("git", ["commit", "-m", "base"], cd: tmp_dir, stderr_to_stdout: true)

      # Uncommitted change (staged) should appear in diff.
      File.write!(Path.join(tmp_dir, "README.md"), "# Base\n\nChange\n")
      System.cmd("git", ["add", "README.md"], cd: tmp_dir, stderr_to_stdout: true)

      # Untracked file should also appear in diff.
      File.write!(Path.join(tmp_dir, "untracked.txt"), "Hello\n")

      conn =
        post(conn, ~p"/api/projects/#{project.id}/fs/reviews", %{
          "title" => "Worktree Review",
          "summary" => "Summary",
          "worktree_path" => tmp_dir
        })

      created = json_response(conn, 201)["data"]
      review_id = created["id"]

      conn = get(recycle(conn), ~p"/api/projects/#{project.id}/fs/reviews/#{review_id}")
      data = json_response(conn, 200)["data"]

      assert data["review"]["id"] == review_id
      assert is_binary(data["diff"])
      assert data["diff"] != ""
      assert String.contains?(data["diff"], "README.md")
      assert String.contains?(data["diff"], "untracked.txt")
      assert data["diff_error"] == nil
    end

    @tag :tmp_dir
    test "missing worktree returns empty diff and diff_error", %{conn: conn, tmp_dir: tmp_dir} do
      {:ok, project} =
        Projects.init(tmp_dir, "test-project")

      conn =
        post(conn, ~p"/api/projects/#{project.id}/fs/reviews", %{
          "title" => "Review",
          "worktree_path" => Path.join(tmp_dir, "does-not-exist"),
          "base_sha" => "abc",
          "head_sha" => "def"
        })

      review_id = json_response(conn, 201)["data"]["id"]

      conn = get(recycle(conn), ~p"/api/projects/#{project.id}/fs/reviews/#{review_id}")
      data = json_response(conn, 200)["data"]

      assert data["diff"] == ""
      assert is_binary(data["diff_error"])
    end

    @tag :tmp_dir
    test "submit updates status and persists feedback", %{conn: conn, tmp_dir: tmp_dir} do
      {:ok, project} =
        Projects.init(tmp_dir, "test-project")

      conn =
        post(conn, ~p"/api/projects/#{project.id}/fs/reviews", %{
          "title" => "Review",
          "summary" => "Summary"
        })

      review_id = json_response(conn, 201)["data"]["id"]

      conn =
        post(recycle(conn), ~p"/api/projects/#{project.id}/fs/reviews/#{review_id}/submit", %{
          "status" => "approved",
          "feedback" => "LGTM"
        })

      submitted = json_response(conn, 200)["data"]
      assert submitted["status"] == "approved"

      conn = get(recycle(conn), ~p"/api/projects/#{project.id}/fs/reviews/#{review_id}")
      show = json_response(conn, 200)["data"]

      comments = show["review"]["comments"]
      assert is_list(comments)
      assert Enum.any?(comments, &(&1["body"] == "LGTM"))
    end
  end
end
