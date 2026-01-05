defmodule Squads.OpenCode.ProjectServer do
  @moduledoc """
  A GenServer that manages a single project's OpenCode OS process.
  """
  use GenServer
  require Logger

  alias Squads.OpenCode.Client
  alias Squads.OpenCode.Status
  alias Squads.OpenCode.Resolver

  @registry Squads.OpenCode.ServerRegistry

  @attach_retry_delay_ms 1_000
  @attach_retry_limit 5

  def start_link(opts) do
    project_id = Keyword.fetch!(opts, :project_id)
    name = {:via, Registry, {@registry, project_id}}
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  def ensure_running(pid) do
    GenServer.call(pid, :ensure_running, 70_000)
  end

  # Callbacks

  @impl true
  def init(opts) do
    Process.flag(:trap_exit, true)
    project_id = Keyword.fetch!(opts, :project_id)
    project_path = Keyword.fetch!(opts, :project_path)

    lsof_runner = Keyword.get(opts, :lsof_runner, &System.cmd/2)
    client = Keyword.get(opts, :client, Client)

    state = %{
      project_id: project_id,
      project_path: project_path,
      port: nil,
      url: nil,
      os_pid: nil,
      status: :starting,
      waiters: [],
      started_at_ms: nil,
      attach_attempts: 0,
      lsof_runner: lsof_runner,
      client: client
    }

    {:ok, state, {:continue, :start_process}}
  end

  @impl true
  def handle_continue(:start_process, state) do
    case attach_to_local_instance(state) do
      {:ok, instance} ->
        Logger.info(
          "OpenCode bootstrap: attaching to existing instance",
          project_id: state.project_id,
          port: instance.port,
          os_pid: instance.pid
        )

        {:noreply, mark_running(state, instance)}

      {:error, _reason} ->
        port = find_available_port()
        cmd = "opencode serve --port #{port} --hostname 127.0.0.1 --print-logs"

        Logger.info(
          "Starting OpenCode server for project #{state.project_id} at #{state.project_path} on port #{port}"
        )

        started_at_ms = System.monotonic_time(:millisecond)

        Logger.info(
          "OpenCode bootstrap: provisioning for project #{state.project_id} at #{state.project_path}"
        )

        Status.set(state.project_path, :provisioning)

        case :exec.run_link(cmd, [:stdout, :stderr, :pty, {:cd, state.project_path}]) do
          {:ok, _pid, os_pid} ->
            url = "http://127.0.0.1:#{port}"

            Logger.info(
              "OpenCode bootstrap: process started for project #{state.project_id} (os_pid=#{os_pid})"
            )

            # Start health check
            _task = Task.async(fn -> wait_for_healthy(url) end)

            {:noreply,
             %{
               state
               | port: port,
                 url: url,
                 os_pid: os_pid,
                 status: :starting,
                 started_at_ms: started_at_ms
             }}

          {:error, reason} ->
            Logger.error(
              "Failed to start OpenCode process for project #{state.project_id}: #{inspect(reason)}"
            )

            {:stop, reason, state}
        end
    end
  end

  @impl true
  def handle_call(:ensure_running, _from, %{status: :running, url: url} = state) do
    {:reply, {:ok, url}, state}
  end

  @impl true
  def handle_call(:ensure_running, from, %{status: :starting} = state) do
    {:noreply, %{state | waiters: [from | state.waiters]}}
  end

  @impl true
  def handle_info({ref, :ok}, state) when is_reference(ref) do
    Process.demonitor(ref, [:flush])
    Logger.info("OpenCode server for project #{state.project_id} is healthy at #{state.url}")

    Logger.info(
      "OpenCode bootstrap: running for project #{state.project_id} (elapsed_ms=#{elapsed_ms(state)})"
    )

    {:noreply, mark_running(state, %{url: state.url, port: state.port, pid: state.os_pid})}
  end

  @impl true
  def handle_info({ref, {:error, reason}}, %{status: :running} = state) when is_reference(ref) do
    Process.demonitor(ref, [:flush])

    Logger.debug(
      "OpenCode health check failed after attach; ignoring",
      project_id: state.project_id,
      reason: inspect(reason)
    )

    {:noreply, state}
  end

  @impl true
  def handle_info({ref, {:error, reason}}, state) when is_reference(ref) do
    Process.demonitor(ref, [:flush])

    Logger.error(
      "OpenCode server health check failed for project #{state.project_id}: #{inspect(reason)} (elapsed_ms=#{elapsed_ms(state)})"
    )

    case attach_to_local_instance(state) do
      {:ok, instance} ->
        Logger.warning(
          "OpenCode bootstrap: attaching to existing instance after health check failure",
          project_id: state.project_id,
          port: instance.port,
          os_pid: instance.pid
        )

        {:noreply, mark_running(state, instance)}

      {:error, attach_reason} ->
        Logger.error(
          "OpenCode bootstrap: failed to attach after health check failure",
          project_id: state.project_id,
          reason: inspect(attach_reason)
        )

        Status.set(state.project_path, :error)
        reply_waiters(state, {:error, reason})
        {:stop, reason, state}
    end
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, _pid, reason}, state) do
    if reason != :normal do
      Logger.error(
        "OpenCode health check task crashed for project #{state.project_id}: #{inspect(reason)}"
      )

      reply_waiters(state, {:error, :health_check_crashed})

      {:stop, :health_check_crashed, state}
    else
      {:noreply, state}
    end
  end

  @impl true
  def handle_info(:attach_retry, state) do
    case attach_to_local_instance(state) do
      {:ok, instance} ->
        Logger.info(
          "OpenCode attach retry succeeded",
          project_id: state.project_id,
          port: instance.port,
          os_pid: instance.pid
        )

        {:noreply, mark_running(state, instance)}

      {:error, attach_reason} ->
        schedule_attach_retry(state, attach_reason)
    end
  end

  @impl true
  def handle_info({:stdout, _pid, data}, state) do
    if state.status in [:starting, :attaching] do
      Logger.info("OpenCode [#{state.project_id}] stdout: #{data}")
    else
      Logger.debug("OpenCode [#{state.project_id}] stdout: #{data}")
    end

    {:noreply, state}
  end

  @impl true
  def handle_info({:stderr, _pid, data}, state) do
    log_stderr(state.project_id, data, state.status in [:starting, :attaching])
    {:noreply, state}
  end

  @impl true
  def handle_info({:EXIT, _pid, :normal}, %{status: :running} = state) do
    Logger.debug("OpenCode process exited normally after successful start; moving to idle",
      project_id: state.project_id
    )

    Status.set(state.project_path, :idle)
    {:noreply, %{state | status: :idle, os_pid: nil}}
  end

  @impl true
  def handle_info({:EXIT, _pid, reason}, state) do
    if reason == :normal do
      case attach_to_local_instance(state) do
        {:ok, instance} ->
          Logger.warning(
            "OpenCode process exited normally during startup; attaching to existing instance",
            project_id: state.project_id,
            port: instance.port,
            os_pid: instance.pid
          )

          Logger.info(
            "OpenCode bootstrap: running for project #{state.project_id} (elapsed_ms=#{elapsed_ms(state)})"
          )

          {:noreply, mark_running(state, instance)}

        {:error, attach_reason} ->
          case schedule_attach_retry(state, attach_reason) do
            {:noreply, updated_state} -> {:noreply, updated_state}
            {:stop, stop_reason, updated_state} -> {:stop, stop_reason, updated_state}
          end
      end
    else
      Logger.error(
        "OpenCode process for project #{state.project_id} exited with error: #{inspect(reason)} (elapsed_ms=#{elapsed_ms(state)})"
      )

      Status.set(state.project_path, :error)
      reply_waiters(state, {:error, :process_exited})
      {:stop, :process_exited, state}
    end
  end

  @impl true
  def terminate(reason, state) do
    if state.os_pid do
      Logger.info(
        "Stopping OpenCode server for project #{state.project_id} (os_pid=#{state.os_pid})",
        reason: inspect(reason)
      )

      :exec.stop(state.os_pid)
    end

    status =
      case reason do
        :normal -> :idle
        :shutdown -> :idle
        {:shutdown, _} -> :idle
        _ -> :error
      end

    Status.set(state.project_path, status)

    :ok
  end

  # Helpers

  defp find_available_port do
    {:ok, socket} = :gen_tcp.listen(0, [])
    {:ok, port} = :inet.port(socket)
    :ok = :gen_tcp.close(socket)
    port
  end

  defp mark_running(state, %{url: url, port: port, pid: os_pid}) do
    Status.set(state.project_path, :running)

    # Update registry with URL metadata
    Registry.update_value(@registry, state.project_id, fn _ -> url end)

    reply_waiters(state, {:ok, url})

    %{
      state
      | status: :running,
        waiters: [],
        url: url,
        port: port,
        os_pid: os_pid,
        attach_attempts: 0
    }
  end

  defp reply_waiters(state, reply) do
    Enum.each(state.waiters, fn from -> GenServer.reply(from, reply) end)
  end

  defp schedule_attach_retry(state, reason) do
    if state.status in [:starting, :attaching] and state.attach_attempts < @attach_retry_limit do
      attempt = state.attach_attempts + 1

      Logger.warning(
        "OpenCode attach attempt #{attempt} failed; retrying",
        project_id: state.project_id,
        reason: inspect(reason)
      )

      Process.send_after(self(), :attach_retry, @attach_retry_delay_ms)
      {:noreply, %{state | status: :attaching, attach_attempts: attempt}}
    else
      Logger.error(
        "OpenCode process exited normally but no attachable instance found",
        project_id: state.project_id,
        reason: inspect(reason)
      )

      Status.set(state.project_path, :error)
      reply_waiters(state, {:error, :process_exited})
      {:stop, :process_exited, state}
    end
  end

  defp log_stderr(project_id, data, startup?) when is_binary(data) do
    data
    |> String.split("\n", trim: true)
    |> Enum.each(fn line ->
      message = "OpenCode [#{project_id}] stderr: #{line}"

      cond do
        String.starts_with?(line, "ERROR") -> Logger.error(message)
        String.starts_with?(line, "WARN") -> Logger.warning(message)
        String.starts_with?(line, "WARNING") -> Logger.warning(message)
        startup? -> Logger.info(message)
        String.starts_with?(line, "INFO") -> Logger.debug(message)
        true -> Logger.debug(message)
      end
    end)
  end

  defp log_stderr(project_id, data, _startup?) do
    Logger.debug("OpenCode [#{project_id}] stderr: #{inspect(data)}")
  end

  defp attach_to_local_instance(state) do
    lsof_runner = Map.get(state, :lsof_runner, &System.cmd/2)
    client = Map.get(state, :client, Client)

    case resolve_instance_for_port(state.port, state.project_path, lsof_runner, client) do
      {:ok, instance} -> {:ok, instance}
      :not_found -> discover_instance_for_project(state.project_path, lsof_runner, client)
    end
  end

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

  defp url_for_port(port) when is_integer(port) do
    "http://127.0.0.1:#{port}"
  end

  defp elapsed_ms(%{started_at_ms: nil}), do: "unknown"

  defp elapsed_ms(%{started_at_ms: started_at_ms}) do
    System.monotonic_time(:millisecond) - started_at_ms
  end

  defp wait_for_healthy(url, retries \\ 60)
  defp wait_for_healthy(_url, 0), do: {:error, :timeout}

  defp wait_for_healthy(url, retries) do
    port = URI.parse(url).port

    case :gen_tcp.connect(~c"127.0.0.1", port, [:binary, active: false], 1000) do
      {:ok, socket} ->
        :gen_tcp.close(socket)
        :ok

      _ ->
        if retries in [60, 30, 10, 5, 1] do
          Logger.debug("OpenCode bootstrap: waiting for health at #{url} (retries=#{retries})")
        end

        Process.sleep(1000)
        wait_for_healthy(url, retries - 1)
    end
  end
end
