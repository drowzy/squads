# PRD 003: Global Squads — 002: Add explicit project context to Sessions

## Background
With global squads, sessions can no longer infer project context through `agent -> squad -> project`. We must attach project context directly to the `sessions` table so session startup can:
- locate the correct project path/worktree
- start/ensure the right OpenCode server

This issue adds `sessions.project_id` and updates session creation flows (API + UI) to populate it.

## PRD References
- `.squads/prds/003-document.md:137` (sessions must reference project context explicitly)
- `.squads/prds/003-document.md:71` (must stop relying on `squad.project_id` implicitly)
- `.squads/prds/003-document.md:303` (Migration Phase 0: add explicit project context to sessions)
- `.squads/prds/003-document.md:329` (Acceptance #3: create work session with explicit project context)

## Dependencies
- Recommended: complete `PRD 003: Global Squads — 001` first (it introduces deployments, but this issue can still proceed without it).

## Current Code (Pointers)
- Session schema: `lib/squads/sessions/session.ex` (currently derives project via `has_one :project, through: [...]`)
- Session normalize: `lib/squads/sessions/lifecycle.ex:17` (normalizes params; currently has no `project_id`)
- Session API: `lib/squads_web/controllers/api/session_controller.ex:68` (`POST /api/sessions`)
- Start session API: `lib/squads_web/controllers/api/session_controller.ex:88` (`POST /api/sessions/start`)
- UI start session call: `assets/src/api/queries.ts:1048` (`useCreateSession()` calls `/sessions/start` without `project_id`)
- UI usage: `assets/src/routes/squad.tsx:422` (calls `createSession.mutateAsync({ agent_id, title })`)

## Goal
Ensure every new session is created with an explicit `project_id`, and existing sessions are backfilled.

## Requirements
1. Add `project_id` column to `sessions`.
2. Backfill existing sessions.
3. Require/ensure `project_id` is provided in the session create/start API.
4. Update the UI to include `project_id` when starting a session.

## Tasks
1. **DB migration**: add `project_id` to `sessions`.
   - Add `project_id` as `references(:projects, type: :binary_id, on_delete: :delete_all)`.
   - For SQLite compatibility, consider:
     - add column nullable first
     - backfill
     - (optional later issue) enforce `null: false` by table rewrite
2. **Backfill** existing session rows:
   - Use the current join path `sessions.agent_id -> agents.squad_id -> squads.project_id` to set `sessions.project_id`.
   - Ensure migration is safe if some rows are missing associations (use best-effort + leave nil, but log/flag if possible).
3. **Update `Squads.Sessions.Session` schema**:
   - Add `belongs_to :project, Squads.Projects.Project`.
   - Add field to `@required_fields` (or enforce in changeset once UI/API updated).
4. **Update session param normalization**:
   - Extend `Squads.Sessions.Lifecycle.normalize_params/1` to accept `project_id`.
5. **Update SessionController**:
   - `POST /api/sessions` and `POST /api/sessions/start` must accept `project_id`.
   - Return `{:error, :missing_project_id}` (or changeset error) if missing.
6. **Update UI**:
   - Update `useCreateSession()` usage so payload includes `project_id: activeProject.id`.
   - Ensure callers have access to `activeProject` (e.g. route already has `useActiveProject`).
7. **Tests**:
   - Add a controller test that `POST /api/sessions/start` fails without `project_id`.
   - Add a test that succeeds with `project_id` and persists it.

## Acceptance Criteria
- `sessions.project_id` exists and is populated for newly created sessions.
- Existing sessions are backfilled with the correct project.
- `POST /api/sessions/start` includes/requires `project_id` and the UI sends it.

## Test Plan
- `mix ecto.migrate`
- `mix test test/squads_web/controllers/api/session_controller_test.exs`
- Manual: start a session from the UI and confirm session shows correct project linkage.
