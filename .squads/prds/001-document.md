# PRD 001: Fleet Assembly Line (Pipeline-Orchestrated Squads)

- Status: Draft (spec-complete)
- Owner: (you)
- Last updated: 2026-01-07
- Canonical path: `.squads/prds/001-document.md`

## Summary
Fleet is an assembly-line style orchestration layer inside Squads: work moves through a directed pipeline of agents, squads, and gates, producing durable artifacts (PRDs, optional GitHub issues, PRs, review reports).

Fleet is designed for a **single operator running locally**. It optimizes the workflow of working with LLMs/agents by making the process explicit, repeatable, inspectable, and recoverable.

At a high level:

1. Brainstorm (chat) → PRD (repo markdown artifact)
2. PRD → GitHub Issues (optional; tickets + dependencies + suggested scopes)
3. Tickets → implementation (squads/agents in isolated git worktrees)
4. Review gate (LLM review if configured)
5. Human approval (manual merge in GitHub)
6. Cleanup + reporting

## What’s Done vs Next
As of 2026-01-07, Squads has moved fully to GitHub Issues for ticket tracking (no Beads/bd).

Implemented (Ticketing foundation)
- GitHub-backed tickets in API + UI (sync, claim/unclaim, close).
- Status/metadata via labels (e.g. `status:in_progress`, `status:blocked`, `type:*`, `priority:*`, `agent:*`).
- Stable ticket key format for humans and tooling: `owner/repo#123`.

Next to tackle (Fleet v1)
1. Workflow rendering: load `.squads/workflows/*.json` and render a read-only DAG in React Flow with node status.
2. Run/step state API + SQLite durability: persist runs, steps, and transcripts; resume on restart.
3. Control-plane commands: wire `/continue`, `/retry`, `/approve`, `/generate-issues`, `/run-ticket` to runtime actions.
4. Issue generation from PRD: create/label issues (incl. dependencies + scope) and dedupe/adopt existing issues.
5. Ticket execution: create worktrees/branches, run agent sessions, open PRs (optionally stacked), and reconcile artifacts on retry.
6. Review gate: surface CI status + optional LLM review output as PR comment/check-run; keep merge manual.
7. Cleanup: detect merges, delete local worktrees/branches, and update issue status labels.

The pipeline is **modeled as a DAG** (Loom Serverless Workflow DSL v1 JSON). The Squads UI renders that workflow visually (React Flow) and shows live run status, lanes, and agent sessions.

## Problem
Current agentic development tends to be:

- Chat-thread bound (hard to scale and repeat).
- Unsafe to parallelize (multiple agents collide in the same code areas).
- Hard to govern (unclear gates, unclear “done”).
- Hard to audit (outputs live in chats instead of durable artifacts).

## Goals
- Make the workflow explicit as a DAG (not an implicit chat process).
- Use durable artifacts with clear handoffs between phases.
- Keep changes reviewable and human-approved (merge remains manual).
- Improve observability: show what’s running, what’s blocked, and why.
- Improve recoverability: crashes/restarts should reconcile and continue.
- Keep operator control: most “looping/iteration” happens manually in chat; automation should be conservative.

## Non-goals (v1)
- Multi-user permissions/roles.
- Fully autonomous merges.
- Perfect automatic conflict detection (no path-prefix locks in v1).
- Strict enforcement of ticket templates and scope labeling (best-effort prompting; execution may require manual fixes).
- A complete bidirectional graphical workflow editor (UI is primarily a visualization of Loom DSL in v1).

## Personas
- **Operator (primary)**: you, running Squads + Fleet locally.
- **Collaborator (future)**: other humans who may later use Fleet, but not a v1 requirement.

## Key Product Decisions
- **Workflows live in-repo**: `.squads/workflows/*.json`.
- **Workflow format**: Loom-compatible Serverless Workflow DSL v1 (JSON documents).
  - Fleet metadata is stored under `document.metadata` (standards-compliant freeform map).
  - v1 is *DSL → UI* (graphical round-trip editing is a v2+ goal).
