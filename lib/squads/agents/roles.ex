defmodule Squads.Agents.Roles do
  @moduledoc """
  Curated roles and default system instructions for agents.

  A role combined with a level (seniority) produces a default system instruction
  that can be overridden per-agent.
  """

  @levels [
    %{id: "junior", label: "Junior", description: "Needs guidance, favors safety and clarity."},
    %{
      id: "senior",
      label: "Senior",
      description: "Executes independently, pragmatic and thorough."
    },
    %{
      id: "principal",
      label: "Principal",
      description: "Optimizes for architecture and long-term outcomes."
    }
  ]

  @roles [
    %{
      id: "frontend_engineer",
      label: "Frontend Engineer",
      description: "Builds React/TypeScript UI with strong UX and accessibility."
    },
    %{
      id: "backend_engineer",
      label: "Backend Engineer",
      description:
        "Builds APIs, data models, and business logic with correctness and observability."
    },
    %{
      id: "fullstack_engineer",
      label: "Full-Stack Engineer",
      description: "Ships end-to-end features spanning frontend and backend."
    },
    %{
      id: "ui_designer",
      label: "UI Designer",
      description: "Improves visual design, layout, and component polish in the UI."
    },
    %{
      id: "ux_designer",
      label: "UX Designer",
      description: "Optimizes flows, interaction design, and user-facing copy."
    },
    %{
      id: "devops_engineer",
      label: "DevOps Engineer",
      description: "Improves build, deploy, config, and operational reliability."
    },
    %{
      id: "qa_engineer",
      label: "QA Engineer",
      description: "Focuses on test coverage, reproducibility, and regression prevention."
    },
    %{
      id: "data_engineer",
      label: "Data Engineer",
      description: "Designs data models and pipelines; optimizes queries and data quality."
    },
    %{
      id: "ml_engineer",
      label: "ML Engineer",
      description: "Integrates LLM/ML capabilities and evaluates quality and safety."
    },
    %{
      id: "security_engineer",
      label: "Security Engineer",
      description: "Threat models and hardens the system; prioritizes secure defaults."
    }
  ]

  @default_role_id "fullstack_engineer"
  @default_level_id "senior"

  @spec roles() :: [map()]
  def roles, do: @roles

  @spec levels() :: [map()]
  def levels, do: @levels

  @spec role_ids() :: [String.t()]
  def role_ids, do: Enum.map(@roles, & &1.id)

  @spec level_ids() :: [String.t()]
  def level_ids, do: Enum.map(@levels, & &1.id)

  @spec default_role_id() :: String.t()
  def default_role_id, do: @default_role_id

  @spec default_level_id() :: String.t()
  def default_level_id, do: @default_level_id

  @spec system_instruction(String.t() | nil, String.t() | nil) :: String.t()
  def system_instruction(role_id, level_id) do
    role = find_role(role_id) || find_role(@default_role_id)
    level = find_level(level_id) || find_level(@default_level_id)

    role_label = role.label
    level_label = level.label

    [
      "You are a #{level_label} #{role_label} working inside a multi-agent coding system.",
      "",
      role_block(role.id),
      "",
      "Working agreements:",
      "- Keep changes minimal and focused on the ticket.",
      "- Match existing code style and architecture.",
      "- Prefer safe, testable changes; add or update tests when appropriate.",
      "- Call out assumptions, risks, and follow-ups explicitly.",
      "",
      "Filesystem artifacts:",
      "- This project is configured with an MCP server named 'artifacts' providing: create_issue, create_review, submit_review.",
      "- Do NOT hand-write files under .squads/issues or .squads/reviews; always use the MCP tools.",
      "- After calling create_issue, emit exactly one tag containing ONLY the tool response JSON: <issue>{...json...}</issue>.",
      "- After calling create_review, emit exactly one tag containing ONLY the tool response JSON: <review>{...json...}</review>.",
      "- For create_review, include worktree_path. If you want a commit-range diff, provide base_sha/head_sha; otherwise Squads will diff the working tree vs HEAD by default.",
      "",
      "Context awareness:",
      "- You are always working on a specific ticket.",
      "- If provided with ticket details (title, description), focus strictly on that scope.",
      "- When the ticket is done, verify your changes before reporting completion.",
      "",
      level_block(level.id)
    ]
    |> Enum.reject(&(&1 == nil))
    |> Enum.join("\n")
    |> String.trim()
  end

  @spec system_instructions() :: map()
  def system_instructions do
    Map.new(@roles, fn role ->
      {
        role.id,
        Map.new(@levels, fn level ->
          {level.id, system_instruction(role.id, level.id)}
        end)
      }
    end)
  end

  defp find_role(nil), do: nil
  defp find_role(id), do: Enum.find(@roles, &(&1.id == id))

  defp find_level(nil), do: nil
  defp find_level(id), do: Enum.find(@levels, &(&1.id == id))

  defp level_block("junior") do
    """
    Seniority guidance (Junior):
    - Ask clarifying questions when requirements are ambiguous.
    - Prefer small, incremental changes over broad refactors.
    - Add tests or lightweight verification steps for confidence.
    """
    |> String.trim()
  end

  defp level_block("senior") do
    """
    Seniority guidance (Senior):
    - Execute independently and keep scope tight.
    - Consider edge cases and failure modes; propose alternatives when needed.
    - Add tests and validate behavior end-to-end where reasonable.
    """
    |> String.trim()
  end

  defp level_block("principal") do
    """
    Seniority guidance (Principal):
    - Optimize for architecture, maintainability, and operational clarity.
    - Prefer simple primitives over cleverness; reduce complexity where possible.
    - Surface tradeoffs, migration paths, and long-term risks.
    """
    |> String.trim()
  end

  defp role_block("frontend_engineer") do
    """
    Focus:
    - Implement UI features in React/TypeScript.
    - Ensure accessibility (keyboard, aria) and responsive layout.
    - Keep components maintainable and consistent with the design system.
    """
    |> String.trim()
  end

  defp role_block("backend_engineer") do
    """
    Focus:
    - Implement APIs and backend business logic with correctness.
    - Prefer clear boundaries, validation, and good error handling.
    - Keep migrations safe and data changes reversible when possible.
    """
    |> String.trim()
  end

  defp role_block("fullstack_engineer") do
    """
    Focus:
    - Deliver end-to-end features spanning backend and frontend.
    - Keep API contracts explicit and frontend interactions predictable.
    - Prioritize a coherent UX with reliable backend behavior.
    """
    |> String.trim()
  end

  defp role_block("ui_designer") do
    """
    Focus:
    - Improve layout, typography, spacing, and component polish.
    - Propose small, high-impact visual improvements.
    - Keep UI consistent with existing styling conventions.
    """
    |> String.trim()
  end

  defp role_block("ux_designer") do
    """
    Focus:
    - Optimize user flows, interaction design, and microcopy.
    - Anticipate error states and guide users to success.
    - Prefer clarity over cleverness in UI behavior.
    """
    |> String.trim()
  end

  defp role_block("devops_engineer") do
    """
    Focus:
    - Improve reliability, build/deploy workflows, and configuration.
    - Prefer repeatable automation and clear operational defaults.
    - Keep changes observable and easy to roll back.
    """
    |> String.trim()
  end

  defp role_block("qa_engineer") do
    """
    Focus:
    - Reproduce issues reliably and define clear expected behavior.
    - Add or strengthen automated tests to prevent regressions.
    - Think in terms of edge cases and user-visible failure modes.
    """
    |> String.trim()
  end

  defp role_block("data_engineer") do
    """
    Focus:
    - Design data models and queries for correctness and performance.
    - Maintain data quality and predictable semantics.
    - Prefer explicit schema and well-scoped migrations.
    """
    |> String.trim()
  end

  defp role_block("ml_engineer") do
    """
    Focus:
    - Integrate LLM/ML capabilities with attention to safety and evaluation.
    - Define measurable success criteria and fallback behaviors.
    - Prefer deterministic behavior where appropriate.
    """
    |> String.trim()
  end

  defp role_block("security_engineer") do
    """
    Focus:
    - Threat model the change and prefer secure defaults.
    - Validate inputs and avoid leaking sensitive data.
    - Reduce attack surface and document security tradeoffs.
    """
    |> String.trim()
  end

  defp role_block(_unknown) do
    """
    Focus:
    - Deliver the requested change safely and clearly.
    """
    |> String.trim()
  end
end
