defmodule Squads.OpenCode.ProjectServer do
  @moduledoc """
  A GenServer that manages a single project's OpenCode OS process.
  """
  use GenServer
  require Logger

  alias Squads.OpenCode.Status

  @registry Squads.OpenCode.ServerRegistry

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

    state = %{
      project_id: project_id,
      project_path: project_path,
      port: nil,
      url: nil,
      os_pid: nil,
      status: :starting,
      waiters: [],
      started_at_ms: nil
    }

    {:ok, state, {:continue, :start_process}}
  end

  @impl true
  def handle_continue(:start_process, state) do
    port = find_available_port()
    cmd = "opencode serve --port #{port} --hostname 127.0.0.1"

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

    Status.set(state.project_path, :running)

    # Update registry with URL metadata
    Registry.update_value(@registry, state.project_id, fn _ -> state.url end)

    # Reply to all waiters
    Enum.each(state.waiters, fn from -> GenServer.reply(from, {:ok, state.url}) end)

    {:noreply, %{state | status: :running, waiters: []}}
  end

  @impl true
  def handle_info({ref, {:error, reason}}, state) when is_reference(ref) do
    Process.demonitor(ref, [:flush])

    Logger.error(
      "OpenCode server health check failed for project #{state.project_id}: #{inspect(reason)} (elapsed_ms=#{elapsed_ms(state)})"
    )

    Status.set(state.project_path, :error)

    Enum.each(state.waiters, fn from -> GenServer.reply(from, {:error, reason}) end)
    {:stop, reason, state}
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, _pid, reason}, state) do
    if reason != :normal do
      Logger.error(
        "OpenCode health check task crashed for project #{state.project_id}: #{inspect(reason)}"
      )

      Enum.each(state.waiters, fn from ->
        GenServer.reply(from, {:error, :health_check_crashed})
      end)

      {:stop, :health_check_crashed, state}
    else
      {:noreply, state}
    end
  end

  @impl true
  def handle_info({:stdout, _pid, data}, state) do
    Logger.debug("OpenCode [#{state.project_id}] stdout: #{data}")
    {:noreply, state}
  end

  @impl true
  def handle_info({:stderr, _pid, data}, state) do
    Logger.error("OpenCode [#{state.project_id}] stderr: #{data}")
    {:noreply, state}
  end

  @impl true
  def handle_info({:EXIT, _pid, reason}, state) do
    reachable = state.status == :running and server_reachable?(state.url)

    if reason == :normal and reachable do
      Logger.warning(
        "OpenCode process exited normally but server still reachable for project #{state.project_id} (elapsed_ms=#{elapsed_ms(state)})"
      )

      Logger.info("OpenCode bootstrap: instance still reachable after normal exit")
      Status.set(state.project_path, :running)

      {:noreply, state}
    else
      Logger.error(
        "OpenCode process for project #{state.project_id} exited: #{inspect(reason)} (elapsed_ms=#{elapsed_ms(state)})"
      )

      Status.set(state.project_path, :error)
      Enum.each(state.waiters, fn from -> GenServer.reply(from, {:error, :process_exited}) end)
      {:stop, :process_exited, state}
    end
  end

  # Helpers

  defp find_available_port do
    {:ok, socket} = :gen_tcp.listen(0, [])
    {:ok, port} = :inet.port(socket)
    :ok = :gen_tcp.close(socket)
    port
  end

  defp server_reachable?(url) when is_binary(url) do
    port = URI.parse(url).port

    case :gen_tcp.connect(~c"127.0.0.1", port, [:binary, active: false], 1000) do
      {:ok, socket} ->
        :gen_tcp.close(socket)
        true

      _ ->
        false
    end
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