- **Execution runtime**: Loom runs **in-process** as a library.
- **Loom dependency (dev)**: use a Mix `path` dependency via `LOOM_PATH` (defaults to `~/dev/loom`).
- **Durability**: a Loom durability plugin stores run snapshots in **SQLite** (Squads already uses SQLite).
- **Chat control plane**: workflow progress is driven by typed commands in chat (MCP-backed).
- **Planning backend**: GitHub Issues are the v1 ticket backend (recommended); no-issues mode is secondary.
- **Ticket dependencies**: canonical source is the issue body’s `### Dependencies` section (Markdown).
- **Ticket priority**: numeric priority per ticket (default `2`).
- **GitHub auth**: PAT loaded from environment at startup.
- **Merge policy**: merges are **always manual** in GitHub’s PR UI.
- **Transcripts**: store full transcripts (including tool calls/outputs) in SQLite, indefinitely; provide optional masking.
- **Branch naming**: `squads/<scope>/<issue-slug>`.
- **Stacked PRs**: supported as real GitHub stacked PRs; max supported depth is 5; ordering is enforced via UX + informational checks (override by merging manually).

## Glossary
- **Artifact**: durable output of a stage (PRD, issue set, PR, review report).
- **Workflow**: a DAG encoded as Loom Serverless Workflow DSL JSON.
- **Node / Step**: a single executable unit in a workflow run.
- **Gate**: a node that blocks progress until criteria is met (review/human decision).
- **Persona**: a named agent configuration (prompt/model/tools).
- **Session**: a single chat transcript for a persona, created for a specific step (v1 default).
- **Run**: one execution of a workflow; persists in SQLite.
- **Scope label**: GitHub label `scope:<area>/<subarea>` used for (best-effort) lane serialization.
- **Lane**: a serialization domain for tickets that share a scope.
- **Soft lock**: a lane is “assigned” to one active worker/session; reclaimable by the operator.
- **Stacked PRs**: PR chain where each PR targets the previous PR’s branch.

## Product Overview
Fleet is a “workflow + runtime + UI” triad:

- **Workflow definition**: Loom workflow JSON stored in-repo.
- **Runtime**: Loom executes the workflow and delegates work to personas (agent steps) and MCP tools (GitHub/git/etc).
- **UI**: React Flow visualizes the workflow and run status; the operator drives progress via chat commands and GitHub.

### Sources of truth
- PRD: git-tracked markdown in `.squads/prds/`.
- Workflow: git-tracked JSON in `.squads/workflows/`.
- Run state + transcripts: SQLite (local).
- GitHub artifacts (when used): Issues, PRs, CI, and human reviews.

## Architecture (Local-first)
Fleet runs entirely on the operator’s machine.

- **Squads UI** hosts Fleet UI (workflow graph, run view, chat panes).
- **Squads API** hosts the Fleet orchestrator and Loom runtime (in-process library).
- **SQLite** stores durable run snapshots, step results, and full transcripts.
- **MCP tools** provide integrations (GitHub, git, agent-mail, Playwright, etc.).

The UI MUST be able to observe run/step/session state from the API (streaming or polling), and MUST be able to open the corresponding chat session for any step that is waiting or failed.

## UX / UI Requirements

### Primary screen: live workflow run
The default operator view is a live, visual workflow:

- React Flow graph showing node status (e.g. queued/running/waiting/failed/succeeded).
- Lane/ticket summary: what’s in progress, what’s blocked, what’s waiting on you.
- Agent/persona indicators: whether a persona is “busy” and how many sessions exist.

Minimum node status states (v1):
- `queued`
- `running`
- `waiting_on_user`
- `blocked` (dependencies not satisfied / missing scope / etc)
- `failed`
- `succeeded`

### Chat as the control plane
Fleet is operated through chat sessions.

- Each agent execution runs in a **fresh session by default** (per persona, per step) to avoid interleaving.
- The UI groups sessions by persona and run, and tags messages with run/step context.
- The operator can explicitly “spawn a new session” for a persona to reset context.

Slash commands are typed in chat and apply to the currently selected node (v1):
- `/continue`
- `/retry`
- `/generate-issues`
- `/run-ticket <issue-or-ticket-ref>`
- `/approve` / `/reject` (for gates)

(Exact command surface is flexible; v1 goal is “manual commands through MCP”.)

### Node configuration UX
- Selecting a node opens a **right sidebar flyout**.
- v1 can be read-only configuration display (since workflows are authored in Loom DSL). Editing in the UI is a v2+ goal.

### Human approval gate UX
- Fleet UI links out to GitHub Issues/PRs.
- Approval = **manual merge** in GitHub PR UI.
- At approval time, Fleet should surface:
  - Diff summary (at least link to PR + file/line stats)
  - CI status / required checks
  - LLM review report summary

## Workflow Definition and Execution

### Workflow file format and storage
- Workflow files are stored in `.squads/workflows/*.json`.
- Each file MUST be a Loom Serverless Workflow DSL document (v1), using the `document` + `do` structure.
- Fleet-specific metadata MUST live under `document.metadata.squads`.

