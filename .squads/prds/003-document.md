# PRD 003: Global Squads (Reusable Templates + Deployments + Leaders)

- Status: Draft (spec-complete)
- Owner: (you)
- Last updated: 2026-01-10
- Canonical path: `.squads/prds/003-document.md`

## Summary
We are redefining **Squads** as a *global* primitive (a reusable team template) instead of something defined per project.

A global squad (e.g. “Frontend Squad”) is composed of:
- a single **Squad Leader** (generalist/coordinator; the primary interface)
- multiple specialized **subagents** (implementers/reviewers/explorers)

We then **deploy** that squad into one or more projects. When work is assigned in a project, the Squad Leader becomes the “front door” and delegates work by launching subagents.

This redesign explicitly aligns with OpenCode’s agent model:
- **Primary vs subagents** (leader orchestrates; subagents execute).
- Agents defined via `.opencode/agent/` (project-scoped) and/or `~/.config/opencode/agent/` (global).

Finally, we standardize cross-team communication: the existing mail MCP becomes **squad-to-squad** communication (leader-to-leader), not “any agent to any agent”.

## Problem
Today Squads is modeled as:
- `Squad` belongs to a `Project` (project-scoped definition).
- `Agent` belongs to a `Squad` and uses `role + level` (e.g. senior/junior) to generate instructions.
- `Session` derives `project` via `agent -> squad -> project`.
- Mail and escalation semantics target individuals/mentors, not the squad boundary.

This causes:
- **Recreation overhead:** the same conceptual squad must be created repeatedly per project.
- **No reusable templates:** “Frontend Squad” can’t be reused across projects without duplication.
- **Misalignment with OpenCode:** we’re not leveraging `.opencode` agents + primary/subagent orchestration as the primitive.
- **Poor boundary hygiene:** cross-team comms happen agent-to-agent instead of leader-to-leader.

## Goals
1. **Global squads:** define squads once, reuse everywhere.
2. **Deployments:** assign (deploy) a global squad to many projects.
3. **Squad Leader is the interface:** all work enters a squad through the leader.
4. **OpenCode-native agents:** use OpenCode agent configs as the source of truth for prompts/models/tools/permissions.
5. **Leader-launched subagents:** the leader launches subagents for specialized tasks.
6. **Leader-to-leader comms:** mail MCP is used for squad-to-squad comms.
7. **Remove senior/junior levels:** eliminate “level”; keep functional specialization via agent configs.
8. **No naming collisions:** global identifiers are unique and stable.

## Non-goals (v1)
- Multi-tenant / multi-user permissioning.
- Automatically generating perfect agent prompts for every project.
- Fully autonomous, self-directed multi-squad orchestration.
- Cross-project shared “memory” beyond what OpenCode already persists per session.

## Personas
- **Operator / Admin (primary):** defines global squads, deploys to projects, assigns leaders, maintains agent templates.
- **Project owner:** sees deployed squads and assigns work to squads.
- **Squad Leader agent:** coordinates work, launches subagents, talks to other Squad Leaders.

## Glossary
- **Global Squad (Template):** reusable definition of a team (name/slug/type + member agents).
- **Squad Deployment:** association of a global squad to a specific project.
- **Squad Leader:** the single “front door” agent for a squad.
- **Subagent:** specialized agent invoked by the leader.
- **OpenCode agent:** an agent configured in OpenCode (prompt/model/tools/permissions).
- **Session:** an OpenCode session instance; OpenCode persists transcript/state; Squads persists metadata and links.

## Current State (Baseline)
Key existing constraints we must design around:
- Squads are project-scoped (`squads.project_id` exists today).
- Sessions and OpenCode server startup currently assume project access via `agent -> squad -> project`.
- Mail MCP includes an `escalate` tool that routes to `agent.mentor_id` (implicit seniority/mentorship model).

This means that “make squads global” is not just a table change; we must also make **project context explicit** wherever we currently rely on `squad.project_id`.

## Key Product Decisions
1. **Squads are templates, not project-owned.** Projects have deployments.
2. **Agents are identified by OpenCode agent names.** Squads stores references, not prompt bodies.
3. **Exactly one leader per squad.** Leader is required and explicit.
4. **Project context is explicit for sessions.** Sessions reference a project/deployment.
5. **Mail is routed to leaders.** Messages address squads; delivery resolves to the leader in that project.
6. **Global uniqueness:**
   - Squads have a globally unique identifier (`slug` recommended).
   - Agents have a globally unique `slug`.
   - OpenCode agent names referenced by squads must be stable.
7. **Cross-squad communication is an allowlisted relationship.** (Use existing `squad_connections` as the policy surface.)

## Scope / Deliverables (v1)
- Global squads CRUD (create/update/list/delete) in API + UI.
- Deploy/undeploy squads to projects.
- Leader assignment and validation (exactly one leader).
- Sessions are created with explicit project context.
- Mail MCP supports squad-addressed messaging (leader-to-leader) with server-side enforcement.
- Remove seniority levels from UI and DB usage.

