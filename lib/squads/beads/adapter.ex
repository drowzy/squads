defmodule Squads.Beads.Adapter do
  @moduledoc """
  Adapter for interacting with the `bd` (beads) CLI tool.
  """

  @bd_path "bd"

  @doc """
  Lists all issues in JSON format.
  """
  def list_issues(path) do
    case run_cmd(path, ["list", "--json"]) do
      {:ok, json} -> {:ok, Jason.decode!(json)}
      error -> error
    end
  end

  @doc """
  Lists ready issues in JSON format.
  """
  def ready_issues(path) do
    case run_cmd(path, ["ready", "--json"]) do
      {:ok, json} -> {:ok, Jason.decode!(json)}
      error -> error
    end
  end

  @doc """
  Shows details for a specific issue.
  """
  def show_issue(path, id) do
    case run_cmd(path, ["show", id, "--json"]) do
      {:ok, json} -> {:ok, Jason.decode!(json)}
      error -> error
    end
  end

  @doc """
  Updates an issue's status.
  """
  def update_status(path, id, status) do
    case run_cmd(path, ["update", id, "--status", to_string(status), "--json"]) do
      {:ok, json} -> {:ok, Jason.decode!(json)}
      error -> error
    end
  end

  @doc """
  Updates an issue's assignee.
  """
  def update_assignee(path, id, assignee) do
    case run_cmd(path, ["update", id, "--assignee", to_string(assignee), "--json"]) do
      {:ok, json} -> {:ok, Jason.decode!(json)}
      error -> error
    end
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

    case run_cmd(path, args) do
      {:ok, json} -> {:ok, Jason.decode!(json)}
      error -> error
    end
  end

  @doc """
  Closes an issue.
  """
  def close_issue(path, id, reason \\ nil) do
    args = ["close", id, "--json"]
    args = if reason, do: args ++ ["--reason", reason], else: args

    case run_cmd(path, args) do
      {:ok, json} -> {:ok, Jason.decode!(json)}
      error -> error
    end
  end

  @doc """
  Creates a new issue.
  """
  def create_issue(path, title, opts \\ []) do
    args = ["create", title, "--json"]
    args = if type = opts[:type], do: args ++ ["-t", to_string(type)], else: args
    args = if priority = opts[:priority], do: args ++ ["-p", to_string(priority)], else: args
    args = if parent = opts[:parent], do: args ++ ["--parent", parent], else: args

    case run_cmd(path, args) do
      {:ok, json} -> {:ok, Jason.decode!(json)}
      error -> error
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
