defmodule Squads.WorktreesHardeningTest do
  use Squads.DataCase, async: true

  alias Squads.Worktrees

  describe "ensure_worktree/3 hardening" do
    test "returns {:error, :not_found} if project does not exist" do
      assert {:error, :not_found} ==
               Worktrees.ensure_worktree(
                 Ecto.UUID.generate(),
                 Ecto.UUID.generate(),
                 Ecto.UUID.generate()
               )
    end
  end

  describe "generate_pr_summary/2 hardening" do
    test "returns {:error, :not_found} if project does not exist" do
      assert {:error, :not_found} ==
               Worktrees.generate_pr_summary(Ecto.UUID.generate(), "some-worktree")
    end
  end

  describe "list_worktrees/1 hardening" do
    test "returns {:error, :not_found} if project does not exist" do
      assert {:error, :not_found} == Worktrees.list_worktrees(Ecto.UUID.generate())
    end
  end

  describe "remove_worktree/2 hardening" do
    test "returns {:error, :not_found} if project does not exist" do
      assert {:error, :not_found} ==
               Worktrees.remove_worktree(Ecto.UUID.generate(), "some-worktree")
    end
  end

  describe "merge_and_cleanup/3 hardening" do
    test "returns {:error, :not_found} if project does not exist" do
      assert {:error, :not_found} ==
               Worktrees.merge_and_cleanup(Ecto.UUID.generate(), "some-worktree")
    end
  end
end
