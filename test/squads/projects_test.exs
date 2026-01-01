defmodule Squads.ProjectsTest do
  use Squads.DataCase, async: true

  alias Squads.Projects
  alias Squads.Projects.Project

  describe "init/3" do
    @tag :tmp_dir
    test "initializes a new project", %{tmp_dir: tmp_dir} do
      assert {:ok, %Project{} = project} = Projects.init(tmp_dir, "test-project")

      assert project.path == tmp_dir
      assert project.name == "test-project"
      assert project.config["name"] == "test-project"
      assert project.config["version"] == 1

      # Verify files were created
      assert File.dir?(Path.join(tmp_dir, ".squads"))
      assert File.exists?(Path.join(tmp_dir, ".squads/config.json"))
    end

    @tag :tmp_dir
    test "accepts config overrides", %{tmp_dir: tmp_dir} do
      overrides = %{"orchestration" => %{"max_parallel_agents" => 8}}
      assert {:ok, project} = Projects.init(tmp_dir, "test", overrides)

      assert project.config["orchestration"]["max_parallel_agents"] == 8
    end

    @tag :tmp_dir
    test "fails for already initialized project", %{tmp_dir: tmp_dir} do
      assert {:ok, _} = Projects.init(tmp_dir, "test")
      assert {:error, "project already initialized at " <> _} = Projects.init(tmp_dir, "test2")
    end

    test "fails for non-existent path" do
      assert {:error, "path does not exist or is not a directory"} =
               Projects.init("/nonexistent/path", "test")
    end

    test "fails for relative path" do
      assert {:error, "path must be absolute"} = Projects.init("relative/path", "test")
    end
  end

  describe "initialized?/1" do
    @tag :tmp_dir
    test "returns false for uninitalized path", %{tmp_dir: tmp_dir} do
      refute Projects.initialized?(tmp_dir)
    end

    @tag :tmp_dir
    test "returns true after initialization", %{tmp_dir: tmp_dir} do
      {:ok, _} = Projects.init(tmp_dir, "test")
      assert Projects.initialized?(tmp_dir)
    end
  end

  describe "get_by_path/1" do
    @tag :tmp_dir
    test "returns project for path", %{tmp_dir: tmp_dir} do
      {:ok, project} = Projects.init(tmp_dir, "test")
      found = Projects.get_by_path(tmp_dir)

      assert found.id == project.id
      assert found.path == tmp_dir
    end

    test "returns nil for unknown path" do
      assert Projects.get_by_path("/unknown/path") == nil
    end
  end

  describe "list_projects/0" do
    @tag :tmp_dir
    test "returns all projects", %{tmp_dir: tmp_dir} do
      # Create a subdirectory for second project
      second_path = Path.join(tmp_dir, "second")
      File.mkdir_p!(second_path)

      {:ok, _} = Projects.init(tmp_dir, "first")
      {:ok, _} = Projects.init(second_path, "second")

      projects = Projects.list_projects()
      assert length(projects) >= 2
    end
  end

  describe "load_config/1" do
    @tag :tmp_dir
    test "loads config from initialized project", %{tmp_dir: tmp_dir} do
      {:ok, _} = Projects.init(tmp_dir, "test")
      {:ok, config} = Projects.load_config(tmp_dir)

      assert config["name"] == "test"
      assert config["version"] == 1
    end

    test "fails for uninitialized project" do
      assert {:error, "config file not found:" <> _} = Projects.load_config("/tmp/uninitialized")
    end
  end

  describe "sync_config/1" do
    @tag :tmp_dir
    test "updates project from config file changes", %{tmp_dir: tmp_dir} do
      {:ok, project} = Projects.init(tmp_dir, "original")

      # Manually update the config file
      config_path = Path.join([tmp_dir, ".squads", "config.json"])
      config = Jason.decode!(File.read!(config_path))
      updated_config = Map.put(config, "name", "updated")
      File.write!(config_path, Jason.encode!(updated_config, pretty: true))

      # Sync and verify
      {:ok, synced} = Projects.sync_config(project)
      assert synced.name == "updated"
    end
  end
end
