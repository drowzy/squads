defmodule Squads.OpenCode.DaemonStartup do
  @moduledoc """
  Handles OpenCode daemon startup, health checking, and instance discovery.

  This module encapsulates the complexity of:
  - Starting OpenCode as a daemon process
  - Waiting for the daemon to become healthy
  - Discovering and attaching to existing instances
  """

  require Logger

  alias Squads.OpenCode.Resolver

  @type instance :: %{
          url: String.t(),
          port: non_neg_integer(),
          pid: non_neg_integer() | nil,
          source: :lsof_port | :lsof_project | :port_probe
        }

  @type attach_opts :: %{
          port: non_neg_integer() | nil,
          project_path: String.t(),
          lsof_runner: (String.t(), [String.t()] -> {String.t(), non_neg_integer()}),
          client: module()
        }

  @doc """
  Attempts to attach to an existing OpenCode instance for the given project.

  First tries to find an instance on the specified port (if any), then falls
  back to discovering any instance serving the project path.

  Returns `{:ok, instance}` if found, or `{:error, reason}` otherwise.
  """
  @spec attach_to_instance(attach_opts()) :: {:ok, instance()} | {:error, term()}
  def attach_to_instance(opts) do
    port = Map.get(opts, :port)
    project_path = Map.fetch!(opts, :project_path)
    lsof_runner = Map.get(opts, :lsof_runner, &System.cmd/2)
    client = Map.get(opts, :client, Squads.OpenCode.Client)

    case resolve_instance_for_port(port, project_path, lsof_runner, client) do
      {:ok, instance} -> {:ok, instance}
      :not_found -> discover_instance_for_project(project_path, lsof_runner, client)
    end
  end

  @doc """
  Spawns an OpenCode daemon process.

  Returns `{:ok, os_pid, url}` on success, or `{:error, reason}` on failure.
  The daemon may exit immediately after spawning (daemon mode), so the caller
  should not assume the process remains alive.
  """
  @spec spawn_daemon(String.t(), non_neg_integer()) ::
          {:ok, non_neg_integer(), String.t()} | {:error, term()}
  def spawn_daemon(project_path, port) do
    cmd = "opencode serve --port #{port} --hostname 127.0.0.1 --print-logs"

    Logger.info("Starting OpenCode daemon at #{project_path} on port #{port}")

    case :exec.run_link(cmd, [:stdout, :stderr, {:cd, project_path}]) do
      {:ok, _pid, os_pid} ->
        url = url_for_port(port)
        Logger.info("OpenCode daemon spawned (os_pid=#{os_pid})")
        {:ok, os_pid, url}

      {:error, reason} ->
        Logger.error("Failed to spawn OpenCode daemon: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Waits for the OpenCode server to become healthy and serve the correct project.

  This function blocks until the server is ready (up to `retries` seconds).
  Returns `:ok` on success, or `{:error, reason}` on failure/timeout.
  """
  @spec wait_for_healthy(String.t(), String.t(), module(), non_neg_integer()) ::
          :ok | {:error, term()}
  def wait_for_healthy(url, project_path, client, retries \\ 60) do
    do_wait_for_healthy(url, project_path, client, retries, nil)
  end

  @doc """
  Finds an available port by briefly binding to port 0.
  """
  @spec find_available_port() :: non_neg_integer()
  def find_available_port do
    {:ok, socket} = :gen_tcp.listen(0, [])
    {:ok, port} = :inet.port(socket)
    :ok = :gen_tcp.close(socket)
    port
  end

  # Private functions

  defp resolve_instance_for_port(nil, _project_path, _lsof_runner, _client), do: :not_found

  defp resolve_instance_for_port(port, project_path, lsof_runner, client) when is_integer(port) do
    case resolve_opencode_listener(port, lsof_runner) do
      {:ok, listener} ->
        base_url = url_for_port(listener.port)

        case client.get_current_project(base_url: base_url, timeout: 1000, retry_count: 0) do
          {:ok, project} when is_map(project) ->
            if Resolver.project_matches?(project_path, project) do
              {:ok,
               %{
                 url: base_url,
                 port: listener.port,
                 pid: listener.pid,
                 source: :lsof_port
               }}
            else
              :not_found
            end

          _ ->
            :not_found
        end

      :not_found ->
        probe_instance_for_port(port, project_path, client)
    end
  end

  defp probe_instance_for_port(port, project_path, client) when is_integer(port) do
    base_url = url_for_port(port)

    case client.get_current_project(base_url: base_url, timeout: 1000, retry_count: 0) do
      {:ok, project} when is_map(project) ->
        if Resolver.project_matches?(project_path, project) do
          {:ok,
           %{
             url: base_url,
             port: port,
             pid: nil,
             source: :port_probe
           }}
        else
          :not_found
        end

      _ ->
        :not_found
    end
  end

  defp resolve_opencode_listener(port, lsof_runner) when is_integer(port) do
    case lsof_runner.("lsof", ["-nP", "-iTCP:#{port}", "-sTCP:LISTEN"]) do
      {output, 0} ->
        output
        |> String.split("\n", trim: true)
        |> Enum.filter(&String.contains?(&1, "opencode"))
        |> Enum.find_value(&Resolver.parse_lsof_listener/1)
        |> case do
          nil -> :not_found
          listener -> {:ok, listener}
        end

      _ ->
        :not_found
    end
  rescue
    _ -> :not_found
  end

  defp discover_instance_for_project(project_path, lsof_runner, client)
       when is_binary(project_path) do
    instance =
      Resolver.list_local_listeners(lsof_runner)
      |> Enum.find_value(fn %{port: port, pid: pid} ->
        base_url = url_for_port(port)

        case client.get_current_project(base_url: base_url, timeout: 1000, retry_count: 0) do
          {:ok, project} when is_map(project) ->
            if Resolver.project_matches?(project_path, project) do
              %{
                url: base_url,
                port: port,
                pid: pid,
                source: :lsof_project
              }
            end

          _ ->
            nil
        end
      end)

    case instance do
      nil -> {:error, :no_matching_instance}
      _ -> {:ok, instance}
    end
  end

  defp do_wait_for_healthy(_url, _project_path, _client, 0, last_error),
    do: {:error, {:timeout, last_error}}

  defp do_wait_for_healthy(url, project_path, client, retries, last_error) do
    port = URI.parse(url).port

    {ready?, new_last_error} =
      case :gen_tcp.connect(~c"127.0.0.1", port, [:binary, active: false], 1000) do
        {:ok, socket} ->
          :gen_tcp.close(socket)

          case client.health(base_url: url, timeout: 1000, retry_count: 0) do
            {:ok, %{"healthy" => true}} ->
              case client.get_current_project(base_url: url, timeout: 1000, retry_count: 0) do
                {:ok, project} when is_map(project) ->
                  if Resolver.project_matches?(project_path, project) do
                    {true, nil}
                  else
                    {false, :wrong_project}
                  end

                other ->
                  {false, {:project_not_ready, other}}
              end

            other ->
              {false, {:unhealthy, other}}
          end

        other ->
          {false, {:port_not_ready, other}}
      end

    last_error = if ready?, do: last_error, else: new_last_error

    if ready? do
      :ok
    else
      if retries in [60, 30, 10, 5, 1] do
        Logger.debug(
          "OpenCode: waiting for health at #{url} (retries=#{retries}, last_error=#{inspect(last_error)})"
        )
      end

      Process.sleep(1000)
      do_wait_for_healthy(url, project_path, client, retries - 1, last_error)
    end
  end

  defp url_for_port(port) when is_integer(port) do
    "http://127.0.0.1:#{port}"
  end
end