Example (spec-compliant JSON):

```json
{
  "document": {
    "dsl": "1.0.2",
    "namespace": "<repo-or-org>",
    "name": "fleet-default",
    "version": "0.1.0",
    "metadata": {
      "squads": {
        "fleet": {
          "workflowPath": ".squads/workflows/fleet-default.json"
        }
      }
    }
  },
  "evaluate": { "language": "jq", "mode": "strict" },
  "use": {
    "functions": {
      "syncIssues": { "call": "http", "with": { "method": "post", "endpoint": "http://localhost:4000/api/..." } }
    }
  },
  "do": [
    { "sync": { "call": "syncIssues" } },
    { "gate": { "listen": { "to": { "one": { "with": { "type": "io.squads.fleet.approved" } } } } } }
  ]
}
```

### Opinionated Fleet profile (still spec-compliant)
Fleet will use a constrained subset of the DSL so workflows are readable and map cleanly to the UI:

- **Graph surface**: treat the top-level `do` list as the primary DAG; nested `do` inside `switch`/`for`/`try` is rendered as collapsed subgraphs in v1.
- **Primitives**: define reusable Fleet operations under `use.functions` and invoke them via `call: <functionName>`.
- **Manual gates**: use `listen` tasks that wait for CloudEvents emitted by the UI (`/continue`, `/approve`, `/reject`, `/retry`).
- **Status signaling**: use `emit` tasks (or function wrappers) to publish lifecycle/status events so Squads can update the UI and persist step results.
- **Branching**: use `switch` + `then` flow directives for conditional paths; avoid deep/clever control flow in v1.
- **Iteration**: use `for` to iterate tickets (issue-backed mode), and `try`/`retries` for fault tolerance.

**Proposed `use.functions` set (v1)**
- `fleet.sync_issues`: ensure the local DB mirrors GitHub issues labeled `squads`.
- `fleet.generate_issues`: create/update issues from a PRD (labels + dependency sections + dedupe/adopt).
- `fleet.run_ticket`: create worktree + branch, start an agent session for a ticket, and track outputs.
- `fleet.open_pr`: open a PR (or record a PR URL) and attach it to the ticket/run.
- `fleet.review`: request/collect CI + optional LLM review output.
- `fleet.cleanup`: after merge, delete local worktrees/branches and update issue labels.

**Control-plane as CloudEvents (v1)**
- Commands from chat/UI are emitted as events and consumed with `listen`, e.g.:
  - `io.squads.fleet.command.continue`
  - `io.squads.fleet.command.retry`
  - `io.squads.fleet.command.approve`
  - `io.squads.fleet.command.reject`

### React Flow mapping
- v1: Fleet UI renders a Loom workflow as an **opinionated React Flow graph**.
- v1 does not guarantee lossless “graph edits → DSL” round-tripping.
- v2+: add bidirectional editing (graph → DSL and DSL → graph).

### Execution model
- A **Run** executes a workflow definition through Loom.
- Each node produces a persisted **Step Result**:
  - start time, end time
  - status
  - structured result payload
  - for agent steps: full transcript

### Persistence and durability (SQLite)
Fleet implements a Loom durability plugin that stores **snapshots** in SQLite.

Required persisted data (v1):
- Runs and current state
- Steps: start/end, status, step result payload
- Agent sessions: full transcript including tool calls and tool outputs

Retention:
- Store indefinitely by default.
- Provide configurable masking options for stored transcripts (v1 “nice to have”, but the storage model must support it).

Crash recovery:
- On restart, Fleet loads the latest snapshot and resumes execution.
- For steps that interact with GitHub, the responsible node/agent MUST reconcile existing artifacts and **adopt** them (instead of failing or duplicating work).

### Failure policy
- GitHub/API calls: short retry with backoff; if still failing, mark the step failed.
- Agent steps: manual `/retry` by default.
- When GitHub fails mid-run, keep local state/worktrees and allow resuming once it recovers.

## Ticketing Model
Fleet supports two planning/execution modes.

### Mode A: Issue-backed tickets (v1 default)
Fleet generates and/or consumes GitHub issues as tickets.

Benefits:
- Clear durable handoff between planning and execution
- Familiar for LLMs and humans
- Easy linking: issues ↔ PRs ↔ checks ↔ review

Constraints:
- Template and labeling are best-effort; operator can proceed manually.

### Mode B: No-issues execution (supported)
Sometimes you want to skip issues and just run a piece of work.

- Planning is “internal” to the agent/operator and not persisted as issues.
- Auditability is intentionally relaxed.
- Optionally, Fleet supports writing a lightweight plan file under `.squads/plans/`.