## Proposed Architecture

### 1) Data Model

#### 1.1 Squads become global
Update `squads`:
- Remove `project_id`.
- Add a globally unique `slug` (recommended) and keep `name` as human-friendly.
- Optional `type/domain` (e.g. `frontend`, `backend`, `security`).

Uniqueness rules:
- `squads.slug` is globally unique.
- Optionally enforce `squads.name` uniqueness too (policy choice).

#### 1.2 Deploy squads into projects
Create `project_squads`:
- `project_id` (FK)
- `squad_id` (FK)
- `enabled` boolean (default true)
- `config` map (default `{}`) for deployment overrides (future-proof)
- unique index on `(project_id, squad_id)`

This is the “deployment” primitive.

#### 1.3 Agents belong to squads (global) and map to OpenCode
Update `agents`:
- Keep `belongs_to :squad` (now global squad).
- Remove `level` (senior/junior/principal).
- Add leader marker:
  - `is_squad_leader: boolean` (exactly one per squad)
- Add `opencode_agent_name: string` (OpenCode agent identifier; e.g. `generalist`, `react-specialist`).

Uniqueness rules:
- `agents.slug` is globally unique.
- `agents.name` may remain non-unique (since slug is canonical).

Leader constraint (DB-level best-effort):
- Add a partial unique index to enforce exactly one leader per squad (`WHERE is_squad_leader = true`).
- Add app-level validation for databases that can’t enforce it perfectly.

Mentorship:
- `mentor_id` and `mentees` are deprecated as a “seniority” mechanism.
- v1: keep fields if needed for backwards compatibility, but stop using them for escalation.

#### 1.4 Sessions must reference project context explicitly
Sessions can no longer derive project via `agent -> squad -> project`.

Update `sessions` (v1):
- Add `project_id` (required) **or** `project_squad_id` (preferred).
- If we use OpenCode subagent child sessions:
  - Store parent-child link (either explicit `parent_session_id` or in `metadata`).

Rationale:
- OpenCode server startup and directory/worktree resolution is per project.
- OpenCode persists the transcript; our DB remains the durable index for who/what/where.

#### 1.5 Squad connections become global policy rules
Existing `squad_connections` remain useful, but their meaning changes:
- A connection defines that squad A is allowed to communicate with squad B.
- Delivery still requires **project context** (which deployment in which project).

Routing rule:
- A message can be delivered only if both squads are deployed to the same project (unless explicitly supporting cross-project messaging as a future feature).

#### 1.6 Mail remains project-scoped but becomes squad-addressed
Mail threads remain scoped to project (`mail_threads.project_id`).

Change semantics:
- Messages are sent **from one squad to another squad** within a project.
- Sender must be the sending squad’s leader.
- Recipient is resolved to the target squad’s leader in that project.

Implementation options:
- v1 (minimal): keep message schema but store `from_squad_id` and `to_squad_id` in `mail_messages.metadata`.
- v2: add explicit columns `from_squad_id`, `to_squad_id`.

### 2) OpenCode Integration

#### 2.1 Agent definitions live in `.opencode/agent/` (and/or global)
We treat OpenCode agent configuration as canonical:
- Global library: `~/.config/opencode/agent/*.md`
- Per-project overrides: `.opencode/agent/*.md`

Resolution order:
1. Project `.opencode/agent/<name>.md` overrides
2. Global `~/.config/opencode/agent/<name>.md`
3. Built-in agents (fallback)

Squads references agents by `opencode_agent_name`.

#### 2.2 Leader orchestrates via subagents
The Squad Leader should:
- be configured to invoke subagents (OpenCode `Task` tool)
- have `permission.task` allowlisting which subagents it can spawn

Subagents:
- are `mode: subagent`
- have tighter tool permissions where appropriate

#### 2.3 Tool permissions enforce the leader boundary
- Only the leader can access inter-squad tools (mail MCP).
- Subagents can be limited to code + read tools, or purpose-specific subsets.

### 3) Squad-to-Squad Communication (Mail MCP)

We evolve the existing mail MCP into **squad-oriented** operations.

Required behavior:
- A leader can send a message to another squad by squad id/slug.
- The system resolves the correct target leader for the target squad deployment.
- Server-side enforcement ensures non-leader agents cannot send inter-squad messages even if misconfigured.

Proposed MCP tool surface (preferred):
- `send_squad_message`:
  - `project_id`
  - `from_squad_id` (optional; inferred from sender agent)
  - `to_squad_id` or `to_squad_slug`
  - `subject`, `body_md`, `importance`, `ack_required`

Escalation:
- Replace “mentor/senior escalation” with “escalate to squad leader”.
  - Subagents escalate internally to their leader.
  - Leader escalates externally to other leaders.

Policy enforcement:
- Use `squad_connections` as the allowlist: deny if no connection exists.

### 4) Naming & Collision Rules (Hard Requirements)

