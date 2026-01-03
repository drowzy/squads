defmodule Squads.OpenCode.ProjectServerTest do
  use ExUnit.Case, async: false

  alias Squads.OpenCode.ProjectServer
  alias Squads.OpenCode.Status

  setup_all do
    case Status.start_link([]) do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
    end

    :ok
  end

  defp listen_port do
    {:ok, socket} = :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true])
    {:ok, port} = :inet.port(socket)
    {socket, port}
  end

  defp reserve_port do
    {:ok, socket} = :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true])
    {:ok, port} = :inet.port(socket)
    :ok = :gen_tcp.close(socket)
    port
  end

  test "normal exit with reachable server keeps status running" do
    {socket, port} = listen_port()
    project_path = "/tmp/opencode-status-reachable"
    Status.set(project_path, :running)

    state = %{
      project_id: "proj",
      project_path: project_path,
      url: "http://127.0.0.1:#{port}",
      status: :running,
      waiters: [],
      started_at_ms: System.monotonic_time(:millisecond)
    }

    assert {:noreply, ^state} = ProjectServer.handle_info({:EXIT, self(), :normal}, state)
    assert Status.get(project_path) == :running
    :ok = :gen_tcp.close(socket)
  end

  test "normal exit with unreachable server marks error" do
    port = reserve_port()
    project_path = "/tmp/opencode-status-unreachable"
    Status.set(project_path, :running)

    state = %{
      project_id: "proj",
      project_path: project_path,
      url: "http://127.0.0.1:#{port}",
      status: :running,
      waiters: [],
      started_at_ms: System.monotonic_time(:millisecond)
    }

    assert {:stop, :process_exited, ^state} =
             ProjectServer.handle_info({:EXIT, self(), :normal}, state)

    assert Status.get(project_path) == :error
  end

  @tag :integration
  test "opencode serve stays attached when run with pty" do
    case System.find_executable("opencode") do
      nil ->
        skip("opencode binary not available")

      _ ->
        if System.get_env("OPENCODE_INTEGRATION") != "1" do
          skip("set OPENCODE_INTEGRATION=1 to run")
        end

        Process.flag(:trap_exit, true)
        port = reserve_port()
        cmd = "opencode serve --port #{port} --hostname 127.0.0.1 --print-logs"

        {:ok, pid, os_pid} = :exec.run_link(cmd, [:stdout, :stderr, :pty])

        assert wait_for_port(port, 5_000)
        refute_receive {:EXIT, ^pid, _reason}, 2_000

        :ok = :exec.stop(os_pid)
    end
  end

  defp wait_for_port(port, timeout_ms) do
    deadline = System.monotonic_time(:millisecond) + timeout_ms
    do_wait_for_port(port, deadline)
  end

  defp do_wait_for_port(port, deadline) do
    if System.monotonic_time(:millisecond) >= deadline do
      false
    else
      case :gen_tcp.connect(~c"127.0.0.1", port, [:binary, active: false], 500) do
        {:ok, socket} ->
          :gen_tcp.close(socket)
          true

        _ ->
          Process.sleep(200)
          do_wait_for_port(port, deadline)
      end
    end
  end
end
