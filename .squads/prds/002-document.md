# PRD 002: Filesystem Issues + Reviews (Chat-Native)

- Status: Draft
- Owner: (you)
- Last updated: 2026-01-10
- Canonical path: `.squads/prds/002-document.md`

## Summary
We will simplify Squads’ planning + review workflow by moving **issues** and **human reviews** from GitHub-native primitives to **filesystem-backed artifacts** inside each project:

- Issues live in `.squads/issues/`
- Reviews live in `.squads/reviews/`

Agents create these artifacts by calling MCP tools (initially) and returning a special-tagged payload in chat:

- `<issue>{...json...}</issue>`
- `<review>{...json...}</review>`

The Squads UI recognizes these tags and renders inline UI controls (buttons/cards). Clicking them navigates to the corresponding Issue/Review view in Squads.

This makes the **chat the primary interface** for navigation and task progression, while the filesystem provides durable, inspectable artifacts.

## Problem
Today Squads leans on:

- GitHub Issues as the primary ticket backend.
- GitHub PR review UX for human reviews.

This adds friction for local-first workflows:

- Frequent context switching between chat ↔ issues ↔ PR review UI.
- Overhead for lightweight tasks that do not need GitHub artifacts.
- Harder to build a “chat-native control plane” where the agent can hand off next actions as clickable UI elements.

## Goals
- **Local-first issues**: create and manage issues as files in `.squads/issues/`.
- **Local-first reviews**: create and manage reviews as files in `.squads/reviews/`.
- **Chat-native navigation**: agent emits `<issue>` / `<review>` tags that the UI renders as actionable elements.
- **Rich review UX**:
  - Summary + highlights
  - File-level comments
  - Line-level comments (anchored to a diff)
  - Submitting a review sends structured feedback back to the agent.
- **MCP-first integration**: implement `create_issue` / `create_review` as MCP tools served by Squads (via existing `/api/mcp/:name/connect`).
- **Worktree-aware diffs**: reviews are anchored to the worktree’s “start” commit → current HEAD (or an explicit base/head SHA pair).

## Non-goals (v1)
- Full GitHub Issues parity (assignees, labels sync, cross-repo references).
- Replacing existing board lanes / cards architecture immediately.
- Multi-user permissions/ACLs.
- Advanced merge automation.

## Key Product Decisions
- **Artifacts are filesystem-backed** under `.squads/`.
- **Local by default**: `.squads/issues/` and `.squads/reviews/` are intended to be local artifacts (users may choose to commit them, but v1 does not require it).
- **Tag payloads are JSON** inside `<issue>` / `<review>` so we can render rich UI elements over time.
- **MCP tools** are the initial agent integration surface.

## Data Model (Filesystem)
### Directory layout
- `.squads/issues/`
- `.squads/reviews/`

### IDs and filenames
Use ULIDs for stable sorting and non-colliding creation.

- Issue: `.squads/issues/iss_<ulid>.md`
- Review: `.squads/reviews/rev_<ulid>.json`

### Issue file format (Markdown + YAML frontmatter)
**Path**: `.squads/issues/iss_<ulid>.md`

Frontmatter is the machine-readable source of truth; body is for humans.

```md
---
id: iss_01J...  # ULID
status: open|in_progress|blocked|done
priority: 0|1|2|3|4
created_at: 2026-01-10T12:00:00Z
updated_at: 2026-01-10T12:00:00Z
labels:
  - type:feature
  - area:board
assignee: null
references:
  prd_path: .squads/prds/002-document.md
  card_id: null
  pr_url: null
---

# Title

## Description
...

## Acceptance Criteria
- ...

## Dependencies
- iss_01J... (or path/url)
```

### Review file format (JSON)
**Path**: `.squads/reviews/rev_<ulid>.json`

Reviews need structured comments and diff anchoring; JSON is the simplest v1 format.

```json
{
  "id": "rev_01J...",
  "status": "pending|approved|changes_requested",
  "created_at": "2026-01-10T12:00:00Z",
  "updated_at": "2026-01-10T12:00:00Z",

  "title": "...",
  "summary": "...",
  "highlights": ["..."],

  "context": {
    "project_id": "...",
    "squad_id": "...",
    "card_id": "...",
    "worktree_path": "...",
    "base_sha": "...",
    "head_sha": "..."
  },

  "files_changed": [
    {
      "path": "assets/src/routes/review.tsx",
      "status": "modified|added|deleted|renamed"
    }
  ],

  "comments": [
    {
      "id": "cmt_01J...",
      "created_at": "2026-01-10T12:00:00Z",
      "author": "human",
      "type": "summary|file|line",
      "body": "...",
      "file": "path/or/null",
      "line": 123,
      "side": "new|old"
    }
  ]
}
```