#### 4.1 Squad naming
- Each global squad must have a unique, stable identifier.
- Recommended:
  - `squads.slug` is unique and used for APIs.
  - `squads.name` is human-friendly.

#### 4.2 Agent naming
- Agent `slug` must be globally unique.
- Agent `opencode_agent_name` must map to a configured OpenCode agent.

#### 4.3 Deployment naming
- A project can deploy the same squad at most once.

### 5) UX / UI Requirements

#### 5.1 Global Squad Library
- List global squads (name/type/leader/members).
- Create/edit squads:
  - name/slug/description/type
  - add agents (with `opencode_agent_name`)
  - select leader

#### 5.2 Project View: Deployed Squads
- Show squads deployed to the project.
- Deploy/undeploy.
- “Contact” action opens leader session or opens mail thread.

#### 5.3 Agent View
- Show leader vs subagent.
- Show `opencode_agent_name` and where it’s defined (project override vs global).

### 6) API Requirements (Representative)

Global squads:
- `GET /api/squads` (global)
- `POST /api/squads`
- `PATCH /api/squads/:id`

Deployments:
- `GET /api/projects/:project_id/squads` (deployed squads)
- `POST /api/projects/:project_id/squads/:squad_id/deploy`
- `DELETE /api/projects/:project_id/squads/:squad_id/deploy`

Sessions:
- `POST /api/sessions` requires `project_id` or `project_squad_id`.

Mail:
- `POST /api/mail/send` supports squad addressing (leader-only enforced).

### 7) State Management

This is solved by combining:
- **OpenCode session persistence:** OpenCode retains transcript/state per session ID.
- **Squads DB persistence:** we store session records, project/deployment linkage, and metadata/events.

We do not need a new bespoke “leader memory store” in v1. The key is correct session ↔ project/deployment linkage.

## Example (Concrete)

### Example: “Frontend Squad” template
- Squad:
  - `slug: frontend`
  - `name: Frontend Squad`
- Agents:
  - Leader: `slug: silver-otter`, `opencode_agent_name: generalist`, `is_squad_leader: true`
  - Subagent: `slug: green-panda`, `opencode_agent_name: react-specialist`
  - Subagent: `slug: blue-rock`, `opencode_agent_name: css-accessibility`

Deployments:
- Deploy `frontend` into Project A and Project B via `project_squads`.

Work routing:
- Ticket in Project A assigned to `frontend` → session starts with `project_id=ProjectA`, leader agent `generalist`.
- Leader launches `react-specialist` subagent for implementation.

Mail:
- Frontend leader sends `send_squad_message(project_id=ProjectA, to_squad_slug=backend, ...)`.
- Delivery resolves to Backend Squad’s leader in Project A.

## Migration Plan

### Phase 0: Compatibility-first schema changes
- Add `project_squads` and backfill it from existing `squads.project_id`.
- Add explicit project context to sessions (project_id or project_squad_id) and backfill it.

### Phase 1: Globalize squads
- Remove `squads.project_id`.
- Update queries/endpoints that list squads per project to use `project_squads`.

### Phase 2: Remove seniority
- Remove `agents.level` and any logic that depends on it.
- Update defaults/instructions to use leader/subagent semantics.
- Deprecate mentorship as an escalation primitive.

### Phase 3: Mail becomes squad-to-squad
- Add `send_squad_message` (or equivalent) and route to leaders.
- Use `squad_connections` as allowlist.
- Enforce leader-only behavior server-side.

### Naming collision handling
If existing projects contain squads with the same name/slug that would collide globally:
- Prefer merging only when semantics match.
- Otherwise auto-rename with deterministic prefixes (temporary) and surface a cleanup task for the operator.

## Acceptance Criteria
1. A global squad can be created once and deployed to at least two projects.
2. A project can list its deployed squads and see the assigned leader.
3. Creating a work session includes explicit project context and successfully starts an OpenCode session in the correct project directory.
4. A Squad Leader can launch at least one subagent to complete a task.
5. Mail MCP supports sending a message from Squad A → Squad B inside a project, delivered to Squad B’s leader.
6. “Senior/Junior” levels no longer exist in the product experience.
7. Global uniqueness constraints prevent collisions for `squads.slug` and `agents.slug`.
8. `squad_connections` blocks disallowed squad-to-squad communication.

## Risks / Concerns
- **Large refactor radius:** many code paths assume `squad.project_id`.
- **Migration collisions:** global uniqueness may conflict with existing duplicates.
- **Permission gaps:** must enforce leader-only mail on the server side.
- **Ambiguity:** squad-to-squad messages must always include project context.

## Future Work (v2+)
- Deployment-specific overrides (e.g., per-project member set adjustments) via `project_squads.config`.
- UI to author/manage `.opencode/agent/*.md` directly.
- Stronger session parent/child modeling for leader-launched subagent sessions.
- Cross-project squad messaging (explicitly addressing deployments).
- Structured “squad contracts” (request/response schemas over mail).
