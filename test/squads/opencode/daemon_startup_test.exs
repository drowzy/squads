defmodule Squads.OpenCode.DaemonStartupTest do
  use ExUnit.Case, async: true

  alias Squads.OpenCode.DaemonStartup

  defmodule FakeClient do
    def get_current_project(opts) do
      case opts[:base_url] do
        "http://127.0.0.1:55975" -> {:ok, %{"worktree" => "/tmp/test-project"}}
        "http://127.0.0.1:60001" -> {:ok, %{"worktree" => "/tmp/other-project"}}
        _ -> {:error, :not_found}
      end
    end

    def health(opts) do
      case opts[:base_url] do
        "http://127.0.0.1:55975" -> {:ok, %{"healthy" => true}}
        "http://127.0.0.1:60001" -> {:ok, %{"healthy" => true}}
        _ -> {:error, :unhealthy}
      end
    end
  end

  defp lsof_line(pid, port) do
    "opencode #{pid} user 10u IPv4 0x000000 0t0 TCP 127.0.0.1:#{port} (LISTEN)"
  end

  defp lsof_runner_for_port(port, output) do
    port_string = Integer.to_string(port)

    fn
      "lsof", ["-nP", "-iTCP:" <> ^port_string, "-sTCP:LISTEN"] ->
        {output, 0}

      "lsof", ["-nP", "-iTCP", "-sTCP:LISTEN"] ->
        {"", 0}

      _cmd, _args ->
        {"", 1}
    end
  end

  defp lsof_runner_for_all(output) do
    fn
      "lsof", ["-nP", "-iTCP", "-sTCP:LISTEN"] -> {output, 0}
      "lsof", ["-nP", "-iTCP:" <> _port, "-sTCP:LISTEN"] -> {"", 0}
      _cmd, _args -> {"", 1}
    end
  end

  describe "attach_to_instance/1" do
    test "attaches to instance on specified port" do
      port = 55975
      os_pid = 42_424
      project_path = "/tmp/test-project"

      opts = %{
        port: port,
        project_path: project_path,
        lsof_runner: lsof_runner_for_port(port, lsof_line(os_pid, port)),
        client: FakeClient
      }

      assert {:ok, instance} = DaemonStartup.attach_to_instance(opts)
      assert instance.port == port
      assert instance.pid == os_pid
      assert instance.url == "http://127.0.0.1:#{port}"
      assert instance.source == :lsof_port
    end

    test "discovers instance by project path when port is nil" do
      port = 60001
      os_pid = 55_555
      project_path = "/tmp/other-project"

      opts = %{
        port: nil,
        project_path: project_path,
        lsof_runner: lsof_runner_for_all(lsof_line(os_pid, port)),
        client: FakeClient
      }

      assert {:ok, instance} = DaemonStartup.attach_to_instance(opts)
      assert instance.port == port
      assert instance.pid == os_pid
      assert instance.url == "http://127.0.0.1:#{port}"
      assert instance.source == :lsof_project
    end

    test "returns error when no instance found" do
      opts = %{
        port: nil,
        project_path: "/tmp/nonexistent",
        lsof_runner: lsof_runner_for_all(""),
        client: FakeClient
      }

      assert {:error, :no_matching_instance} = DaemonStartup.attach_to_instance(opts)
    end

    test "returns error when port instance serves wrong project" do
      port = 55975
      os_pid = 42_424

      opts = %{
        port: port,
        project_path: "/tmp/different-project",
        lsof_runner: lsof_runner_for_port(port, lsof_line(os_pid, port)),
        client: FakeClient
      }

      # Should fail because FakeClient returns "/tmp/test-project" for this port
      assert {:error, :no_matching_instance} = DaemonStartup.attach_to_instance(opts)
    end
  end

  describe "find_available_port/0" do
    test "returns a valid port number" do
      port = DaemonStartup.find_available_port()
      assert is_integer(port)
      assert port > 0
      assert port < 65536
    end

    test "returns different ports on successive calls" do
      port1 = DaemonStartup.find_available_port()
      port2 = DaemonStartup.find_available_port()
      # They might rarely be the same, but usually different
      assert is_integer(port1)
      assert is_integer(port2)
    end
  end
end
