defmodule Squads.MCP.DockerCLI do
  @moduledoc """
  Wrapper around the Docker MCP CLI.
  """

  @cli_path Application.compile_env(:squads, [__MODULE__, :cli_path], "docker")

  def catalog_show do
    run_cmd(["mcp", "catalog", "show", "docker-mcp"])
  end

  def available? do
    try do
      {output, status} = System.cmd(@cli_path, ["mcp", "--help"], stderr_to_stdout: true)
      trimmed = String.trim(output)

      if status == 0 do
        {:ok, true}
      else
        {:ok, false, trimmed}
      end
    rescue
      error -> {:ok, false, Exception.message(error)}
    end
  end

  def server_enable(name) do
    run_cmd(["mcp", "server", "enable", name])
  end

  def server_disable(name) do
    run_cmd(["mcp", "server", "disable", name])
  end

  def server_ls do
    run_cmd(["mcp", "server", "ls"])
  end

  def server_inspect(name) do
    run_cmd(["mcp", "server", "inspect", name])
  end

  def oauth_authorize(provider) do
    run_cmd(["mcp", "oauth", "authorize", provider])
  end

  def oauth_ls do
    run_cmd(["mcp", "oauth", "ls"])
  end

  def oauth_revoke(provider) do
    run_cmd(["mcp", "oauth", "revoke", provider])
  end

  def tools_ls do
    run_json_cmd(["mcp", "tools", "ls", "--format=json"])
  end

  defp run_json_cmd(args) do
    with {:ok, output} <- run_cmd(args) do
      decode_json(output)
    end
  end

  defp decode_json(output) do
    case Jason.decode(output) do
      {:ok, decoded} -> {:ok, decoded}
      {:error, _reason} -> {:error, {:invalid_json, output}}
    end
  end

  defp run_cmd(args) do
    {output, status} = System.cmd(@cli_path, args, stderr_to_stdout: true)
    trimmed = String.trim(output)

    if status == 0 do
      {:ok, trimmed}
    else
      {:error, {:command_failed, trimmed}}
    end
  end
end
