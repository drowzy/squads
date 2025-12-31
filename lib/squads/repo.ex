defmodule Squads.Repo do
  use Ecto.Repo,
    otp_app: :squads,
    adapter: Ecto.Adapters.SQLite3

  @impl true
  def before_connect(_opts) do
    {:ok, []}
  end

  @impl true
  def after_connect(_result, _opts) do
    :ok
  end
end
