defmodule Squads.OpenCode.Status do
  @moduledoc """
  In-memory status store for OpenCode instances keyed by project path.
  """

  use GenServer

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

  def fetch(project_path) when is_binary(project_path) do
    case :ets.lookup(@table, project_path) do
      [{^project_path, status}] -> {:ok, status}
      [] -> :error
    end
  end

  def get(project_path) when is_binary(project_path) do
    case fetch(project_path) do
      {:ok, status} -> status
      :error -> :provisioning
    end
  end

  def set(project_path, status) when is_binary(project_path) and status in @valid_statuses do
    :ets.insert(@table, {project_path, status})
    :ok
  end

  def clear(project_path) when is_binary(project_path) do
    :ets.delete(@table, project_path)
    :ok
  end
end
