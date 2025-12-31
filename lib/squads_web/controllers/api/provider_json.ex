defmodule SquadsWeb.API.ProviderJSON do
  @moduledoc """
  JSON rendering for providers.
  """

  alias Squads.Providers.Provider

  @doc """
  Renders a list of providers.
  """
  def index(%{providers: providers}) do
    %{data: for(provider <- providers, do: data(provider))}
  end

  @doc """
  Renders a single provider.
  """
  def show(%{provider: provider}) do
    %{data: data(provider)}
  end

  @doc """
  Renders a list of models.
  """
  def models(%{models: models}) do
    %{data: models}
  end

  @doc """
  Renders a single model.
  """
  def model(%{model: model}) do
    %{data: model}
  end

  defp data(%Provider{} = provider) do
    %{
      id: provider.id,
      provider_id: provider.provider_id,
      name: provider.name,
      status: provider.status,
      last_checked_at: provider.last_checked_at,
      models: provider.models,
      default_model: provider.default_model,
      inserted_at: provider.inserted_at,
      updated_at: provider.updated_at
    }
  end
end
