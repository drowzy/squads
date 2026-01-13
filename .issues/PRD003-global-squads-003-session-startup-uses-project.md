# PRD 003: Global Squads — 003: Refactor OpenCode session startup to use `sessions.project_id`

## Background
Today session startup still assumes project context via `agent -> squad -> project`.

Specifically, OpenCode server startup and directory resolution in `Squads.Sessions.Lifecycle` preload the agent’s squad + project and use `squad.project_id` and `squad.project.path`.

Once squads become global, that chain breaks. This issue changes session startup to use `sessions.project_id` as the source of truth.

## PRD References
- `.squads/prds/003-document.md:137` (sessions must reference project context explicitly)
- `.squads/prds/003-document.md:65` (current state: startup assumes `agent -> squad -> project`)
- `.squads/prds/003-document.md:271` (state management uses OpenCode sessions + our DB)
- `.squads/prds/003-document.md:329` (Acceptance #3: start OpenCode session in correct project directory)

## Dependencies
- Must complete `PRD 003: Global Squads — 002` first (sessions must have `project_id`).

## Current Code (Pointers)
- Startup orchestration: `lib/squads/sessions/lifecycle.ex:57` (`start_opencode_session_orchestration/3`)
- Directory resolution: `lib/squads/sessions/lifecycle.ex:455` (`resolve_session_directory/2`)
- Session schema currently derives project via through-association: `lib/squads/sessions/session.ex:31`

## Goal
OpenCode session startup and worktree directory resolution must use `session.project_id` + `Project.path`, not `squad.project_id`.

## Tasks
1. **Update `start_opencode_session_orchestration/3`**:
   - Stop preloading `agent.squad.project` as the primary way to get project.
   - Instead:
     - load `project = Projects.get_project(session.project_id)` (or via Repo)
     - call `Squads.OpenCode.Server.ensure_running(session.project_id, project.path)`
   - Keep existing fallback behavior only if strictly needed for backwards compatibility.
2. **Update directory resolution**:
   - In `resolve_session_directory/2`, when no explicit worktree path is provided, resolve to `project.path` via `session.project_id`.
   - Avoid reaching into `squad.project_id`.
3. **Update `Squads.Sessions.Session` schema**:
   - Replace `has_one :project, through: [...]` with `belongs_to :project`.
   - Keep `has_one :squad, through: [:agent, :squad]` if still valid.
4. **Update any call sites** that expect `session.project` to be present via preload-through.
   - Grep for `session.project` or `:project, through:` usage.
5. **Tests**:
   - Add/adjust tests around `Sessions.create_and_start_session` to ensure it uses `project_id`.
   - Ideally mock/stub OpenCode server calls (if tests already use Mox for OpenCode client).

## Acceptance Criteria
- Starting a session succeeds using only `session.project_id` to resolve project path.
- No remaining runtime dependency on `squad.project_id` in session startup.
- Session directory resolution defaults to the correct project path.

## Test Plan
- `mix test test/squads/sessions/*`
- `mix test test/squads_web/controllers/api/session_controller_test.exs`
- Manual: create/start a session via UI and confirm OpenCode server starts for the correct project.
