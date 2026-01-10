defmodule Squads.OpenCode.ConfigTest do
  use ExUnit.Case, async: true

  alias Squads.OpenCode.Config

  @moduletag :tmp_dir

  # ============================================================================
  # Setup
  # ============================================================================

  setup %{tmp_dir: tmp_dir} do
    # Create a fake project directory structure
    project_dir = Path.join(tmp_dir, "my_project")
    File.mkdir_p!(project_dir)

    # Create a .git directory to mark it as a git root
    File.mkdir_p!(Path.join(project_dir, ".git"))

    %{project_dir: project_dir, tmp_dir: tmp_dir}
  end

  # ============================================================================
  # Basic Loading
  # ============================================================================

  describe "load/2" do
    test "returns empty config when no config files exist", %{project_dir: project_dir} do
      assert {:ok, config} = Config.load(project_dir, include_env: false, include_global: false)
      assert config == %{}
    end

    test "loads project config file", %{project_dir: project_dir} do
      config_content = ~s({"model": "anthropic/claude-sonnet-4-5"})
      File.write!(Path.join(project_dir, "opencode.json"), config_content)

      assert {:ok, config} = Config.load(project_dir, include_env: false)
      assert config["model"] == "anthropic/claude-sonnet-4-5"
    end

    test "loads .jsonc config file", %{project_dir: project_dir} do
      config_content = ~s({"model": "openai/gpt-4o"})
      File.write!(Path.join(project_dir, "opencode.jsonc"), config_content)

      assert {:ok, config} = Config.load(project_dir, include_env: false)
      assert config["model"] == "openai/gpt-4o"
    end

    test "prefers .json over .jsonc when both exist", %{project_dir: project_dir} do
      File.write!(Path.join(project_dir, "opencode.json"), ~s({"model": "from-json"}))
      File.write!(Path.join(project_dir, "opencode.jsonc"), ~s({"model": "from-jsonc"}))

      assert {:ok, config} = Config.load(project_dir, include_env: false)
      assert config["model"] == "from-json"
    end

    test "loads custom config from option", %{project_dir: project_dir, tmp_dir: tmp_dir} do
      custom_path = Path.join(tmp_dir, "custom.json")
      File.write!(custom_path, ~s({"model": "custom-model"}))

      assert {:ok, config} =
               Config.load(project_dir, include_env: false, custom_config: custom_path)

      assert config["model"] == "custom-model"
    end

    test "handles non-existent custom config gracefully", %{
      project_dir: project_dir,
      tmp_dir: tmp_dir
    } do
      custom_path = Path.join(tmp_dir, "does_not_exist.json")

      assert {:ok, config} =
               Config.load(project_dir,
                 include_env: false,
                 include_global: false,
                 custom_config: custom_path
               )

      assert config == %{}
    end
  end

  # ============================================================================
  # JSONC Comment Stripping
  # ============================================================================

  describe "JSONC comment stripping" do
    test "strips single-line comments", %{project_dir: project_dir} do
      config_content = """
      {
        // This is a comment
        "model": "test-model", // inline comment
        "theme": "dark"
      }
      """

      File.write!(Path.join(project_dir, "opencode.json"), config_content)

      assert {:ok, config} = Config.load(project_dir, include_env: false)
      assert config["model"] == "test-model"
      assert config["theme"] == "dark"
    end

    test "strips multi-line comments", %{project_dir: project_dir} do
      config_content = """
      {
        /* This is a
           multi-line comment */
        "model": "test-model",
        "theme": "dark" /* another comment */
      }
      """

      File.write!(Path.join(project_dir, "opencode.json"), config_content)

      assert {:ok, config} = Config.load(project_dir, include_env: false)
      assert config["model"] == "test-model"
      assert config["theme"] == "dark"
    end

    test "handles mixed comment styles", %{project_dir: project_dir} do
      config_content = """
      {
        // Single line
        /* Multi
           line */
        "model": "test", // inline
        "provider": {
          /* nested comment */
          "anthropic": {
            "api_key": "sk-test" // api key
          }
        }
      }
      """

      File.write!(Path.join(project_dir, "opencode.json"), config_content)

      assert {:ok, config} = Config.load(project_dir, include_env: false)
      assert config["model"] == "test"
      assert get_in(config, ["provider", "anthropic", "api_key"]) == "sk-test"
    end
  end

  # ============================================================================
  # Variable Expansion
  # ============================================================================

  describe "environment variable expansion" do
    test "expands {env:VAR} syntax", %{project_dir: project_dir} do
      System.put_env("TEST_OPENCODE_MODEL", "expanded-model")

      on_exit(fn -> System.delete_env("TEST_OPENCODE_MODEL") end)

      config_content = ~s({"model": "{env:TEST_OPENCODE_MODEL}"})
      File.write!(Path.join(project_dir, "opencode.json"), config_content)

      assert {:ok, config} = Config.load(project_dir, include_env: false)
      assert config["model"] == "expanded-model"
    end

    test "returns empty string for undefined env vars", %{project_dir: project_dir} do
      config_content = ~s({"model": "prefix-{env:UNDEFINED_VAR_12345}-suffix"})
      File.write!(Path.join(project_dir, "opencode.json"), config_content)

      assert {:ok, config} = Config.load(project_dir, include_env: false)
      assert config["model"] == "prefix--suffix"
    end

    test "expands multiple env vars in same string", %{project_dir: project_dir} do
      System.put_env("TEST_PROVIDER", "anthropic")
      System.put_env("TEST_MODEL_NAME", "claude")

      on_exit(fn ->
        System.delete_env("TEST_PROVIDER")
        System.delete_env("TEST_MODEL_NAME")
      end)

      config_content = ~s({"model": "{env:TEST_PROVIDER}/{env:TEST_MODEL_NAME}"})
      File.write!(Path.join(project_dir, "opencode.json"), config_content)

      assert {:ok, config} = Config.load(project_dir, include_env: false)
      assert config["model"] == "anthropic/claude"
    end

    test "expands env vars in nested structures", %{project_dir: project_dir} do
      System.put_env("TEST_API_KEY", "sk-secret-key")

      on_exit(fn -> System.delete_env("TEST_API_KEY") end)

      config_content = """
      {
        "provider": {
          "anthropic": {
            "api_key": "{env:TEST_API_KEY}"
          }
        }
      }
      """

      File.write!(Path.join(project_dir, "opencode.json"), config_content)

      assert {:ok, config} = Config.load(project_dir, include_env: false)
      assert get_in(config, ["provider", "anthropic", "api_key"]) == "sk-secret-key"
    end
  end

  describe "file reference expansion" do
    test "expands {file:path} with relative path", %{project_dir: project_dir} do
      # Create a secret file
      File.write!(Path.join(project_dir, "secret.txt"), "my-secret-key\n")

      config_content = ~s({"provider": {"anthropic": {"api_key": "{file:secret.txt}"}}})
      File.write!(Path.join(project_dir, "opencode.json"), config_content)

      assert {:ok, config} = Config.load(project_dir, include_env: false)
      assert get_in(config, ["provider", "anthropic", "api_key"]) == "my-secret-key"
    end

    test "expands {file:path} with absolute path", %{project_dir: project_dir, tmp_dir: tmp_dir} do
      secret_path = Path.join(tmp_dir, "absolute_secret.txt")
      File.write!(secret_path, "absolute-secret\n")

      config_content = ~s({"api_key": "{file:#{secret_path}}"})
      File.write!(Path.join(project_dir, "opencode.json"), config_content)

      assert {:ok, config} = Config.load(project_dir, include_env: false)
      assert config["api_key"] == "absolute-secret"
    end

    test "returns empty string for non-existent file", %{project_dir: project_dir} do
      config_content = ~s({"api_key": "{file:does_not_exist.txt}"})
      File.write!(Path.join(project_dir, "opencode.json"), config_content)

      assert {:ok, config} = Config.load(project_dir, include_env: false)
      assert config["api_key"] == ""
    end

    test "trims whitespace from file contents", %{project_dir: project_dir} do
      File.write!(Path.join(project_dir, "key.txt"), "  key-with-spaces  \n\n")

      config_content = ~s({"api_key": "{file:key.txt}"})
      File.write!(Path.join(project_dir, "opencode.json"), config_content)

      assert {:ok, config} = Config.load(project_dir, include_env: false)
      assert config["api_key"] == "key-with-spaces"
    end
  end

  # ============================================================================
  # Config Merging
  # ============================================================================

  describe "config merging" do
    test "custom config overrides project config", %{project_dir: project_dir, tmp_dir: tmp_dir} do
      File.write!(
        Path.join(project_dir, "opencode.json"),
        ~s({"model": "project-model", "theme": "light"})
      )

      custom_path = Path.join(tmp_dir, "custom.json")
      File.write!(custom_path, ~s({"model": "custom-model"}))

      assert {:ok, config} =
               Config.load(project_dir, include_env: false, custom_config: custom_path)

      assert config["model"] == "custom-model"
      assert config["theme"] == "light"
    end

    test "deep merges nested structures", %{project_dir: project_dir, tmp_dir: tmp_dir} do
      project_config = """
      {
        "provider": {
          "anthropic": {"api_key": "key1", "enabled": true},
          "openai": {"api_key": "key2"}
        }
      }
      """

      custom_config = """
      {
        "provider": {
          "anthropic": {"api_key": "override-key"},
          "google": {"api_key": "key3"}
        }
      }
      """

      File.write!(Path.join(project_dir, "opencode.json"), project_config)

      custom_path = Path.join(tmp_dir, "custom.json")
      File.write!(custom_path, custom_config)

      assert {:ok, config} =
               Config.load(project_dir, include_env: false, custom_config: custom_path)

      # Anthropic api_key is overridden, enabled is preserved
      assert get_in(config, ["provider", "anthropic", "api_key"]) == "override-key"
      assert get_in(config, ["provider", "anthropic", "enabled"]) == true

      # OpenAI is preserved
      assert get_in(config, ["provider", "openai", "api_key"]) == "key2"

      # Google is added
      assert get_in(config, ["provider", "google", "api_key"]) == "key3"
    end

    test "arrays are replaced, not merged", %{project_dir: project_dir, tmp_dir: tmp_dir} do
      File.write!(Path.join(project_dir, "opencode.json"), ~s({"disabled_providers": ["a", "b"]}))

      custom_path = Path.join(tmp_dir, "custom.json")
      File.write!(custom_path, ~s({"disabled_providers": ["c"]}))

      assert {:ok, config} =
               Config.load(project_dir, include_env: false, custom_config: custom_path)

      assert config["disabled_providers"] == ["c"]
    end
  end

  # ============================================================================
  # Environment Variable Overrides
  # ============================================================================

  describe "environment variable overrides" do
    test "OPENCODE_MODEL overrides model", %{project_dir: project_dir} do
      System.put_env("OPENCODE_MODEL", "env-override-model")

      on_exit(fn -> System.delete_env("OPENCODE_MODEL") end)

      File.write!(Path.join(project_dir, "opencode.json"), ~s({"model": "config-model"}))

      assert {:ok, config} = Config.load(project_dir, include_env: true)
      assert config["model"] == "env-override-model"
    end

    test "ANTHROPIC_API_KEY sets provider api_key", %{project_dir: project_dir} do
      System.put_env("ANTHROPIC_API_KEY", "sk-from-env")

      on_exit(fn -> System.delete_env("ANTHROPIC_API_KEY") end)

      assert {:ok, config} = Config.load(project_dir, include_env: true)
      assert get_in(config, ["provider", "anthropic", "api_key"]) == "sk-from-env"
    end

    test "multiple API key env vars are applied", %{project_dir: project_dir} do
      System.put_env("ANTHROPIC_API_KEY", "anthropic-key")
      System.put_env("OPENAI_API_KEY", "openai-key")
      System.put_env("GOOGLE_GENERATIVE_AI_API_KEY", "google-key")

      on_exit(fn ->
        System.delete_env("ANTHROPIC_API_KEY")
        System.delete_env("OPENAI_API_KEY")
        System.delete_env("GOOGLE_GENERATIVE_AI_API_KEY")
      end)

      assert {:ok, config} = Config.load(project_dir, include_env: true)
      assert get_in(config, ["provider", "anthropic", "api_key"]) == "anthropic-key"
      assert get_in(config, ["provider", "openai", "api_key"]) == "openai-key"
      assert get_in(config, ["provider", "google", "api_key"]) == "google-key"
    end

    test "parses boolean values from env", %{project_dir: project_dir} do
      System.put_env("OPENCODE_AUTOUPDATE", "true")

      on_exit(fn -> System.delete_env("OPENCODE_AUTOUPDATE") end)

      assert {:ok, config} = Config.load(project_dir, include_env: true)
      assert config["autoupdate"] == true
    end

    test "parses false boolean from env", %{project_dir: project_dir} do
      System.put_env("OPENCODE_AUTOUPDATE", "false")

      on_exit(fn -> System.delete_env("OPENCODE_AUTOUPDATE") end)

      assert {:ok, config} = Config.load(project_dir, include_env: true)
      assert config["autoupdate"] == false
    end

    test "empty env var is not applied", %{project_dir: project_dir} do
      System.put_env("OPENCODE_MODEL", "")

      on_exit(fn -> System.delete_env("OPENCODE_MODEL") end)

      File.write!(Path.join(project_dir, "opencode.json"), ~s({"model": "config-model"}))

      assert {:ok, config} = Config.load(project_dir, include_env: true)
      assert config["model"] == "config-model"
    end
  end

  # ============================================================================
  # Accessor Functions
  # ============================================================================

  describe "get_model/1" do
    test "returns model from config" do
      config = %{"model" => "anthropic/claude-sonnet-4-5"}
      assert Config.get_model(config) == "anthropic/claude-sonnet-4-5"
    end

    test "returns nil when model not set" do
      assert Config.get_model(%{}) == nil
    end
  end

  describe "get_small_model/1" do
    test "returns small_model from config" do
      config = %{"small_model" => "anthropic/claude-haiku"}
      assert Config.get_small_model(config) == "anthropic/claude-haiku"
    end
  end

  describe "get_provider/2" do
    test "returns provider config" do
      config = %{"provider" => %{"anthropic" => %{"api_key" => "sk-test"}}}
      assert Config.get_provider(config, "anthropic") == %{"api_key" => "sk-test"}
    end

    test "returns nil for unknown provider" do
      assert Config.get_provider(%{}, "unknown") == nil
    end
  end

  describe "get_providers/1" do
    test "returns all providers" do
      config = %{"provider" => %{"a" => %{}, "b" => %{}}}
      assert Config.get_providers(config) == %{"a" => %{}, "b" => %{}}
    end

    test "returns empty map when no providers" do
      assert Config.get_providers(%{}) == %{}
    end
  end

  describe "get_disabled_providers/1" do
    test "returns disabled providers list" do
      config = %{"disabled_providers" => ["a", "b"]}
      assert Config.get_disabled_providers(config) == ["a", "b"]
    end

    test "returns empty list when not set" do
      assert Config.get_disabled_providers(%{}) == []
    end
  end

  describe "get_enabled_providers/1" do
    test "returns enabled providers list" do
      config = %{"enabled_providers" => ["a", "b"]}
      assert Config.get_enabled_providers(config) == ["a", "b"]
    end

    test "returns nil when not set" do
      assert Config.get_enabled_providers(%{}) == nil
    end
  end

  describe "get_mcp_servers/1" do
    test "returns MCP server configs" do
      config = %{"mcp" => %{"server1" => %{"command" => "node"}}}
      assert Config.get_mcp_servers(config) == %{"server1" => %{"command" => "node"}}
    end

    test "returns empty map when not set" do
      assert Config.get_mcp_servers(%{}) == %{}
    end
  end

  describe "get_agents/1" do
    test "returns agent configs" do
      config = %{"agent" => %{"coder" => %{"model" => "claude"}}}
      assert Config.get_agents(config) == %{"coder" => %{"model" => "claude"}}
    end

    test "returns empty map when not set" do
      assert Config.get_agents(%{}) == %{}
    end
  end

  describe "get_default_agent/1" do
    test "returns default agent name" do
      config = %{"default_agent" => "coder"}
      assert Config.get_default_agent(config) == "coder"
    end
  end

  describe "get_server_config/1" do
    test "returns server config" do
      config = %{"server" => %{"port" => 4096}}
      assert Config.get_server_config(config) == %{"port" => 4096}
    end

    test "returns empty map when not set" do
      assert Config.get_server_config(%{}) == %{}
    end
  end

  describe "provider_configured?/2" do
    test "returns true when api_key is set" do
      config = %{"provider" => %{"anthropic" => %{"api_key" => "sk-test"}}}
      assert Config.provider_configured?(config, "anthropic") == true
    end

    test "returns true when options.apiKey is set" do
      config = %{"provider" => %{"anthropic" => %{"options" => %{"apiKey" => "sk-test"}}}}
      assert Config.provider_configured?(config, "anthropic") == true
    end

    test "returns false when provider not configured" do
      assert Config.provider_configured?(%{}, "anthropic") == false
    end

    test "returns false when api_key is empty" do
      config = %{"provider" => %{"anthropic" => %{"api_key" => ""}}}
      assert Config.provider_configured?(config, "anthropic") == false
    end
  end

  # ============================================================================
  # Git Root Discovery
  # ============================================================================

  describe "git root discovery" do
    test "finds config in subdirectory by searching up to git root", %{project_dir: project_dir} do
      # Create config at project root
      File.write!(Path.join(project_dir, "opencode.json"), ~s({"model": "root-model"}))

      # Create subdirectory
      subdir = Path.join(project_dir, "src/components")
      File.mkdir_p!(subdir)

      # Load from subdirectory - should find config at root
      assert {:ok, config} = Config.load(subdir, include_env: false)
      assert config["model"] == "root-model"
    end

    test "prefers config in current directory over parent", %{project_dir: project_dir} do
      File.write!(Path.join(project_dir, "opencode.json"), ~s({"model": "root-model"}))

      subdir = Path.join(project_dir, "src")
      File.mkdir_p!(subdir)
      File.write!(Path.join(subdir, "opencode.json"), ~s({"model": "subdir-model"}))

      assert {:ok, config} = Config.load(subdir, include_env: false)
      assert config["model"] == "subdir-model"
    end
  end

  # ============================================================================
  # Error Handling
  # ============================================================================

  describe "error handling" do
    test "returns error for invalid JSON", %{project_dir: project_dir} do
      File.write!(Path.join(project_dir, "opencode.json"), "not valid json")

      assert {:error, {:parse_error, _path, %Jason.DecodeError{}}} =
               Config.load(project_dir, include_env: false)
    end

    test "returns error when config is not an object", %{project_dir: project_dir} do
      File.write!(Path.join(project_dir, "opencode.json"), ~s(["array", "not", "object"]))

      assert {:error, {:invalid_config, _path, "Config must be a JSON object"}} =
               Config.load(project_dir, include_env: false)
    end
  end

  # ============================================================================
  # Config Saving
  # ============================================================================

  describe "config saving" do
    test "saves config to opencode.json", %{project_dir: project_dir} do
      config = %{"model" => "test-model", "theme" => "dark"}

      assert {:ok, saved_config} = Config.save(project_dir, config)

      assert saved_config == config
      assert File.exists?(Path.join(project_dir, "opencode.json"))

      {:ok, loaded} = File.read(Path.join(project_dir, "opencode.json"))
      assert loaded =~ "test-model"
      assert loaded =~ "dark"
    end

    test "merges with existing config", %{project_dir: project_dir} do
      existing = %{"model" => "existing-model", "theme" => "light"}
      File.write!(Path.join(project_dir, "opencode.json"), Jason.encode!(existing))

      new_config = %{"model" => "new-model", "provider" => %{"openai" => %{"api_key" => "key"}}}
      assert {:ok, merged} = Config.save(project_dir, new_config)

      assert merged["model"] == "new-model"
      assert merged["theme"] == "light"
      assert get_in(merged, ["provider", "openai", "api_key"]) == "key"
    end

    test "can disable merging", %{project_dir: project_dir} do
      existing = %{"model" => "existing-model"}
      File.write!(Path.join(project_dir, "opencode.json"), Jason.encode!(existing))

      new_config = %{"model" => "new-model"}
      assert {:ok, saved} = Config.save(project_dir, new_config, merge: false)

      assert saved["model"] == "new-model"
      assert saved["theme"] == nil
    end
  end

  # ============================================================================
  # Config Initialization
  # ============================================================================

  describe "init/2 - project initialization" do
    test "creates default squads config", %{project_dir: project_dir} do
      assert {:ok, config} = Config.init(project_dir)

      assert config["$schema"] == "https://opencode.ai/config.json"
      assert config["mcp"]["agent_mail"]["enabled"] == true
      assert config["mcp"]["agent_mail"]["url"] =~ "/api/mcp/agent_mail/connect"
      assert config["agent"]["default"] == %{"agent" => "generalist"}
      assert config["agent"]["commands"]["squads-status"] != nil
    end

    test "applies overrides", %{project_dir: project_dir} do
      overrides = %{
        "model" => "custom-model",
        "mcp" => %{"agent_mail" => %{"url" => "http://custom:9999/mcp/"}}
      }

      assert {:ok, config} = Config.init(project_dir, overrides)

      assert config["model"] == "custom-model"
      assert config["mcp"]["agent_mail"]["url"] == "http://custom:9999/mcp/"
      assert config["mcp"]["agent_mail"]["enabled"] == true
      assert config["agent"]["default"] == %{"agent" => "generalist"}
    end

    test "creates opencode.json file", %{project_dir: project_dir} do
      assert {:ok, _config} = Config.init(project_dir)

      assert File.exists?(Path.join(project_dir, "opencode.json"))
    end
  end

  # ============================================================================
  # Default Config
  # ============================================================================

  describe "default_squads_config/0" do
    test "returns complete squads config structure" do
      config = Config.default_squads_config()

      assert is_map(config)
      assert config["$schema"] == "https://opencode.ai/config.json"
      assert is_list(config["plugin"])

      assert config["mcp"] != nil
      assert config["mcp"]["agent_mail"] != nil
      assert config["mcp"]["agent_mail"]["type"] == "remote"
      assert config["mcp"]["agent_mail"]["enabled"] == true

      assert config["agent"] != nil
      assert config["agent"]["default"] != nil
      assert config["agent"]["commands"] != nil
    end

    test "includes agent mail MCP with env var placeholder", _context do
      config = Config.default_squads_config()

      headers = config["mcp"]["agent_mail"]["headers"]
      assert headers["Authorization"] =~ "AGENT_MAIL_API_KEY"
    end
  end
end
