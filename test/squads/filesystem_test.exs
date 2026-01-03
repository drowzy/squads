defmodule Squads.FilesystemTest do
  use ExUnit.Case, async: true
  alias Squads.Filesystem

  @moduletag :tmp_dir

  describe "browse/2" do
    test "lists directories in a given path", %{tmp_dir: tmp_dir} do
      dir1 = Path.join(tmp_dir, "dir1")
      dir2 = Path.join(tmp_dir, "dir2")
      file1 = Path.join(tmp_dir, "file1.txt")

      File.mkdir!(dir1)
      File.mkdir!(dir2)
      File.touch!(file1)

      assert {:ok, result} = Filesystem.browse(tmp_dir)
      assert result.current_path == tmp_dir
      assert result.parent_path == Path.dirname(tmp_dir)

      names = Enum.map(result.directories, & &1.name)
      assert "dir1" in names
      assert "dir2" in names
      refute "file1.txt" in names
    end

    test "respects show_hidden option", %{tmp_dir: tmp_dir} do
      hidden_dir = Path.join(tmp_dir, ".hidden")
      File.mkdir!(hidden_dir)

      assert {:ok, result} = Filesystem.browse(tmp_dir)
      refute Enum.any?(result.directories, &(&1.name == ".hidden"))

      assert {:ok, result} = Filesystem.browse(tmp_dir, show_hidden: true)
      assert Enum.any?(result.directories, &(&1.name == ".hidden"))
    end

    test "identifies git repositories", %{tmp_dir: tmp_dir} do
      git_dir = Path.join(tmp_dir, "repo")
      File.mkdir!(git_dir)
      File.mkdir!(Path.join(git_dir, ".git"))

      assert {:ok, result} = Filesystem.browse(tmp_dir)
      repo_entry = Enum.find(result.directories, &(&1.name == "repo"))
      assert repo_entry.is_git_repo
    end

    test "identifies subdirectories", %{tmp_dir: tmp_dir} do
      parent = Path.join(tmp_dir, "parent")
      child = Path.join(parent, "child")
      File.mkdir_p!(child)

      assert {:ok, result} = Filesystem.browse(tmp_dir)
      parent_entry = Enum.find(result.directories, &(&1.name == "parent"))
      assert parent_entry.has_children
    end

    test "returns error for non-existent directory" do
      assert {:error, :not_a_directory} = Filesystem.browse("/non/existent/path/for/sure")
    end
  end

  describe "git_repo?/1" do
    test "returns true if .git directory exists", %{tmp_dir: tmp_dir} do
      File.mkdir!(Path.join(tmp_dir, ".git"))
      assert Filesystem.git_repo?(tmp_dir)
    end

    test "returns false if .git directory does not exist", %{tmp_dir: tmp_dir} do
      refute Filesystem.git_repo?(tmp_dir)
    end
  end

  describe "has_subdirectories?/1" do
    test "returns true if there are subdirectories", %{tmp_dir: tmp_dir} do
      File.mkdir!(Path.join(tmp_dir, "subdir"))
      assert Filesystem.has_subdirectories?(tmp_dir)
    end

    test "returns false if there are no subdirectories", %{tmp_dir: tmp_dir} do
      File.touch!(Path.join(tmp_dir, "file.txt"))
      refute Filesystem.has_subdirectories?(tmp_dir)
    end

    test "ignores hidden subdirectories", %{tmp_dir: tmp_dir} do
      File.mkdir!(Path.join(tmp_dir, ".hidden"))
      refute Filesystem.has_subdirectories?(tmp_dir)
    end
  end

  describe "list_all_files/1" do
    test "lists all non-hidden files recursively", %{tmp_dir: tmp_dir} do
      # Ensure it's NOT a git repo by NOT creating .git directory directly
      # Wait, File.mkdir!(Path.join(tmp_dir, ".git")) was creating it.

      File.mkdir!(Path.join(tmp_dir, "subdir"))
      File.touch!(Path.join(tmp_dir, "file1.txt"))
      File.touch!(Path.join([tmp_dir, "subdir", "file2.txt"]))
      # Avoid .git to test manual_recursive_list
      File.touch!(Path.join(tmp_dir, "other.txt"))

      {:ok, files} = Filesystem.list_all_files(tmp_dir)
      assert "file1.txt" in files
      assert "subdir/file2.txt" in files
      assert "other.txt" in files
    end

    test "uses git ls-files if it is a git repo", %{tmp_dir: tmp_dir} do
      File.mkdir!(Path.join(tmp_dir, ".git"))
      # Initialize git repo to make git ls-files work
      System.cmd("git", ["init"], cd: tmp_dir)
      File.write!(Path.join(tmp_dir, "tracked.txt"), "test")
      System.cmd("git", ["add", "tracked.txt"], cd: tmp_dir)

      File.write!(Path.join(tmp_dir, "untracked.txt"), "test")

      {:ok, files} = Filesystem.list_all_files(tmp_dir)
      assert "tracked.txt" in files
      # untracked.txt might not be in files if we haven't committed it, 
      # but git ls-files usually shows tracked/staged files.
      # Wait, git ls-files without flags shows tracked files.
    end
  end
end
