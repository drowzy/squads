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
    providers =
      case params["status"] do
        "connected" ->
          Providers.list_connected_providers(project_id)

        _ ->
          Providers.list_providers(project_id)
      end

    render(conn, :index, providers: providers)
  end

  @doc """
  Get a specific provider.

  GET /api/providers/:id
  """
  def show(conn, %{"id" => id}) do
    case Providers.get_provider(id) do
      nil ->
        {:error, :not_found}

      provider ->
        render(conn, :show, provider: provider)
    end
  end

  @doc """
  List all models for a project across all connected providers.

  GET /api/projects/:project_id/models
  """
  def models(conn, %{"project_id" => project_id}) do
    models = Providers.list_all_models(project_id)
    render(conn, :models, models: models)
  end

  @doc """
  Get the default model for a project.

  GET /api/projects/:project_id/models/default
  """
  def default_model(conn, %{"project_id" => project_id}) do
    case Providers.get_default_model(project_id) do
      nil ->
        {:error, :not_found}

      model ->
        render(conn, :model, model: model)
    end
  end

  @doc """
  Sync providers from OpenCode server.

  POST /api/projects/:project_id/providers/sync
  """
  def sync(conn, %{"project_id" => project_id}) do
    case Providers.sync_from_opencode(project_id) do
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
  end
end
