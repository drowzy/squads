defmodule Squads.OpenCode.Status do
  @moduledoc """
  In-memory status store for OpenCode instances keyed by normalized project path.
  """
  use GenServer
  alias Squads.OpenCode.Resolver

  @table __MODULE__
  @valid_statuses [:idle, :provisioning, :running, :error]

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    :ets.new(@table, [
      :named_table,
      :public,
      :set,
      read_concurrency: true,
      write_concurrency: true
    ])

    {:ok, %{}}
  end

  @doc """
  Fetches the status for a project path.
  Normalizes the path before lookup.
  """
  def fetch(project_path) when is_binary(project_path) do
    path = Resolver.canonicalize_path(project_path)

    case :ets.lookup(@table, path) do
      [{^path, status}] -> {:ok, status}
      [] -> :error
    end
  end

  @doc """
  Gets the status for a project path, defaulting to :idle if not found.
  """
  def get(project_path) when is_binary(project_path) do
    case fetch(project_path) do
      {:ok, status} -> status
      :error -> :idle
    end
  end

  @doc """
  Sets the status for a project path.
  Normalizes the path before insertion.
  """
  def set(project_path, status) when is_binary(project_path) and status in @valid_statuses do
    path = Resolver.canonicalize_path(project_path)
    :ets.insert(@table, {path, status})
    :ok
  end

  @doc """
  Clears the status for a project path.
  """
  def clear(project_path) when is_binary(project_path) do
    path = Resolver.canonicalize_path(project_path)
    :ets.delete(@table, path)
    :ok
  end

  @doc """
  Returns all tracked statuses.
  """
  def list_all do
    :ets.tab2list(@table)
  end
end