#### Optional plan file format (`.squads/plans/*.md`)
- Bullet list items only.
- Each bullet MAY include references to GitHub issues/PRs, commit SHAs, and repo URLs.

Example:

```md
- PR: https://github.com/org/repo/pull/123
- Issue: https://github.com/org/repo/issues/456
- Commit: abcdef1234567890
```

## Ticket Issue Format (GitHub Markdown)
GitHub issues do not support JSX/true MDX, but we can treat GitHub-flavored Markdown as a structured document by recommending a strict section template plus a small machine-readable metadata block.

**Enforcement policy (v1)**
- Best-effort only: Fleet SHOULD prompt for this structure, but it MUST NOT hard-block based solely on formatting.

### Template sections (recommended)
- **Description**: what and why (small, concrete).
- **Goals**: 2–6 bullets or checkboxes.
- **Constraints**: hard rules (e.g. “no new deps”, “reuse React Flow”).
- **Dependencies**: blocking items (canonical parse target).
- **References**: PRD excerpts + code pointers.
- **Existing Modules / Reuse**: specific files/functions to reuse.
- **Acceptance Criteria**: testable outcomes.

### Machine-readable metadata block (recommended)
At the top of the issue body include a fenced `yaml` block that Fleet can parse without LLM help:

```yaml
fleet:
  prd:
    path: .squads/prds/001-document.md
    ref: <git-commit-sha-of-prd>
    excerpts:
      - lines: 149-170
  scope: frontend/board-ui
  priority: 2
  constraints:
    - no_new_dependencies
  code_pointers:
    - assets/src/components/board/TicketFlow.tsx
  dependencies:
    - <issue-or-pr-url-or-#123>
```

Notes:
- `ref` + `excerpts` lets Fleet extract only relevant PRD lines (stable even if PRD changes later).
- `scope` SHOULD match the GitHub label `scope:<area>/<subarea>` when present.

### Dependencies section parsing (canonical)
Fleet parses dependencies from the `### Dependencies` section of the issue body.

Accepted dependency reference formats (v1):
- Full GitHub URLs to issues: `https://github.com/<owner>/<repo>/issues/<number>`
- Full GitHub URLs to PRs: `https://github.com/<owner>/<repo>/pull/<number>`
- Shorthand in the current repo: `#123` (issue or PR)
- Cross-repo shorthand: `<owner>/<repo>#123`
- Repo URL (external dependency marker): `https://github.com/<owner>/<repo>`

Semantics:
- Each listed dependency is blocking.
- Dependencies that Fleet cannot automatically resolve (e.g. a plain repo URL) are treated as “external” and require manual satisfaction/override.

### Default agent instruction derived from every ticket
- Implement the smallest acceptable change that meets acceptance criteria.
- Avoid refactors, renames, or broad formatting changes unless required.
- If work expands beyond the ticket’s scope, propose splitting into follow-up work before continuing.

### Context Packing (Don’t Read The Whole PRD)
To avoid wasting model context, Fleet should build a ticket context pack per execution:

- Ticket sections: Description, Goals, Constraints, Dependencies, Acceptance Criteria, References.
- PRD excerpts only: extract `prd.path@prd.ref` line ranges listed under `prd.excerpts`.
- Code reuse pointers: only the files/modules explicitly referenced by the ticket.

If a ticket lacks precise references, Fleet should prefer fixing the ticket (adding refs) over dumping the full PRD into the prompt.

## Lanes, Scopes, and Scheduling

### Scope labels (best-effort)
- Fleet SHOULD use scope labels as its primary concurrency control mechanism when available.
- Execution behavior:
  - If a ticket has exactly one `scope:<area>/<subarea>` label, Fleet assigns it to that lane.
  - If scope is missing/ambiguous, Fleet assigns it to an `unknown` lane and requires manual action (set scope) before it is scheduled.

### Ticket priority
Fleet supports ticket priority to help the operator decide what to run next.

- Priority is an integer (lower is higher priority) and is interpreted only within the local scheduler.
- In issue-backed mode, Fleet SHOULD read priority from `fleet.priority` in the optional YAML metadata block.
- If priority is missing, default priority is `2`.

### Soft locks per lane
- Fleet MUST NOT run two tickets concurrently in the same lane when lane mode is enabled.
- Lanes are “assigned” to an active worker/session (soft lock).
- The operator MUST be able to reclaim a lane easily (force-unassign) if something is stuck.

