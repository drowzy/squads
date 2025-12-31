defmodule Squads.OpenCode.Config do
  @moduledoc """
  OpenCode configuration file parser and merger.

  This module provides fallback configuration when the OpenCode server is not
  reachable. It parses and merges configuration from:

  1. Global config: `~/.config/opencode/opencode.json`
  2. Project config: `opencode.json` in project root
  3. Custom config: via `OPENCODE_CONFIG` env var
  4. Environment variable overrides

  ## Config Merging

  Configurations are deep merged with later sources overriding earlier ones:
  - Global config is loaded first
  - Project config is merged on top
  - Custom config (if specified) is merged next
  - Environment variables override specific fields

  ## Example

      config = Squads.OpenCode.Config.load("/path/to/project")
      # => %{
      #      "model" => "anthropic/claude-sonnet-4-5",
      #      "provider" => %{...},
      #      ...
      #    }
  """

  require Logger

  @global_config_paths [
    "~/.config/opencode/opencode.json",
    "~/.config/opencode/opencode.jsonc"
  ]

  @project_config_names [
    "opencode.json",
    "opencode.jsonc"
  ]

  # Environment variables that override config values
  @env_overrides %{
    "OPENCODE_MODEL" => ["model"],
    "OPENCODE_SMALL_MODEL" => ["small_model"],
    "OPENCODE_THEME" => ["theme"],
    "OPENCODE_AUTOUPDATE" => ["autoupdate"],
    "ANTHROPIC_API_KEY" => ["provider", "anthropic", "api_key"],
    "OPENAI_API_KEY" => ["provider", "openai", "api_key"],
    "GOOGLE_GENERATIVE_AI_API_KEY" => ["provider", "google", "api_key"],
    "OPENROUTER_API_KEY" => ["provider", "openrouter", "api_key"]
  }

  # ============================================================================
  # Public API
  # ============================================================================

  @doc """
  Loads and merges OpenCode configuration for a project.

  Merges global, project, and custom configs, then applies env var overrides.

  ## Options

    * `:include_env` - Apply environment variable overrides (default: true)
    * `:custom_config` - Path to a custom config file
    * `:include_global` - Include global config (default: true)

  ## Returns

    * `{:ok, config}` - Merged configuration map
    * `{:error, reason}` - If parsing failed
  """
  @spec load(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def load(project_path, opts \\ []) do
    include_env = Keyword.get(opts, :include_env, true)
    include_global = Keyword.get(opts, :include_global, true)
    custom_config_path = Keyword.get(opts, :custom_config) || System.get_env("OPENCODE_CONFIG")

    global =
      if include_global do
        load_global_config()
      else
        {:ok, %{}}
      end

    with {:ok, global} <- global,
         {:ok, project} <- load_project_config(project_path),
         {:ok, custom} <- load_custom_config(custom_config_path) do
      merged =
        %{}
        |> deep_merge(global)
        |> deep_merge(project)
        |> deep_merge(custom)

      config =
        if include_env do
          apply_env_overrides(merged)
        else
          merged
        end

      {:ok, config}
    end
  end

  @doc """
  Gets the default model from configuration.
  """
  @spec get_model(map()) :: String.t() | nil
  def get_model(config), do: config["model"]

  @doc """
  Gets the small model from configuration.
  """
  @spec get_small_model(map()) :: String.t() | nil
  def get_small_model(config), do: config["small_model"]

  @doc """
  Gets provider configuration.
  """
  @spec get_provider(map(), String.t()) :: map() | nil
  def get_provider(config, provider_id) do
    get_in(config, ["provider", provider_id])
  end

  @doc """
  Gets all configured providers.
  """
  @spec get_providers(map()) :: map()
  def get_providers(config), do: config["provider"] || %{}

  @doc """
  Gets disabled providers list.
  """
  @spec get_disabled_providers(map()) :: [String.t()]
  def get_disabled_providers(config), do: config["disabled_providers"] || []

  @doc """
  Gets enabled providers list.
  """
  @spec get_enabled_providers(map()) :: [String.t()] | nil
  def get_enabled_providers(config), do: config["enabled_providers"]

  @doc """
  Gets MCP server configurations.
  """
  @spec get_mcp_servers(map()) :: map()
  def get_mcp_servers(config), do: config["mcp"] || %{}

  @doc """
  Gets agent configurations.
  """
  @spec get_agents(map()) :: map()
  def get_agents(config), do: config["agent"] || %{}

  @doc """
  Gets the default agent name.
  """
  @spec get_default_agent(map()) :: String.t() | nil
  def get_default_agent(config), do: config["default_agent"]

  @doc """
  Gets server configuration.
  """
  @spec get_server_config(map()) :: map()
  def get_server_config(config), do: config["server"] || %{}

  # ============================================================================
  # Config Saving
  # ============================================================================

  @doc """
  Saves OpenCode configuration to a project directory.

  Creates or merges the config file at `<project_path>/opencode.json`.
  If an existing config exists, it will be deep-merged with the new config.

  ## Options

    * `:merge` - Whether to merge with existing config (default: true)
    * `:pretty` - Whether to pretty-print JSON (default: true)

  ## Returns

    * `{:ok, config}` - Saved configuration map
    * `{:error, reason}` - If save failed
  """
  @spec save(String.t(), map(), keyword()) :: {:ok, map()} | {:error, term()}
  def save(project_path, config, opts \\ []) do
    merge = Keyword.get(opts, :merge, true)
    pretty = Keyword.get(opts, :pretty, true)

    config_path = Path.join(project_path, "opencode.json")

    merged_config =
      if merge && File.exists?(config_path) do
        case parse_config_file(config_path) do
          {:ok, existing_config} ->
            deep_merge(existing_config, config)

          {:error, _} ->
            config
        end
      else
        config
      end

    with {:ok, json} <- Jason.encode(merged_config, pretty: pretty),
         :ok <- File.write(config_path, json) do
      {:ok, merged_config}
    end
  end

  @doc """
  Initializes a project with default OpenCode configuration.

  Creates opencode.json with sensible defaults including:
  - Agent mail MCP configuration
  - Squads custom commands

  ## Returns

    * `{:ok, config}` - Created configuration map
    * `{:error, reason}` - If initialization failed
  """
  @spec init(String.t(), map()) :: {:ok, map()} | {:error, term()}
  def init(project_path, overrides \\ %{}) do
    default_config = default_squads_config()

    merged_config = deep_merge(default_config, overrides)
    save(project_path, merged_config, merge: false)
  end

  @doc """
  Returns the default OpenCode configuration for Squads projects.
  """
  @spec default_squads_config() :: map()
  def default_squads_config do
    %{
      "$schema" => "https://opencode.ai/config.json",
      "plugin" => ["opencode-openai-codex-auth@4.2.0"],
      "mcp" => %{
        "agent_mail" => %{
          "type" => "remote",
          "url" => "http://127.0.0.1:8765/mcp/agent_mail",
          "enabled" => true,
          "headers" => %{
            "Authorization" => "Bearer {env:AGENT_MAIL_API_KEY}"
          }
        }
      },
      "agent" => %{
        "default" => "generalist",
        "commands" => %{
          "squads-status" => %{
            "description" => "Show current squad status and tasks",
            "agent" => "generalist",
            "noReply" => true
          },
          "squads-tickets" => %{
            "description" => "List available tickets from bd",
            "agent" => "generalist",
            "noReply" => true
          }
        }
      }
    }
  end

  @doc """
  Checks if a specific provider has valid credentials configured.
  """
  @spec provider_configured?(map(), String.t()) :: boolean()
  def provider_configured?(config, provider_id) do
    case get_provider(config, provider_id) do
      nil ->
        false

      provider_config ->
        api_key =
          get_in(provider_config, ["options", "apiKey"]) ||
            get_in(provider_config, ["api_key"])

        api_key != nil and api_key != ""
    end
  end

  # ============================================================================
  # Config Loading
  # ============================================================================

  defp load_global_config do
    @global_config_paths
    |> Enum.map(&Path.expand/1)
    |> Enum.find(&File.exists?/1)
    |> case do
      nil ->
        {:ok, %{}}

      path ->
        case parse_config_file(path) do
          {:ok, config} ->
            {:ok, config}

          {:error, reason} ->
            # Gracefully degrade - log warning but continue with empty global config
            Logger.warning("Ignoring invalid global config: #{inspect(reason)}")
            {:ok, %{}}
        end
    end
  end

  defp load_project_config(project_path) do
    config_path = find_project_config(project_path)

    case config_path do
      nil -> {:ok, %{}}
      path -> parse_config_file(path)
    end
  end

  defp load_custom_config(nil), do: {:ok, %{}}

  defp load_custom_config(path) do
    expanded = Path.expand(path)

    if File.exists?(expanded) do
      parse_config_file(expanded)
    else
      Logger.warning("Custom config file not found: #{path}")
      {:ok, %{}}
    end
  end

  defp find_project_config(project_path) do
    # Start from project path and traverse up to git root
    project_path
    |> find_git_root()
    |> search_path_for_config(project_path)
  end

  defp find_git_root(path) do
    git_dir = Path.join(path, ".git")

    cond do
      File.exists?(git_dir) ->
        path

      path == "/" ->
        nil

      true ->
        find_git_root(Path.dirname(path))
    end
  end

  defp search_path_for_config(nil, project_path) do
    # No git root, just check project path
    find_config_in_dir(project_path)
  end

  defp search_path_for_config(git_root, project_path) do
    # Check from project path up to git root
    check_path = project_path

    search_up_to_root(check_path, git_root)
  end

  defp search_up_to_root(current, git_root) do
    case find_config_in_dir(current) do
      nil ->
        if current == git_root do
          nil
        else
          search_up_to_root(Path.dirname(current), git_root)
        end

      config_path ->
        config_path
    end
  end

  defp find_config_in_dir(dir) do
    @project_config_names
    |> Enum.map(&Path.join(dir, &1))
    |> Enum.find(&File.exists?/1)
  end

  # ============================================================================
  # Config Parsing
  # ============================================================================

  defp parse_config_file(path) do
    Logger.debug("Loading OpenCode config from: #{path}")

    case File.read(path) do
      {:ok, content} ->
        # Strip JSONC comments if present
        json_content = strip_jsonc_comments(content)
        parse_json(json_content, path)

      {:error, reason} ->
        Logger.warning("Failed to read config file #{path}: #{inspect(reason)}")
        {:error, {:read_error, path, reason}}
    end
  end

  defp parse_json(content, path) do
    case Jason.decode(content) do
      {:ok, config} when is_map(config) ->
        # Expand variable substitutions
        expanded = expand_variables(config, Path.dirname(path))
        {:ok, expanded}

      {:ok, _} ->
        {:error, {:invalid_config, path, "Config must be a JSON object"}}

      {:error, %Jason.DecodeError{} = error} ->
        Logger.warning("Failed to parse config #{path}: #{inspect(error)}")
        {:error, {:parse_error, path, error}}
    end
  end

  defp strip_jsonc_comments(content) do
    # This regex attempts to find comments while avoiding // inside strings.
    # It's not a full parser but handles the http:// case by matching strings first.
    Regex.replace(~r/"(?:\\.|[^"\\])*"|(\/\/[^\n]*|\/\*.*?\*\/)/s, content, fn
      # It's a string, return as is
      match, "" -> match
      # It's a comment, replace with empty string
      _, _comment -> ""
    end)
  end

  # ============================================================================
  # Variable Expansion
  # ============================================================================

  defp expand_variables(config, base_dir) when is_map(config) do
    Map.new(config, fn {key, value} ->
      {key, expand_variables(value, base_dir)}
    end)
  end

  defp expand_variables(config, base_dir) when is_list(config) do
    Enum.map(config, &expand_variables(&1, base_dir))
  end

  defp expand_variables(value, base_dir) when is_binary(value) do
    value
    |> expand_env_vars()
    |> expand_file_refs(base_dir)
  end

  defp expand_variables(value, _base_dir), do: value

  defp expand_env_vars(value) do
    Regex.replace(~r/\{env:([^}]+)\}/, value, fn _, var_name ->
      System.get_env(var_name) || ""
    end)
  end

  defp expand_file_refs(value, base_dir) do
    Regex.replace(~r/\{file:([^}]+)\}/, value, fn _, file_path ->
      expanded_path =
        file_path
        |> String.replace_leading("~", System.user_home!())
        |> then(fn path ->
          if String.starts_with?(path, "/") do
            path
          else
            Path.join(base_dir, path)
          end
        end)

      case File.read(expanded_path) do
        {:ok, content} -> String.trim(content)
        {:error, _} -> ""
      end
    end)
  end

  # ============================================================================
  # Environment Overrides
  # ============================================================================

  defp apply_env_overrides(config) do
    Enum.reduce(@env_overrides, config, fn {env_var, path}, acc ->
      case System.get_env(env_var) do
        nil -> acc
        "" -> acc
        value -> put_nested(acc, path, parse_env_value(value))
      end
    end)
  end

  defp parse_env_value("true"), do: true
  defp parse_env_value("false"), do: false
  defp parse_env_value(value), do: value

  defp put_nested(map, [key], value) do
    Map.put(map, key, value)
  end

  defp put_nested(map, [key | rest], value) do
    nested = Map.get(map, key, %{})
    Map.put(map, key, put_nested(nested, rest, value))
  end

  # ============================================================================
  # Deep Merge
  # ============================================================================

  defp deep_merge(left, right) when is_map(left) and is_map(right) do
    Map.merge(left, right, fn
      _key, left_val, right_val when is_map(left_val) and is_map(right_val) ->
        deep_merge(left_val, right_val)

      _key, _left_val, right_val ->
        right_val
    end)
  end

  defp deep_merge(_left, right), do: right
end
