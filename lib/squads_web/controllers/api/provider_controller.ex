defmodule SquadsWeb.API.ProviderController do
  @moduledoc """
  API controller for AI provider management.

  Provides endpoints to list providers, models, and trigger sync.
  """
  use SquadsWeb, :controller

  alias Squads.Providers

  action_fallback SquadsWeb.FallbackController

  @doc """
  List all providers for a project.

  GET /api/projects/:project_id/providers
  GET /api/projects/:project_id/providers?status=connected
  """
  def index(conn, %{"project_id" => project_id} = params) do
    case Ecto.UUID.cast(project_id) do
      {:ok, uuid} ->
        providers =
          case params["status"] do
            "connected" ->
              Providers.list_connected_providers(uuid)

            _ ->
              Providers.list_providers(uuid)
          end

        render(conn, :index, providers: providers)

      :error ->
        render(conn, :index, providers: [])
    end
  end

  @doc """
  Get a specific provider.

  GET /api/providers/:id
  """
  def show(conn, %{"id" => id}) do
    case Ecto.UUID.cast(id) do
      {:ok, uuid} ->
        case Providers.get_provider(uuid) do
          nil ->
            {:error, :not_found}

          provider ->
            render(conn, :show, provider: provider)
        end

      :error ->
        {:error, :not_found}
    end
  end

  @doc """
  List all models for a project across all connected providers.

  GET /api/projects/:project_id/models
  """
  def models(conn, %{"project_id" => project_id}) do
    case Ecto.UUID.cast(project_id) do
      {:ok, uuid} ->
        models = Providers.list_all_models(uuid)
        render(conn, :models, models: models)

      :error ->
        render(conn, :models, models: [])
    end
  end

  @doc """
  Get the default model for a project.

  GET /api/projects/:project_id/models/default
  """
  def default_model(conn, %{"project_id" => project_id}) do
    case Ecto.UUID.cast(project_id) do
      {:ok, uuid} ->
        case Providers.get_default_model(uuid) do
          nil ->
            {:error, :not_found}

          model ->
            render(conn, :model, model: model)
        end

      :error ->
        {:error, :not_found}
    end
  end

  @doc """
  Sync providers from OpenCode server.

  POST /api/projects/:project_id/providers/sync
  """
  def sync(conn, %{"project_id" => project_id}) do
    case Ecto.UUID.cast(project_id) do
      {:ok, uuid} ->
        case Providers.sync_from_opencode(uuid) do
          {:ok, providers} ->
            render(conn, :index, providers: providers)

          {:error, {:transport_error, _}} ->
            conn
            |> put_status(:service_unavailable)
            |> json(%{error: "OpenCode server not available"})

          {:error, reason} ->
            conn
            |> put_status(:unprocessable_entity)
            |> json(%{error: "Sync failed", details: inspect(reason)})
        end

      :error ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "invalid_id", message: "Invalid project ID"})
    end
  end
end