### No additional locking (v1)
- No path-prefix locks or predicted touch sets in v1.
- If collisions happen, rely on human review and improved scoping.
- Optional future mitigation: agent-mail based coordination between agents working on shared areas.

## Git Worktrees and Branching

### Worktrees
- Each ticket execution runs in an isolated git worktree.
- Worktrees live under a deterministic directory (recommendation): `.squads/worktrees/<ticket-key>/...`.
- Retry behavior:
  - By default, retries create a fresh worktree.
  - Fleet MAY reuse a worktree when continuing the same ticket with the same persona/session, but fresh worktrees are the safe default.

### Branch naming
- Branch naming convention: `squads/<scope>/<issue-slug>`.
- If scope is unknown: `squads/unknown/<issue-slug>`.

### Cleanup
- After the operator merges the PR, Fleet deletes local worktrees and branches.
- PRDs remain unchanged (issues already link to the PRD; PRD does not need reverse-linking).

## Stacked PRs (Pipelining Within a Lane)

### Goals
Stacking reduces idle time when lane serialization would otherwise block progress.

- While ticket A is in review, ticket B can start on top of A.
- Feedback can start earlier for B (diff is relative to A).

### How stacking works
- PR A targets `main`.
- PR B targets branch `squads/<scope>/<ticket-A>` (base branch is A’s branch).

Fleet behavior when stacking is enabled:
- Create ticket branches off the current lane head.
- Open PRs with base set to the parent branch.
- Add a small “Stack” section in the PR body including:
  - parent PR link (if known) or parent commit SHA
  - merge order note

Maximum supported stack depth (v1): 5.

### Merge ordering enforcement
- Fleet may emit an **informational** GitHub check-run reminding about merge order.
- Override is simple: merge manually in GitHub PR UI.

### Retarget after parent merge
- After PR A merges, Fleet automatically retargets PR B’s base to `main`.
- Automatic rebases are out of scope for v1.

## Review Gate

### Review stages
- CI (GitHub Actions) is the first feedback signal.
- If configured, a review persona/squad runs an LLM review after CI.

### Review output
- Review output is written to:
  - a PR comment (human-readable)
  - a GitHub check-run output (structured/summary)

## Security and Privacy
- Fleet runs locally, with local filesystem access.
- GitHub auth uses a PAT loaded from the environment at startup.
- Since transcripts are stored indefinitely and include tool outputs, Fleet should support masking options for persisted transcripts.

## Acceptance Criteria (v1)
- Workflow JSON at `.squads/workflows/*.json` loads and renders in React Flow.
- Runs execute through Loom in-process and persist snapshots in SQLite.
- Each step records start/end, status, and result payload.
- Agent steps persist full transcripts including tool calls and tool outputs.
- Crash/restart resumes from snapshots and adopts existing GitHub artifacts (no forced cleanup).
- Issue generation can dedupe by “title + PRD link” and adopt existing issues.
- Ticket execution uses git worktrees and creates GitHub PRs.
- Merge remains manual; Fleet detects merges and performs cleanup (delete worktrees + branches).
- Review gate (when configured) writes a PR comment and a check-run output.
- Stacked PR creation works (real base branches) and Fleet supports stacks up to depth 5.

## Risks / Concerns
- **Duplicate artifacts**: heuristic dedupe (title + PRD link) can still collide; mitigate via optional `fleet:` metadata later.
- **Concurrency collisions**: no path locks in v1; mitigate with lanes + scoping discipline and human review.
- **Transcript sensitivity**: full tool outputs can include secrets; mitigate with masking and operator discipline.
- **SQLite growth**: indefinite retention can bloat DB; mitigate with optional toggles and export/compact later.
- **Workflow UX mismatch**: DSL-first means the graph is visualization-only in v1; mitigate by good mapping and sidebar config display.

## Alternatives / Tradeoffs
- **GitHub Issues vs other planning backends**: Issues are broadly understood and integrate well with PRs/checks; Fleet still supports a no-issues mode for pragmatism.
- **Scope labels vs path locks**: labels are simple and human-friendly; path locks are more precise but require prediction/maintenance.
- **Automatic merges vs manual**: manual merge preserves operator trust and reduces risk; automation focuses on preparation and review.

## Future Work (v2+)
- Bidirectional workflow editing (React Flow edits write back to Loom DSL).
- Optional context carry-over between sessions/personas ("compact and keep alive").
- Path-prefix locks or predicted touch sets (if collisions become painful).
- Better dedupe with stable `fleet.ticket_id`.
- Optional automatic rebase/retarget tooling for stacked PR chains.
- Budget controls (max tokens per step/run) if/when runs become more autonomous.
