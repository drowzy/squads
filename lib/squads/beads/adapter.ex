defmodule Squads.Beads.Adapter do
  @moduledoc """
  Adapter for interacting with the `bd` (beads) CLI tool.
  """

  @bd_path "bd"

  @doc """
  Lists all issues in JSON format.
  """
  def list_issues do
    case run_cmd(["list", "--json"]) do
      {:ok, json} -> {:ok, Jason.decode!(json)}
      error -> error
    end
  end

  @doc """
  Lists ready issues in JSON format.
  """
  def ready_issues do
    case run_cmd(["ready", "--json"]) do
      {:ok, json} -> {:ok, Jason.decode!(json)}
      error -> error
    end
  end

  @doc """
  Shows details for a specific issue.
  """
  def show_issue(id) do
    case run_cmd(["show", id, "--json"]) do
      {:ok, json} -> {:ok, Jason.decode!(json)}
      error -> error
    end
  end

  @doc """
  Updates an issue's status.
  """
  def update_status(id, status) do
    case run_cmd(["update", id, "--status", to_string(status), "--json"]) do
      {:ok, json} -> {:ok, Jason.decode!(json)}
      error -> error
    end
  end

  @doc """
  Updates an issue's assignee.
  """
  def update_assignee(id, assignee) do
    case run_cmd(["update", id, "--assignee", to_string(assignee), "--json"]) do
      {:ok, json} -> {:ok, Jason.decode!(json)}
      error -> error
    end
  end

  @doc """
  Updates an issue with multiple fields.
  """
  def update_issue(id, opts) do
    args = ["update", id, "--json"]
    args = if status = opts[:status], do: args ++ ["--status", to_string(status)], else: args

    args =
      if assignee = opts[:assignee], do: args ++ ["--assignee", to_string(assignee)], else: args

    args = if priority = opts[:priority], do: args ++ ["-p", to_string(priority)], else: args

    case run_cmd(args) do
      {:ok, json} -> {:ok, Jason.decode!(json)}
      error -> error
    end
  end

  @doc """
  Closes an issue.
  """
  def close_issue(id, reason \\ nil) do
    args = ["close", id, "--json"]
    args = if reason, do: args ++ ["--reason", reason], else: args

    case run_cmd(args) do
      {:ok, json} -> {:ok, Jason.decode!(json)}
      error -> error
    end
  end

  @doc """
  Creates a new issue.
  """
  def create_issue(title, opts \\ []) do
    args = ["create", title, "--json"]
    args = if type = opts[:type], do: args ++ ["-t", to_string(type)], else: args
    args = if priority = opts[:priority], do: args ++ ["-p", to_string(priority)], else: args
    args = if parent = opts[:parent], do: args ++ ["--parent", parent], else: args

    case run_cmd(args) do
      {:ok, json} -> {:ok, Jason.decode!(json)}
      error -> error
    end
  end

  defp run_cmd(args) do
    case System.cmd(@bd_path, args) do
      {output, 0} -> {:ok, output}
      {output, _status} -> {:error, output}
    end
  end
end
