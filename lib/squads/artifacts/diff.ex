defmodule Squads.Artifacts.Diff do
  @moduledoc false

  @type error_reason :: String.t()

  @spec git_patch(String.t(), String.t(), String.t()) ::
          {:ok, String.t()} | {:error, error_reason()}
  def git_patch(worktree_path, base_sha, head_sha)
      when is_binary(worktree_path) and is_binary(base_sha) and is_binary(head_sha) do
    cond do
      worktree_path == "" ->
        {:error, "missing_worktree_path"}

      base_sha == "" or head_sha == "" ->
        {:error, "missing_base_or_head_sha"}

      not File.dir?(worktree_path) ->
        {:error, "worktree_path_not_found"}

      true ->
        run_git_ok(worktree_path, ["diff", "--patch", "#{base_sha}...#{head_sha}"])
    end
  end

  @spec worktree_patch(String.t()) :: {:ok, String.t()} | {:error, error_reason()}
  def worktree_patch(worktree_path) when is_binary(worktree_path) do
    cond do
      worktree_path == "" ->
        {:error, "missing_worktree_path"}

      not File.dir?(worktree_path) ->
        {:error, "worktree_path_not_found"}

      true ->
        with {:ok, tracked_diff} <- tracked_worktree_patch(worktree_path),
             {:ok, untracked_diff} <- untracked_worktree_patch(worktree_path) do
          diff =
            [String.trim_trailing(tracked_diff), String.trim_trailing(untracked_diff)]
            |> Enum.reject(&(&1 == ""))
            |> Enum.join("\n")

          {:ok, if(diff == "", do: "", else: diff <> "\n")}
        end
    end
  end

  defp tracked_worktree_patch(worktree_path) do
    if head_exists?(worktree_path) do
      # Includes staged + unstaged changes relative to HEAD.
      run_git_ok(worktree_path, ["diff", "--patch", "HEAD"])
    else
      # No commits yet (or HEAD missing). Fall back to staged + unstaged diffs.
      with {:ok, unstaged} <- run_git_ok(worktree_path, ["diff", "--patch"]),
           {:ok, staged} <- run_git_ok(worktree_path, ["diff", "--patch", "--cached"]) do
        diff =
          [String.trim_trailing(staged), String.trim_trailing(unstaged)]
          |> Enum.reject(&(&1 == ""))
          |> Enum.join("\n")

        {:ok, if(diff == "", do: "", else: diff <> "\n")}
      end
    end
  end

  defp untracked_worktree_patch(worktree_path) do
    case run_git_ok(worktree_path, ["ls-files", "--others", "--exclude-standard"]) do
      {:ok, output} ->
        paths =
          output
          |> String.split("\n", trim: true)

        patch =
          paths
          |> Enum.reduce("", fn path, acc ->
            case untracked_file_patch(worktree_path, path) do
              {:ok, ""} -> acc
              {:ok, patch} -> acc <> patch
              {:error, _reason} -> acc
            end
          end)

        {:ok, patch}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp untracked_file_patch(worktree_path, path) when is_binary(path) do
    if path == "" do
      {:ok, ""}
    else
      abs_path = Path.join(worktree_path, path)

      cond do
        not File.regular?(abs_path) ->
          {:ok, ""}

        true ->
          # `git diff --no-index` often exits with 1 when differences exist.
          run_git_allow_status(
            worktree_path,
            ["diff", "--no-index", "--patch", "--", "/dev/null", path],
            [0, 1]
          )
      end
    end
  end

  defp head_exists?(worktree_path) do
    {_output, status} =
      System.cmd(
        "git",
        ["rev-parse", "--verify", "HEAD"],
        cd: worktree_path,
        stderr_to_stdout: true
      )

    status == 0
  end

  defp run_git_ok(worktree_path, args) when is_list(args) do
    run_git_allow_status(worktree_path, args, [0])
  end

  defp run_git_allow_status(worktree_path, args, ok_statuses)
       when is_list(args) and is_list(ok_statuses) do
    {output, status} =
      System.cmd(
        "git",
        args,
        cd: worktree_path,
        stderr_to_stdout: true
      )

    if status in ok_statuses do
      {:ok, output}
    else
      {:error, String.trim(output)}
    end
  end
end