## MCP Tooling
Squads already exposes an MCP transport (`/api/mcp/:name/connect`). We will add a Squads MCP server (name TBD) that provides these tools.

### Tool: `create_issue`
**Purpose**: Create a new filesystem issue file and return a tag payload the UI can render.

**Input**
```json
{
  "project_id": "...",
  "title": "...",
  "body_md": "...",
  "priority": 2,
  "labels": ["type:feature"],
  "dependencies": ["iss_01J..."],
  "references": {
    "prd_path": ".squads/prds/...",
    "card_id": "..."
  }
}
```

**Tool response**
The MCP tool returns a normal MCP result, but the agent MUST also emit a chat tag:

```xml
<issue>{"id":"iss_01J...","path":".squads/issues/iss_01J....md","url":"/issues/iss_01J...","title":"...","status":"open"}</issue>
```

### Tool: `create_review`
**Purpose**: Create a new filesystem review file and return a tag payload the UI can render.

**Input**
```json
{
  "project_id": "...",
  "title": "...",
  "summary": "...",
  "highlights": ["..."],
  "worktree_path": "...",
  "base_sha": "...",
  "head_sha": "...",
  "files_changed": [{"path":"...","status":"modified"}],
  "references": {
    "prd_path": ".squads/prds/...",
    "card_id": "...",
    "pr_url": "..."
  }
}
```

**Tool response / tag**
```xml
<review>{"id":"rev_01J...","path":".squads/reviews/rev_01J....json","url":"/review/rev_01J...","title":"...","status":"pending"}</review>
```

### Tool: `submit_review` (v1)
When a human submits, the UI calls backend API which updates the review file, then Squads sends a message into the relevant agent session containing the full review payload.

Minimum input:
```json
{
  "project_id": "...",
  "review_id": "rev_01J...",
  "status": "approved|changes_requested",
  "feedback": "...",
  "comments": [/* optional structured comments */]
}
```

## UX / UI
### Chat: inline navigation
- When chat messages contain `<issue>...</issue>` or `<review>...</review>`, the UI renders them as a compact card:
  - Title
  - Status
  - Primary CTA: “Open Issue” / “Open Review”

### Issue view
- Minimal v1:
  - Render Markdown
  - Edit in-place (optional v1.1)
  - Status transitions (open/in_progress/blocked/done)

### Review view
- Reuse the existing `/review` view conceptually, but back it with filesystem reviews.
- Show:
  - summary + highlights
  - diff (computed from `base_sha..head_sha` in `worktree_path`)
  - comment composer (summary/file/line)
  - submit: Approve / Request Changes

### Feedback loop to agent
- On submit, Squads sends a single structured message into the agent’s session:
  - review status
  - human feedback
  - structured comments
  - references (review id/path)

## Backend Requirements
### Filesystem access + safety
- All issue/review IO is scoped to the project root.
- Reject path traversal and absolute paths.
- Ensure directories exist (`.squads/issues`, `.squads/reviews`).

### Diff computation
- For review rendering, run `git diff --patch <base_sha>...<head_sha>` in `worktree_path`.
- `base_sha` should be captured when the worktree is created (or on first review creation for that worktree).

### API surface (proposed)
- `GET /api/projects/:project_id/fs/issues` (list)
- `GET /api/projects/:project_id/fs/issues/:id` (read)
- `POST /api/projects/:project_id/fs/issues` (create)

- `GET /api/projects/:project_id/fs/reviews` (list)
- `GET /api/projects/:project_id/fs/reviews/:id` (read)
- `POST /api/projects/:project_id/fs/reviews` (create)
- `POST /api/projects/:project_id/fs/reviews/:id/submit` (submit)

(Exact routing can be adjusted to match current API conventions.)

### MCP integration
- Add a Squads MCP tool namespace that bridges tool calls → the above APIs.
- Ensure the MCP server can be provisioned into the project `opencode.json` via existing `Squads.OpenCode.Config.init/2`.

## Rollout Plan
- Enable filesystem issues/reviews by default.
- Keep existing GitHub issue generation and existing DB-backed review queue working.

## Acceptance Criteria
- Agent can call `create_issue` and the UI renders an inline issue card from `<issue>...</issue>`.
- Agent can call `create_review` and the UI renders an inline review card from `<review>...</review>`.
- Clicking the inline review opens a view showing a stable diff from `base_sha...head_sha` in the worktree.
- Submitting a review updates the review file and sends a structured “review feedback” message back to the agent.

## Open Questions
- Should issues/reviews be auto-ignored via `.gitignore` by default, or left unignored with docs recommending local-only?
- What is the canonical place to store worktree base SHA (DB vs file vs inferred)?
- Should issue dependencies reference IDs, filenames, or both?
- Do we want a single “artifact index” file for faster listing, or rely on directory scans?
