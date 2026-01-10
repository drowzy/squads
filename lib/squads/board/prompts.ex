defmodule Squads.Board.Prompts do
  @moduledoc false

  def plan_prompt(opts) do
    squad_name = opts[:squad_name] || "(unknown squad)"
    card_body = opts[:card_body] || ""
    prd_path = opts[:prd_path] || ""
    github_repo = opts[:github_repo] || ""

    """
    You are the PLAN agent for squad #{squad_name}. Your job is to turn the build request into a PRD and an issue plan.

    Build request:
    #{card_body}

    Constraints:
    - Write the PRD to: #{prd_path} (this path is reserved; do not change it).
    - Keep scope crisp; prefer smallest shippable increment.
    - Ask clarifying questions for anything non-obvious before locking the PRD.
    - After the PRD, propose GitHub issues (do not create them yet).

    Output requirements:
    1) Create/update #{prd_path} as Markdown.
    2) Then output an ISSUE_PLAN block in JSON exactly like:

    ```json
    {
      "repo": "#{github_repo}",
      "prd_path": "#{prd_path}",
      "questions": ["..."],
      "issues": [
        {
          "title": "...",
          "body_md": "...",
          "labels": ["squads"],
          "dependencies": []
        }
      ]
    }
    ```

    Notes:
    - dependencies should reference other proposed issue titles (exact match) or GitHub URLs if known.
    - If you still have unanswered questions, still draft the PRD but mark assumptions clearly.
    """
  end

  def build_prompt(opts) do
    squad_name = opts[:squad_name] || "(unknown squad)"
    prd_path = opts[:prd_path] || ""
    issue_refs = opts[:issue_refs] || []
    pr_url = opts[:pr_url]
    worktree_path = opts[:worktree_path] || ""
    branch = opts[:branch] || ""
    base_branch = opts[:base_branch] || "main"

    issues_text =
      issue_refs
      |> Enum.map(fn
        %{"url" => url} when is_binary(url) -> url
        %{url: url} when is_binary(url) -> url
        %{"number" => n, "repo" => r} -> "#{r}##{n}"
        _ -> nil
      end)
      |> Enum.reject(&is_nil/1)
      |> Enum.join("\n")

    closing_lines = issue_closing_lines(issue_refs)

    closing_block =
      if closing_lines != "" do
        """

        PR description requirements:
        - Include the following lines verbatim somewhere in the PR description so GitHub auto-closes the issues when merged:
        #{closing_lines}
        """
      else
        ""
      end

    maybe_pr = if is_binary(pr_url) and pr_url != "", do: "- Existing PR: #{pr_url}\n", else: ""

    """
    You are the BUILD agent for squad #{squad_name}. Implement the work described by the PRD and linked issues, run tests, and open a PR.

    Context:
    - PRD: #{prd_path}
    - GitHub issues:
    #{issues_text}
    #{maybe_pr}- Worktree directory: #{worktree_path}
    - Branch: #{branch}
    - Base branch: #{base_branch}

    Requirements:
    - Implement the smallest change that satisfies the PRD/issues.
    - Run relevant tests; report commands + results.
    - Open exactly 1 PR for this card.
    #{closing_block}

    Output requirements:
    - At the end, output a BUILD_RESULT JSON block:

    ```json
    {
      "pr_url": "https://github.com/.../pull/123",
      "tests": [{"command": "...", "status": "pass|fail|skipped", "output_summary": "..."}],
      "notes": "..."
    }
    ```
    """
  end

  def create_pr_prompt(issue_refs \\ []) do
    closing_lines = issue_closing_lines(issue_refs)

    closing_block =
      if closing_lines != "" do
        """

        PR description requirements:
        - Include the following lines verbatim somewhere in the PR description so GitHub auto-closes the issues when merged:
        #{closing_lines}
        """
      else
        ""
      end

    """
    Create a GitHub Pull Request for the current branch.

    Requirements:
    - Push the branch to origin if needed.
    - Create exactly one PR.
    #{closing_block}
    - After creating it, output a BUILD_RESULT JSON block containing pr_url.
    """
  end

  defp issue_closing_lines(issue_refs) when is_list(issue_refs) do
    issue_refs
    |> Enum.map(fn
      %{"repo" => repo, "number" => number} when is_binary(repo) and is_integer(number) ->
        "Closes #{repo}##{number}"

      %{repo: repo, number: number} when is_binary(repo) and is_integer(number) ->
        "Closes #{repo}##{number}"

      %{"url" => url} when is_binary(url) and url != "" ->
        "Closes #{url}"

      %{url: url} when is_binary(url) and url != "" ->
        "Closes #{url}"

      _ ->
        nil
    end)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> Enum.join("\n")
  end

  defp issue_closing_lines(_), do: ""

  def review_prompt(opts) do
    squad_name = opts[:squad_name] || "(unknown squad)"
    pr_url = opts[:pr_url] || ""
    prd_path = opts[:prd_path] || ""
    worktree_path = opts[:worktree_path] || ""
    branch = opts[:branch] || ""
    base_branch = opts[:base_branch] || "main"

    """
    You are the REVIEW agent for squad #{squad_name}. Perform a code review of the changes for this card and produce a structured review report.

    Review target:
    - PR: #{pr_url}
    - Worktree: #{worktree_path}
    - Branch: #{branch}
    - Base: #{base_branch}
    - PRD: #{prd_path}

    Instructions:
    - Review correctness, scope, tests, risks, and maintainability.
    - Prefer actionable feedback with file/line references when possible.
    - Be concise but complete.

    Output requirements:
    - Output AI_REVIEW JSON:

    ```json
    {
      "recommendation": "approve|request_changes|comment_only",
      "risk": "low|medium|high",
      "summary": "...",
      "key_changes": ["..."],
      "findings": [
        {
          "severity": "high|medium|low",
          "title": "...",
          "details": "...",
          "suggestion": "...",
          "file": "path/or/null",
          "line": 0
        }
      ],
      "test_assessment": {
        "observed": ["..."],
        "gaps": ["..."]
      },
      "checklist": ["..."]
    }
    ```
    """
  end
end
