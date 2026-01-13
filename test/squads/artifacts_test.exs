defmodule Squads.ArtifactsTest do
  use ExUnit.Case, async: true

  alias Squads.Artifacts
  alias Squads.Artifacts.{Issue, Review}

  @moduletag :tmp_dir

  describe "ensure_dirs/1" do
    test "creates .squads/issues and .squads/reviews", %{tmp_dir: tmp_dir} do
      assert :ok = Artifacts.ensure_dirs(tmp_dir)

      assert File.dir?(Path.join(tmp_dir, ".squads/issues"))
      assert File.dir?(Path.join(tmp_dir, ".squads/reviews"))
    end
  end

  describe "Path.safe_join/2" do
    test "rejects absolute paths", %{tmp_dir: tmp_dir} do
      assert {:error, :invalid_path} = Squads.Artifacts.Path.safe_join(tmp_dir, "/etc/passwd")
    end

    test "rejects path traversal", %{tmp_dir: tmp_dir} do
      assert {:error, :invalid_path} = Squads.Artifacts.Path.safe_join(tmp_dir, "../escape")
      assert {:error, :invalid_path} = Squads.Artifacts.Path.safe_join(tmp_dir, "a/../escape")
      assert {:error, :invalid_path} = Squads.Artifacts.Path.safe_join(tmp_dir, "a\\..\\escape")
    end
  end

  describe "issues" do
    test "create/get/update round-trip", %{tmp_dir: tmp_dir} do
      assert {:ok, %Issue{} = issue} =
               Artifacts.create_issue(tmp_dir, %{
                 title: "Test Issue",
                 body_md: "## Description\n\nHello",
                 priority: 2,
                 labels: ["type:feature"]
               })

      assert issue.id =~
               ~r/^iss_[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[0-9a-f]{4}-[0-9a-f]{12}$/i

      assert issue.status == "open"
      assert issue.title == "Test Issue"
      assert File.exists?(Path.join(tmp_dir, issue.path))

      assert {:ok, %Issue{} = loaded} = Artifacts.get_issue(tmp_dir, issue.id)
      assert loaded.id == issue.id
      assert loaded.title == "Test Issue"
      assert String.contains?(loaded.body_md, "# Test Issue")

      assert {:ok, %Issue{} = updated} =
               Artifacts.update_issue(tmp_dir, issue.id, %{
                 status: "done",
                 title: "Renamed"
               })

      assert updated.status == "done"
      assert updated.title == "Renamed"
      assert String.contains?(updated.body_md, "# Renamed")

      assert {:ok, issues} = Artifacts.list_issues(tmp_dir)
      assert Enum.any?(issues, &(&1.id == issue.id))
    end

    test "create rejects invalid status", %{tmp_dir: tmp_dir} do
      assert {:error, {:validation, changeset}} =
               Artifacts.create_issue(tmp_dir, %{
                 title: "Bad",
                 status: "wat"
               })

      assert %{status: ["is invalid"]} = Squads.DataCase.errors_on(changeset)
    end
  end

  describe "reviews" do
    test "create/get/update round-trip", %{tmp_dir: tmp_dir} do
      assert {:ok, %Review{} = review} =
               Artifacts.create_review(tmp_dir, %{
                 title: "Review",
                 summary: "Summary",
                 highlights: ["A"],
                 context: %{
                   "worktree_path" => tmp_dir,
                   "base_sha" => "abc",
                   "head_sha" => "def"
                 },
                 files_changed: [%{"path" => "README.md", "status" => "modified"}]
               })

      assert review.id =~
               ~r/^rev_[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[0-9a-f]{4}-[0-9a-f]{12}$/i

      assert review.status == "pending"
      assert File.exists?(Path.join(tmp_dir, review.path))

      assert {:ok, %Review{} = loaded} = Artifacts.get_review(tmp_dir, review.id)
      assert loaded.id == review.id
      assert loaded.title == "Review"

      assert {:ok, %Review{} = submitted} =
               Artifacts.update_review(tmp_dir, review.id, %{
                 status: "approved",
                 comments: [%{"id" => "cmt_1", "body" => "LGTM"}]
               })

      assert submitted.status == "approved"
      assert length(submitted.comments) == 1

      assert {:ok, reviews} = Artifacts.list_reviews(tmp_dir)
      assert Enum.any?(reviews, &(&1.id == review.id))
    end

    test "create rejects missing title", %{tmp_dir: tmp_dir} do
      assert {:error, :invalid_title} = Artifacts.create_review(tmp_dir, %{})
    end
  end
end
