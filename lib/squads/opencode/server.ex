defmodule Squads.OpenCode.Server do
  @moduledoc """
  Manages project-specific OpenCode server instances.
  """
  use GenServer
  require Logger

  alias Squads.Repo
  # alias Squads.Projects

  @registry Squads.OpenCode.ServerRegistry

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: Squads.OpenCode.Server)
  end

  @doc """
  Lists all currently running projects and their URLs.
  """
  def list_running_servers do
    GenServer.call(__MODULE__, :list_running_servers)
  end

  @doc """
  Ensures an OpenCode server is running for the given project.
  Returns {:ok, base_url} or {:error, reason}.
  """
  def ensure_running(project_id, project_path \\ nil) do
    GenServer.call(__MODULE__, {:ensure_running, project_id, project_path}, 120_000)
  end

  @doc """
  Gets the base URL for a running project server.
  """
  def get_url(project_id) do
    case Registry.lookup(@registry, project_id) do
      [{_pid, url}] -> {:ok, url}
      [] -> {:error, :not_running}
    end
  end

  # Callbacks

  @impl true
  def init(_opts) do
    Process.flag(:trap_exit, true)

    {:ok, %{servers: %{}}}
  end

  @impl true
  def handle_call(:list_running_servers, _from, state) do
    {:reply, state.servers, state}
  end

  @impl true
  def handle_call({:ensure_running, project_id, project_path}, _from, state) do
    case get_url(project_id) do
      {:ok, url} ->
        {:reply, {:ok, url}, state}

      {:error, :not_running} ->
        path = project_path || get_project_path(project_id)

        case start_project_server(project_id, path) do
          {:ok, url, pid} ->
            {:ok, _} = Registry.register(@registry, project_id, url)
            {:reply, {:ok, url}, put_in(state.servers[project_id], %{url: url, pid: pid})}

          {:error, reason} ->
            {:reply, {:error, reason}, state}
        end
    end
  end

  @impl true
  def handle_info({:stdout, _pid, data}, state) do
    Logger.debug("OpenCode stdout: #{data}")
    {:noreply, state}
  end

  @impl true
  def handle_info({:stderr, _pid, data}, state) do
    Logger.error("OpenCode stderr: #{data}")
    {:noreply, state}
  end

  @impl true
  def handle_info({:EXIT, pid, reason}, state) do
    Logger.error("OpenCode process exited: #{inspect(reason)}")

    # Find which project this was
    project_id =
      Enum.find_value(state.servers, fn {id, info} ->
        case info.pid do
          {_res, ^pid, _os_pid} -> id
          _ -> nil
        end
      end)

    if project_id do
      Logger.info("Cleaning up OpenCode server for project #{project_id}")
      Registry.unregister(@registry, project_id)
      {:noreply, update_in(state.servers, &Map.delete(&1, project_id))}
    else
      {:noreply, state}
    end
  end

  defp get_project_path(project_id) do
    Repo.get!(Squads.Projects.Project, project_id).path
  end

  defp start_project_server(_project_id, path) do
    # We use port 0 to let OS assign a random port.
    # However, OpenCode serve might not output the port in a machine-readable way easily
    # or it might take some time to boot.
    # For now, let's try to find an available port first or just use a range.
    port = find_available_port()

    cmd = "opencode serve --port #{port} --hostname 127.0.0.1"

    Logger.info("Starting OpenCode server for project at #{path} on port #{port}")

    case :exec.run_link(cmd, [:stdout, :stderr, {:cd, path}]) do
      {:ok, _pid, _os_pid} = result ->
        url = "http://127.0.0.1:#{port}"
        # Wait a bit for server to be ready
        case wait_for_healthy(url) do
          :ok -> {:ok, url, result}
          {:error, reason} -> {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp find_available_port do
    {:ok, socket} = :gen_tcp.listen(0, [])
    {:ok, port} = :inet.port(socket)
    :ok = :gen_tcp.close(socket)
    port
  end

  defp wait_for_healthy(url, retries \\ 60)
  defp wait_for_healthy(_url, 0), do: {:error, :timeout}

  defp wait_for_healthy(url, retries) do
    # Just check if the port is open as a fallback
    port = URI.parse(url).port

    case :gen_tcp.connect(~c"127.0.0.1", port, [:binary, active: false], 1000) do
      {:ok, socket} ->
        :gen_tcp.close(socket)
        :ok

      _ ->
        Process.sleep(1000)
        wait_for_healthy(url, retries - 1)
    end
  end
end
