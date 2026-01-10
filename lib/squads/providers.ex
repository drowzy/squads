defmodule Squads.Providers do
  @moduledoc """
  The Providers context manages AI provider configurations.

  This module handles:
  - Syncing provider data from OpenCode server
  - Querying available providers and models
  - Tracking provider connection status
  """

  import Ecto.Query, warn: false
  alias Squads.Repo
  alias Squads.Providers.Provider
  alias Squads.Projects
  alias Squads.OpenCode.Client
  alias Squads.OpenCode.Server, as: OpenCodeServer

  require Logger

  # ============================================================================
  # CRUD Operations
  # ============================================================================

  @doc """
  Lists all providers for a project.
  """
  @spec list_providers(Ecto.UUID.t()) :: [Provider.t()]
  def list_providers(project_id) do
    Provider
    |> where(project_id: ^project_id)
    |> order_by(:name)
    |> Repo.all()
  end

  @doc """
  Lists only connected providers for a project.
  """
  @spec list_connected_providers(Ecto.UUID.t()) :: [Provider.t()]
  def list_connected_providers(project_id) do
    Provider
    |> where(project_id: ^project_id, status: "connected")
    |> order_by(:name)
    |> Repo.all()
  end

  @doc """
  Gets a provider by ID.
  """
  @spec get_provider(Ecto.UUID.t()) :: Provider.t() | nil
  def get_provider(id), do: Repo.get(Provider, id)

  @doc """
  Fetches a provider by ID with a tuple result.
  """
  @spec fetch_provider(Ecto.UUID.t()) :: {:ok, Provider.t()} | {:error, :not_found}
  def fetch_provider(id) do
    case get_provider(id) do
      nil -> {:error, :not_found}
      provider -> {:ok, provider}
    end
  end

  @doc """
  Gets a provider by ID or raises.
  """
  @spec get_provider!(Ecto.UUID.t()) :: Provider.t()
  def get_provider!(id) do
    case get_provider(id) do
      nil -> raise Ecto.NoResultsError, queryable: Provider
      provider -> provider
    end
  end

  @spec get_provider_by_provider_id(Ecto.UUID.t(), String.t()) :: Provider.t() | nil
  def get_provider_by_provider_id(project_id, provider_id) do
    Provider
    |> where(project_id: ^project_id, provider_id: ^provider_id)
    |> Repo.one()
  end

  @doc """
  Creates a provider.
  """
  @spec create_provider(map()) :: {:ok, Provider.t()} | {:error, Ecto.Changeset.t()}
  def create_provider(attrs) do
    %Provider{}
    |> Provider.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a provider.
  """
  @spec update_provider(Provider.t(), map()) :: {:ok, Provider.t()} | {:error, Ecto.Changeset.t()}
  def update_provider(%Provider{} = provider, attrs) do
    provider
    |> Provider.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a provider.
  """
  @spec delete_provider(Provider.t()) :: {:ok, Provider.t()} | {:error, Ecto.Changeset.t()}
  def delete_provider(%Provider{} = provider) do
    Repo.delete(provider)
  end

  # ============================================================================
  # Sync from OpenCode
  # ============================================================================

  @doc """
  Syncs provider data from OpenCode server for a project.

  Fetches provider list from `/provider` endpoint and upserts into database.

  ## Options

    * `:client_opts` - Options to pass to the OpenCode client

  ## Returns

    * `{:ok, providers}` - List of synced providers
    * `{:error, reason}` - Sync failed
  """
  @spec sync_from_opencode(Ecto.UUID.t(), keyword()) ::
          {:ok, [Provider.t()]} | {:error, term()}
  def sync_from_opencode(project_id, opts \\ []) do
    client_opts = Keyword.get(opts, :client_opts, [])
    client_opts = add_base_url(project_id, client_opts)

    case Client.list_providers(client_opts) do
      {:ok, provider_payload} ->
        config_payload =
          case Client.get_config_providers(client_opts) do
            {:ok, config} -> config
            {:error, _} -> %{}
          end

        providers = normalize_providers(provider_payload, config_payload)
        synced = upsert_providers(project_id, providers)
        {:ok, synced}

      {:error, {:transport_error, reason}} ->
        Logger.info("OpenCode server not available for provider sync; using defaults",
          project_id: project_id,
          reason: inspect(reason)
        )

        {:ok, ensure_default_providers(project_id)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Syncs a single provider's status.
  """
  @spec sync_provider_status(Provider.t(), keyword()) ::
          {:ok, Provider.t()} | {:error, term()}
  def sync_provider_status(%Provider{} = provider, opts \\ []) do
    client_opts = Keyword.get(opts, :client_opts, [])
    client_opts = add_base_url(provider.project_id, client_opts)

    case Client.list_providers(client_opts) do
      {:ok, %{"all" => providers} = payload} ->
        connected = payload |> Map.get("connected", []) |> MapSet.new()
        defaults = extract_defaults(payload)

        status =
          if MapSet.member?(connected, provider.provider_id),
            do: "connected",
            else: "disconnected"

        provider_data = find_provider_data(providers, provider.provider_id)
        models = if provider_data, do: normalize_models(provider_data), else: []

        attrs = %{
          status: status,
          models: models,
          default_model: defaults[provider.provider_id],
          metadata: if(provider_data, do: Map.drop(provider_data, ["models"]), else: %{})
        }

        provider
        |> Provider.sync_changeset(attrs)
        |> Repo.update()

      {:ok, providers} when is_list(providers) ->
        case find_provider_data(providers, provider.provider_id) do
          nil ->
            update_provider_status(provider, "disconnected", [])

          data ->
            update_provider_status(
              provider,
              normalize_status(data),
              normalize_models(data)
            )
        end

      {:error, reason} ->
        update_provider_status(provider, "error", [])
        {:error, reason}
    end
  end

  # ============================================================================
  # Model Queries
  # ============================================================================

  @doc """
  Lists all available models across all connected providers for a project.
  """
  @spec list_all_models(Ecto.UUID.t()) :: [map()]
  def list_all_models(project_id) do
    project_id
    |> list_connected_providers()
    |> Enum.flat_map(fn provider ->
      Enum.map(provider.models, fn model ->
        model_id = model["id"]

        model
        |> Map.put("model_id", model_id)
        |> Map.put("id", "#{provider.provider_id}/#{model_id}")
        |> Map.put("provider_id", provider.provider_id)
        |> Map.put("provider_name", provider.name)
      end)
    end)
  end

  @doc """
  Gets the default model for a project.

  Returns the first available default model from connected providers.
  """
  @spec get_default_model(Ecto.UUID.t()) :: map() | nil
  def get_default_model(project_id) do
    project_id
    |> list_connected_providers()
    |> Enum.find_value(fn provider ->
      model_id = provider.default_model

      if model_id do
        Enum.find(provider.models, fn model ->
          model["id"] == model_id
        end)
        |> case do
          nil ->
            nil

          model ->
            model
            |> Map.put("model_id", model_id)
            |> Map.put("id", "#{provider.provider_id}/#{model_id}")
            |> Map.put("provider_id", provider.provider_id)
            |> Map.put("provider_name", provider.name)
        end
      end
    end)
  end

  @doc """
  Finds a model by ID across all providers.
  """
  @spec find_model(Ecto.UUID.t(), String.t()) :: map() | nil
  def find_model(project_id, model_id) do
    project_id
    |> list_all_models()
    |> Enum.find(fn model ->
      model["id"] == model_id or model["model_id"] == model_id
    end)
  end

  # ============================================================================
  # Private Implementation
  # ============================================================================

  defp add_base_url(project_id, client_opts) do
    case OpenCodeServer.get_url(project_id) do
      {:ok, url} ->
        Keyword.put_new(client_opts, :base_url, url)

      _ ->
        maybe_attach_base_url(project_id, client_opts)
    end
  end

  defp maybe_attach_base_url(project_id, client_opts) do
    if test_env?() do
      client_opts
    else
      case Projects.get_project(project_id) do
        %Projects.Project{path: path} ->
          case OpenCodeServer.ensure_running(project_id, path) do
            {:ok, url} ->
              Keyword.put_new(client_opts, :base_url, url)

            {:error, reason} ->
              Logger.warning("OpenCode server not available for provider sync",
                project_id: project_id,
                reason: inspect(reason)
              )

              client_opts
          end

        _ ->
          client_opts
      end
    end
  end

  defp test_env? do
    Code.ensure_loaded?(Mix) and function_exported?(Mix, :env, 0) and Mix.env() == :test
  end

  defp ensure_default_providers(project_id) do
    default_provider_defs()
    |> Enum.map(fn provider_data ->
      case get_provider_by_provider_id(project_id, provider_data.provider_id) do
        nil ->
          attrs = Map.put(provider_data, :project_id, project_id)
          {:ok, provider} = create_provider(attrs)
          provider

        existing ->
          existing
      end
    end)
  end

  defp default_provider_defs do
    [
      %{provider_id: "anthropic", name: "Anthropic", status: "disconnected", models: []},
      %{provider_id: "openai", name: "OpenAI", status: "disconnected", models: []},
      %{provider_id: "google", name: "Google", status: "disconnected", models: []},
      %{provider_id: "openrouter", name: "OpenRouter", status: "disconnected", models: []}
    ]
  end

  defp normalize_providers(%{"all" => providers} = payload, config_payload)
       when is_list(providers) do
    connected = payload |> Map.get("connected", []) |> MapSet.new()
    defaults = extract_defaults(payload) |> Map.merge(extract_defaults(config_payload))

    Enum.map(providers, fn provider ->
      provider_id = provider["id"] || provider["provider"]

      %{
        provider_id: provider_id,
        name: provider["name"] || String.capitalize(provider_id),
        status: if(MapSet.member?(connected, provider_id), do: "connected", else: "disconnected"),
        models: normalize_models(provider),
        default_model: defaults[provider_id],
        metadata: Map.drop(provider, ["models"])
      }
    end)
  end

  defp normalize_providers(provider_list, config_payload) when is_list(provider_list) do
    defaults = extract_defaults(config_payload)

    Enum.map(provider_list, fn provider ->
      provider_id = provider["id"] || provider["provider"]

      %{
        provider_id: provider_id,
        name: provider["name"] || String.capitalize(provider_id),
        status: normalize_status(provider),
        models: normalize_models(provider),
        default_model: defaults[provider_id],
        metadata: Map.drop(provider, ["models"])
      }
    end)
  end

  defp normalize_providers(_, _), do: []

  defp extract_defaults(%{"default" => defaults}) when is_map(defaults), do: defaults

  defp extract_defaults(config_providers) when is_map(config_providers) do
    config_providers
    |> Map.get("providers", %{})
    |> Enum.into(%{}, fn {provider_id, config} ->
      {provider_id, config["default"]}
    end)
  end

  defp extract_defaults(_), do: %{}

  defp normalize_status(%{"status" => "connected"}), do: "connected"
  defp normalize_status(%{"status" => "ready"}), do: "connected"
  defp normalize_status(%{"status" => "ok"}), do: "connected"
  defp normalize_status(%{"status" => "error"}), do: "error"
  defp normalize_status(%{"status" => "disconnected"}), do: "disconnected"
  defp normalize_status(%{"connected" => true}), do: "connected"
  defp normalize_status(%{"connected" => false}), do: "disconnected"
  defp normalize_status(_), do: "unknown"

  defp normalize_models(%{"models" => models}) when is_map(models) do
    models
    |> Enum.map(fn
      {model_id, model} when is_map(model) ->
        model
        |> Map.put_new("id", model_id)
        |> Map.put_new("name", model["id"] || model_id)
        # Preserve context/output limits if they exist in the model map
        |> Map.put_new("context_window", model["context_window"] || model["contextWindow"])
        |> Map.put_new("max_output", model["max_output"] || model["maxOutput"])

      {model_id, _} ->
        %{"id" => model_id, "name" => model_id}
    end)
    |> Enum.sort_by(&(&1["name"] || &1["id"]))
  end

  defp normalize_models(%{"models" => models}) when is_list(models) do
    Enum.map(models, fn
      model when is_binary(model) ->
        %{"id" => model, "name" => model}

      model when is_map(model) ->
        %{
          "id" => model["id"] || model["model"],
          "name" => model["name"] || model["id"] || model["model"],
          "context_window" => model["context_window"] || model["contextWindow"],
          "max_output" => model["max_output"] || model["maxOutput"]
        }
    end)
  end

  defp normalize_models(_), do: []

  defp upsert_providers(project_id, providers) do
    Enum.map(providers, fn provider_data ->
      case get_provider_by_provider_id(project_id, provider_data.provider_id) do
        nil ->
          attrs = Map.put(provider_data, :project_id, project_id)
          {:ok, provider} = create_provider(attrs)
          provider

        existing ->
          {:ok, provider} =
            existing
            |> Provider.sync_changeset(provider_data)
            |> Repo.update()

          provider
      end
    end)
  end

  defp find_provider_data(provider_list, provider_id) do
    Enum.find(provider_list, fn p ->
      p["id"] == provider_id || p["provider"] == provider_id
    end)
  end

  defp update_provider_status(provider, status, models) do
    provider
    |> Provider.sync_changeset(%{status: status, models: models})
    |> Repo.update()
  end
end
