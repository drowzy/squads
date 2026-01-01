defmodule Squads.Config.ProjectConfigTest do
  use ExUnit.Case, async: true

  alias Squads.Config.ProjectConfig

  describe "default_config/0" do
    test "returns a valid default config" do
      config = ProjectConfig.default_config()

      assert config["version"] == 1
      assert config["orchestration"]["max_parallel_agents"] == 4
      assert config["orchestration"]["auto_assign"] == true
      assert config["integrations"]["opencode"]["enabled"] == true
      assert config["worktrees"]["base_branch"] == "main"
    end
  end

  describe "new/2" do
    test "creates config with name" do
      config = ProjectConfig.new("my-project")
      assert config["name"] == "my-project"
      assert config["version"] == 1
    end

    test "allows overrides" do
      config = ProjectConfig.new("test", %{"orchestration" => %{"max_parallel_agents" => 8}})
      assert config["name"] == "test"
      assert config["orchestration"]["max_parallel_agents"] == 8
      # Preserves other defaults
      assert config["orchestration"]["auto_assign"] == true
    end
  end

  describe "validate/1" do
    test "accepts valid config" do
      config = ProjectConfig.default_config()
      assert :ok = ProjectConfig.validate(config)
    end

    test "accepts minimal config" do
      assert :ok = ProjectConfig.validate(%{})
    end

    test "rejects non-map" do
      assert {:error, "config must be a map"} = ProjectConfig.validate("invalid")
    end

    test "rejects invalid version" do
      assert {:error, "version must be a positive integer"} =
               ProjectConfig.validate(%{"version" => "1"})

      assert {:error, "version must be a positive integer"} =
               ProjectConfig.validate(%{"version" => 0})
    end

    test "rejects invalid max_parallel_agents" do
      config = %{"orchestration" => %{"max_parallel_agents" => "4"}}

      assert {:error, "orchestration.max_parallel_agents must be an integer"} =
               ProjectConfig.validate(config)

      config = %{"orchestration" => %{"max_parallel_agents" => 0}}

      assert {:error, "orchestration.max_parallel_agents must be at least 1"} =
               ProjectConfig.validate(config)
    end

    test "rejects invalid auto_assign" do
      config = %{"orchestration" => %{"auto_assign" => "true"}}

      assert {:error, "orchestration.auto_assign must be a boolean"} =
               ProjectConfig.validate(config)
    end

    test "rejects invalid integration enabled flag" do
      config = %{"integrations" => %{"opencode" => %{"enabled" => "yes"}}}

      assert {:error, "integrations.opencode.enabled must be a boolean"} =
               ProjectConfig.validate(config)
    end

    test "rejects invalid worktrees config" do
      config = %{"worktrees" => %{"enabled" => "true"}}

      assert {:error, "worktrees.enabled must be a boolean"} =
               ProjectConfig.validate(config)

      config = %{"worktrees" => %{"base_branch" => 123}}

      assert {:error, "worktrees.base_branch must be a string"} =
               ProjectConfig.validate(config)
    end
  end

  describe "merge_defaults/1" do
    test "merges partial config with defaults" do
      partial = %{"name" => "test", "orchestration" => %{"max_parallel_agents" => 8}}
      merged = ProjectConfig.merge_defaults(partial)

      assert merged["name"] == "test"
      assert merged["orchestration"]["max_parallel_agents"] == 8
      assert merged["orchestration"]["auto_assign"] == true
      assert merged["integrations"]["opencode"]["enabled"] == true
    end
  end

  describe "config_path/1" do
    test "returns correct path" do
      assert ProjectConfig.config_path("/home/user/project") ==
               "/home/user/project/.squads/config.json"
    end
  end

  describe "save/2 and load/1" do
    @tag :tmp_dir
    test "round-trips config through filesystem", %{tmp_dir: tmp_dir} do
      config = ProjectConfig.new("test-project", %{"description" => "A test project"})

      assert :ok = ProjectConfig.save(tmp_dir, config)
      assert {:ok, loaded} = ProjectConfig.load(tmp_dir)

      assert loaded["name"] == "test-project"
      assert loaded["description"] == "A test project"
      assert loaded["version"] == 1
    end

    @tag :tmp_dir
    test "creates .squads directory if missing", %{tmp_dir: tmp_dir} do
      config = ProjectConfig.new("test")

      assert :ok = ProjectConfig.save(tmp_dir, config)
      assert File.dir?(Path.join(tmp_dir, ".squads"))
    end

    test "returns error for missing file" do
      assert {:error, "config file not found:" <> _} = ProjectConfig.load("/nonexistent/path")
    end

    @tag :tmp_dir
    test "rejects saving invalid config", %{tmp_dir: tmp_dir} do
      invalid_config = %{"version" => "bad"}

      assert {:error, "version must be a positive integer"} =
               ProjectConfig.save(tmp_dir, invalid_config)
    end
  end
end
