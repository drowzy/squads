defmodule Squads.Config.ProjectConfig do
  @moduledoc """
  Schema and validation for `.squads/config.json` files.

  The config file lives in the target project's `.squads/` directory and contains
  settings for orchestration, agent configuration, and integration preferences.
  """

  @config_dir ".squads"
  @config_file "config.json"

  @default_config %{
    "version" => 1,
    "name" => nil,
    "description" => nil,
    "orchestration" => %{
      "max_parallel_agents" => 4,
      "default_model" => nil,
      "auto_assign" => true
    },
    "integrations" => %{
      "opencode" => %{
        "enabled" => true
      },
      "github" => %{
        "enabled" => true,
        "repo" => nil
      },
      "mail" => %{
        "enabled" => true,
        "auto_poll" => false
      }
    },
    "worktrees" => %{
      "enabled" => true,
      "base_branch" => "main"
    }
  }

  @type validation_error :: {:error, String.t()}
  @type config :: map()

  @doc """
  Returns the default configuration map.
  """
  @spec default_config() :: config()
  def default_config, do: @default_config

  @doc """
  Returns the config directory name.
  """
  @spec config_dir() :: String.t()
  def config_dir, do: @config_dir

  @doc """
  Returns the config file name.
  """
  @spec config_file() :: String.t()
  def config_file, do: @config_file

  @doc """
  Returns the full path to the config file for a given project path.
  """
  @spec config_path(String.t()) :: String.t()
  def config_path(project_path) do
    Path.join([project_path, @config_dir, @config_file])
  end

  @doc """
  Loads and validates the config from a project path.

  Returns `{:ok, config}` on success or `{:error, reason}` on failure.
  """
  @spec load(String.t()) :: {:ok, config()} | {:error, String.t()}
  def load(project_path) do
    path = config_path(project_path)

    with {:ok, content} <- read_file(path),
         {:ok, config} <- decode_json(content),
         :ok <- validate(config) do
      {:ok, merge_defaults(config)}
    end
  end

  @doc """
  Saves a config to the project path.

  Creates the `.squads/` directory if it doesn't exist.
  """
  @spec save(String.t(), config()) :: :ok | {:error, String.t()}
  def save(project_path, config) do
    with :ok <- validate(config) do
      dir = Path.join(project_path, @config_dir)
      path = config_path(project_path)

      with :ok <- ensure_dir(dir),
           {:ok, json} <- encode_json(config),
           :ok <- write_file(path, json) do
        :ok
      end
    end
  end

  @doc """
  Validates a config map against the schema.

  Returns `:ok` if valid, `{:error, reason}` otherwise.
  """
  @spec validate(config()) :: :ok | validation_error()
  def validate(config) when is_map(config) do
    with :ok <- validate_version(config),
         :ok <- validate_orchestration(config),
         :ok <- validate_integrations(config),
         :ok <- validate_worktrees(config),
         :ok <- validate_features(config) do
      :ok
    end
  end

  def validate(_), do: {:error, "config must be a map"}

  @doc """
  Merges a partial config with defaults.
  """
  @spec merge_defaults(config()) :: config()
  def merge_defaults(config) do
    deep_merge(@default_config, config)
  end

  @doc """
  Creates a new config with the given name and optional overrides.
  """
  @spec new(String.t(), map()) :: config()
  def new(name, overrides \\ %{}) do
    @default_config
    |> Map.put("name", name)
    |> deep_merge(overrides)
  end

  # Private functions

  defp validate_version(%{"version" => v}) when is_integer(v) and v >= 1, do: :ok
  defp validate_version(%{"version" => _}), do: {:error, "version must be a positive integer"}
  defp validate_version(_), do: :ok

  defp validate_orchestration(%{"orchestration" => orch}) when is_map(orch) do
    cond do
      Map.has_key?(orch, "max_parallel_agents") and
          not is_integer(orch["max_parallel_agents"]) ->
        {:error, "orchestration.max_parallel_agents must be an integer"}

      Map.has_key?(orch, "max_parallel_agents") and orch["max_parallel_agents"] < 1 ->
        {:error, "orchestration.max_parallel_agents must be at least 1"}

      Map.has_key?(orch, "auto_assign") and not is_boolean(orch["auto_assign"]) ->
        {:error, "orchestration.auto_assign must be a boolean"}

      true ->
        :ok
    end
  end

  defp validate_orchestration(%{"orchestration" => _}),
    do: {:error, "orchestration must be a map"}

  defp validate_orchestration(_), do: :ok

  defp validate_integrations(%{"integrations" => integrations}) when is_map(integrations) do
    Enum.reduce_while(integrations, :ok, fn {key, value}, _acc ->
      case validate_integration(key, value) do
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  defp validate_integrations(%{"integrations" => _}),
    do: {:error, "integrations must be a map"}

  defp validate_integrations(_), do: :ok

  defp validate_integration(name, config) when is_map(config) do
    case Map.get(config, "enabled") do
      nil -> :ok
      enabled when is_boolean(enabled) -> :ok
      _ -> {:error, "integrations.#{name}.enabled must be a boolean"}
    end
  end

  defp validate_integration(name, _),
    do: {:error, "integrations.#{name} must be a map"}

  defp validate_worktrees(%{"worktrees" => wt}) when is_map(wt) do
    cond do
      Map.has_key?(wt, "enabled") and not is_boolean(wt["enabled"]) ->
        {:error, "worktrees.enabled must be a boolean"}

      Map.has_key?(wt, "base_branch") and not is_binary(wt["base_branch"]) ->
        {:error, "worktrees.base_branch must be a string"}

      true ->
        :ok
    end
  end

  defp validate_worktrees(%{"worktrees" => _}), do: {:error, "worktrees must be a map"}
  defp validate_worktrees(_), do: :ok

  defp validate_features(%{"features" => features}) when is_map(features), do: :ok
  defp validate_features(%{"features" => _}), do: {:error, "features must be a map"}
  defp validate_features(_), do: :ok

  defp read_file(path) do
    case File.read(path) do
      {:ok, content} -> {:ok, content}
      {:error, :enoent} -> {:error, "config file not found: #{path}"}
      {:error, reason} -> {:error, "failed to read config: #{inspect(reason)}"}
    end
  end

  defp write_file(path, content) do
    case File.write(path, content) do
      :ok -> :ok
      {:error, reason} -> {:error, "failed to write config: #{inspect(reason)}"}
    end
  end

  defp ensure_dir(dir) do
    case File.mkdir_p(dir) do
      :ok -> :ok
      {:error, reason} -> {:error, "failed to create directory: #{inspect(reason)}"}
    end
  end

  defp decode_json(content) do
    case Jason.decode(content) do
      {:ok, config} ->
        {:ok, config}

      {:error, %Jason.DecodeError{} = error} ->
        {:error, "invalid JSON: #{Exception.message(error)}"}
    end
  end

  defp encode_json(config) do
    case Jason.encode(config, pretty: true) do
      {:ok, json} -> {:ok, json}
      {:error, reason} -> {:error, "failed to encode JSON: #{inspect(reason)}"}
    end
  end

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
