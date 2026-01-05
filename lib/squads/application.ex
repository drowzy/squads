defmodule Squads.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      SquadsWeb.Telemetry,
      Squads.Repo,
      {Ecto.Migrator,
       repos: Application.fetch_env!(:squads, :ecto_repos), skip: skip_migrations?()},
      {DNSCluster, query: Application.get_env(:squads, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Squads.PubSub},
      {Registry, keys: :unique, name: Squads.OpenCode.ServerRegistry},
      {DynamicSupervisor, strategy: :one_for_one, name: Squads.OpenCode.ProjectSupervisor},
      {Task.Supervisor, name: Squads.OpenCode.TaskSupervisor},
      {Squads.OpenCode.Status, []},
      # Squads.OpenCode.Server is now a plain module facade
      # SquadsWeb.Endpoint must be started last
      SquadsWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Squads.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    SquadsWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  defp skip_migrations?() do
    # By default, sqlite migrations are run when using a release
    System.get_env("RELEASE_NAME") == nil
  end
end
