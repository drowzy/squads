defmodule Squads.Beads.Adapter do
  @moduledoc """
  Adapter for interacting with the `bd` (beads) CLI tool.
  """

  @bd_path "bd"

  @doc """
  Lists all issues in JSON format.
  """
  def list_issues(path) do
    run_json_cmd(path, ["list", "--json"])
  end

  @doc """
  Lists ready issues in JSON format.
  """
  def ready_issues(path) do
    run_json_cmd(path, ["ready", "--json"])
  end

  @doc """
  Shows details for a specific issue.
  """
  def show_issue(path, id) do
    run_json_cmd(path, ["show", id, "--json"])
  end

  @doc """
  Updates an issue's status.
  """
  def update_status(path, id, status) do
    run_json_cmd(path, ["update", id, "--status", to_string(status), "--json"])
  end

  @doc """
  Updates an issue's assignee.
  """
  def update_assignee(path, id, assignee) do
    run_json_cmd(path, ["update", id, "--assignee", to_string(assignee), "--json"])
  end

  @doc """
  Updates an issue with multiple fields.
  """
  def update_issue(path, id, opts) do
    args = ["update", id, "--json"]
    args = if status = opts[:status], do: args ++ ["--status", to_string(status)], else: args

    args =
      if assignee = opts[:assignee], do: args ++ ["--assignee", to_string(assignee)], else: args

    args = if priority = opts[:priority], do: args ++ ["-p", to_string(priority)], else: args

    run_json_cmd(path, args)
  end

  @doc """
  Closes an issue.
  """
  def close_issue(path, id, reason \\ nil) do
    args = ["close", id, "--json"]
    args = if reason, do: args ++ ["--reason", reason], else: args

    run_json_cmd(path, args)
  end

  @doc """
  Creates a new issue.
  """
  def create_issue(path, title, opts \\ []) do
    args = ["create", title, "--json"]
    args = if type = opts[:type], do: args ++ ["-t", to_string(type)], else: args
    args = if priority = opts[:priority], do: args ++ ["-p", to_string(priority)], else: args
    args = if parent = opts[:parent], do: args ++ ["--parent", parent], else: args

    run_json_cmd(path, args)
  end

  defp run_json_cmd(path, args) do
    case run_cmd(path, args) do
      {:ok, output} -> decode_json(output)
      error -> error
    end
  end

  defp decode_json(output) do
    case Jason.decode(output) do
      {:ok, decoded} -> {:ok, decoded}
      {:error, _reason} -> {:error, {:invalid_json, output}}
    end
  end

  defp run_cmd(path, args) do
    # Implicitly relies on the .beads directory existing or the command failing gracefully.
    # Catches the "no beads database found" error to provide a specific error return.
    case System.cmd(@bd_path, args, cd: path, stderr_to_stdout: true) do
      {output, 0} ->
        {:ok, output}

      {output, _status} ->
        if String.contains?(output, "no beads database found") do
          # We return a specific error here to allow the caller to decide on auto-initialization or other handling.
          {:error, :no_beads_db}
        else
          {:error, output}
        end
    end
  end
end
