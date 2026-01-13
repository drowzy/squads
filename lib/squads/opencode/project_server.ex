defmodule Squads.OpenCode.ProjectServer do
  @moduledoc """
  A GenServer that manages a single project's OpenCode OS process.
  """
  use GenServer
  require Logger

  alias Squads.OpenCode.Client
  alias Squads.OpenCode.DaemonStartup
  alias Squads.OpenCode.Status

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
      client: client,
      health_check_task: nil
    }

    {:ok, state, {:continue, :start_process}}
  end

  @impl true
  def handle_continue(:start_process, state) do
    attach_opts = attach_opts(state)

    case DaemonStartup.attach_to_instance(attach_opts) do
      {:ok, instance} ->
        Logger.info(
          "OpenCode bootstrap: attaching to existing instance",
          project_id: state.project_id,
          port: instance.port,
          os_pid: instance.pid
        )

        {:noreply, mark_running(state, instance)}

      {:error, _reason} ->
        spawn_new_daemon(state)
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

  # Health check succeeded
  @impl true
  def handle_info({ref, :ok}, state) when is_reference(ref) do
    Process.demonitor(ref, [:flush])
    Logger.info("OpenCode server for project #{state.project_id} is healthy at #{state.url}")

    Logger.info(
      "OpenCode bootstrap: running for project #{state.project_id} (elapsed_ms=#{elapsed_ms(state)})"
    )

    {:noreply, mark_running(state, %{url: state.url, port: state.port, pid: state.os_pid})}
  end

  # Health check failed but we're already running (ignore)
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

  # Health check failed during startup
  @impl true
  def handle_info({ref, {:error, reason}}, state) when is_reference(ref) do
    Process.demonitor(ref, [:flush])

    Logger.error(
      "OpenCode server health check failed for project #{state.project_id}: #{inspect(reason)} (elapsed_ms=#{elapsed_ms(state)})"
    )

    try_attach_or_retry(state, reason)
  end

  # Health check task crashed
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

  # Retry attach timer fired
  @impl true
  def handle_info(:attach_retry, state) do
    try_attach(state)
  end

  # Process exited normally while running - move to idle
  @impl true
  def handle_info({:EXIT, _pid, :normal}, %{status: :running} = state) do
    Logger.debug("OpenCode process exited normally after successful start; moving to idle",
      project_id: state.project_id
    )

    Status.set(state.project_path, :idle)
    {:noreply, %{state | status: :idle, os_pid: nil}}
  end

  # Process exited normally while starting (daemon mode)
  @impl true
  def handle_info({:EXIT, _pid, :normal}, %{status: status} = state)
      when status in [:starting, :attaching] do
    Logger.debug(
      "OpenCode process exited normally (daemon mode), waiting for health check",
      project_id: state.project_id
    )

    handle_daemon_exit(state)
  end

  # Process exited with error
  @impl true
  def handle_info({:EXIT, _pid, reason}, state) do
    Logger.error(
      "OpenCode process for project #{state.project_id} exited with error: #{inspect(reason)} (elapsed_ms=#{elapsed_ms(state)})"
    )

    Status.set(state.project_path, :error)
    reply_waiters(state, {:error, :process_exited})
    {:stop, :process_exited, state}
  end

  # stdout/stderr from the process
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

  # Private helpers

  defp spawn_new_daemon(state) do
    port = DaemonStartup.find_available_port()

    Logger.info(
      "Starting OpenCode server for project #{state.project_id} at #{state.project_path} on port #{port}"
    )

    started_at_ms = System.monotonic_time(:millisecond)

    Logger.info(
      "OpenCode bootstrap: provisioning for project #{state.project_id} at #{state.project_path}"
    )

    Status.set(state.project_path, :provisioning)

    case DaemonStartup.spawn_daemon(state.project_path, port) do
      {:ok, os_pid, url} ->
        Logger.info(
          "OpenCode bootstrap: process started for project #{state.project_id} (os_pid=#{os_pid})"
        )

        health_check_task =
          Task.async(fn ->
            DaemonStartup.wait_for_healthy(url, state.project_path, state.client)
          end)

        {:noreply,
         %{
           state
           | port: port,
             url: url,
             os_pid: os_pid,
             status: :starting,
             started_at_ms: started_at_ms,
             health_check_task: health_check_task
         }}

      {:error, reason} ->
        Logger.error(
          "Failed to start OpenCode process for project #{state.project_id}: #{inspect(reason)}"
        )

        {:stop, reason, state}
    end
  end

  defp handle_daemon_exit(state) do
    case state.health_check_task do
      %Task{ref: ref} = task ->
        # Wait for health check to complete (with timeout)
        receive do
          {^ref, :ok} ->
            Process.demonitor(ref, [:flush])

            Logger.info(
              "OpenCode bootstrap: health check completed for project #{state.project_id}"
            )

            {:noreply,
             mark_running(%{state | os_pid: nil, health_check_task: nil}, %{
               url: state.url,
               port: state.port,
               pid: nil
             })}

          {^ref, {:error, reason}} ->
            Process.demonitor(ref, [:flush])

            Logger.debug(
              "OpenCode health check failed, attempting to attach",
              project_id: state.project_id,
              reason: inspect(reason)
            )

            try_attach(%{state | health_check_task: nil})

          {:DOWN, ^ref, :process, _pid, _reason} ->
            Logger.warning(
              "OpenCode health check task exited, attempting to attach",
              project_id: state.project_id
            )

            try_attach(%{state | health_check_task: nil})
        after
          10_000 ->
            # Timeout waiting for health check, cancel and try attach
            Task.shutdown(task, :brutal_kill)

            Logger.warning(
              "OpenCode health check timed out, attempting to attach",
              project_id: state.project_id
            )

            try_attach(%{state | health_check_task: nil})
        end

      nil ->
        # No health check task, try to attach directly
        Logger.debug(
          "OpenCode no health check task, attempting to attach",
          project_id: state.project_id
        )

        try_attach(state)
    end
  end

  defp try_attach(state) do
    attach_opts = attach_opts(state)

    case DaemonStartup.attach_to_instance(attach_opts) do
      {:ok, instance} ->
        {:noreply, mark_running(%{state | health_check_task: nil}, instance)}

      {:error, reason} ->
        schedule_attach_retry(state, reason)
    end
  end

  defp try_attach_or_retry(state, reason) do
    attach_opts = attach_opts(state)

    case DaemonStartup.attach_to_instance(attach_opts) do
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

  defp attach_opts(state) do
    %{
      port: state.port,
      project_path: state.project_path,
      lsof_runner: state.lsof_runner,
      client: state.client
    }
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

  defp elapsed_ms(%{started_at_ms: nil}), do: "unknown"

  defp elapsed_ms(%{started_at_ms: started_at_ms}) do
    System.monotonic_time(:millisecond) - started_at_ms
  end
end
