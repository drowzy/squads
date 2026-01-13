# PRD 003: Global Squads — 006: Agent changes (Leader flag + OpenCode agent mapping) + remove senior/junior

## Background
The PRD replaces seniority levels with a **Squad Leader** concept. Squads are composed of agents, where exactly one agent is the leader and all others are subagents.

We also want our agents to map cleanly to OpenCode agent configuration:
- store an `opencode_agent_name` (e.g. `generalist`, `react-specialist`)
- use OpenCode for prompts/models/tools rather than baking it into our DB

## PRD References
- `.squads/prds/003-document.md:117` (agent model changes: remove level; add leader marker; add `opencode_agent_name`)
- `.squads/prds/003-document.md:76` (exactly one leader per squad)
- `.squads/prds/003-document.md:88` (deliverable: leader assignment + validation)
- `.squads/prds/003-document.md:332` (Acceptance #6: senior/junior levels removed)

## Dependencies
- Recommended to complete after `PRD 003: Global Squads — 004` (global squads), but can be done earlier if it doesn’t depend on `squad.project_id`.

## Current Code (Pointers)
- Agent schema: `lib/squads/agents/agent.ex` (`role`, `level`, `mentor_id`)
- Roles config: `lib/squads/agents/roles.ex` (generates instructions using level)
- Agent JSON: `lib/squads_web/controllers/api/squad_json.ex:66` (returns `level`, `role`, `system_instruction`)
- DB migration adding level: `priv/repo/migrations/20251231160000_add_role_level_system_instruction_to_agents.exs`

## Goal
Refactor the agent model to:
- remove levels
- add a leader flag
- map agents to OpenCode agent configs

## Requirements
1. Add `agents.is_squad_leader` boolean.
2. Add `agents.opencode_agent_name` string.
3. Remove `agents.level` from product usage (and eventually from DB).
4. Enforce “exactly one leader per squad” (DB-level if possible + app-level validation).

## Tasks
1. **DB migration**:
   - Add `is_squad_leader` (default false, not null).
   - Add `opencode_agent_name` (string, nullable initially).
   - Remove `level` column (if SQLite migration is too risky, mark it deprecated first and remove in a later cleanup).
   - Add a partial unique index to enforce one leader per squad:
     - unique on `squad_id` where `is_squad_leader = true`.
2. **Update `Squads.Agents.Agent` schema**:
   - Add fields.
   - Remove `level` from required fields + changeset validations.
   - Add validation:
     - if `is_squad_leader` is true, ensure no other leader exists in the same squad.
3. **Update `Squads.Agents.Roles`**:
   - Remove the `level` concept from system instruction generation.
   - Introduce leader-specific vs subagent-specific guidance (based on `is_squad_leader`).
4. **Update JSON outputs**:
   - Update `SquadJSON.agent_data/1` to return `is_squad_leader` and `opencode_agent_name`.
   - Remove or null out `level`.
5. **Update UI forms** (minimal):
   - Agent create/edit UI should allow setting:
     - `is_squad_leader` (checkbox)
     - `opencode_agent_name` (text input)
   - Remove level dropdown.

## Acceptance Criteria
- Agent create/update supports leader flag and OpenCode agent name.
- Exactly one leader can be set for a squad.
- UI and API no longer expose “junior/senior/principal” as a user concept.

## Test Plan
- `mix test test/squads_web/controllers/api/agent_controller_test.exs` (or closest)
- `mix test test/squads/agents/*`
- Manual: create agents in UI, assign one as leader, verify second leader assignment fails.
