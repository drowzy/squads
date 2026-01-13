# PRD 003: Global Squads — 004: Globalize `squads` (remove `project_id`) + update core schemas

## Background
The core change in the PRD is that **squads are global templates**, not owned by a project. Projects get deployments via `project_squads`.

This issue performs the structural migration:
- remove `squads.project_id`
- update Ecto schemas and core queries so the system no longer assumes `Squad belongs_to Project`

This must be done before we can correctly build global squad CRUD + deployment UX.

## PRD References
- `.squads/prds/003-document.md:97` (Squads become global: remove `project_id`)
- `.squads/prds/003-document.md:74` (Key decision: squads are templates, not project-owned)
- `.squads/prds/003-document.md:307` (Migration Phase 1: remove `squads.project_id`)
- `.squads/prds/003-document.md:336` (Risk: large refactor radius; many paths assume `squad.project_id`)

## Dependencies
- Must complete:
  - `PRD 003: Global Squads — 001` (deployments exist)
  - `PRD 003: Global Squads — 003` (session startup no longer depends on `squad.project_id`)

## Current Code (Pointers)
- Squad schema: `lib/squads/squads/squad.ex` (`belongs_to :project`, `@required_fields` includes `project_id`)
- Project schema: `lib/squads/projects/project.ex` (`has_many :squads`)
- Squad JSON: `lib/squads_web/controllers/api/squad_json.ex` (includes `project_id`)
- Squad queries: `lib/squads/squads.ex` (filters by `s.project_id` and preloads `:project`)

## Goal
Make `Squad` a global entity and ensure the application compiles and passes tests with `project_squads` as the only project association.

## Tasks
1. **DB migration**: remove `project_id` from `squads`.
   - Preferred: try `alter table(:squads) do remove :project_id end` and verify it works with `ecto_sqlite3`.
   - If SQLite limitations block it, implement a safe table-rewrite migration:
     - create a new squads table without `project_id`
     - copy data
     - swap tables
     - recreate indexes
   - Validate that foreign key references from `agents` etc. still function.
2. **Update `Squads.Squads.Squad` schema**:
   - Remove `belongs_to :project`.
   - Remove `project_id` from `@required_fields` and changeset.
   - Keep/ensure associations needed for deployments (`many_to_many :projects` via `project_squads`).
3. **Update `Squads.Projects.Project` schema**:
   - Remove `has_many :squads`.
   - Keep `many_to_many :squads, join_through: "project_squads"` (added in issue 001).
4. **Update squad context queries** (`lib/squads/squads.ex`):
   - Remove any filtering by `s.project_id`.
   - Project-scoped listing must join via `project_squads`.
   - Remove preloads that assume `squad.project` exists.
5. **Update JSON rendering** (`SquadJSON`):
   - Stop reading `squad.project_id` / `squad.project` directly.
   - For `GET /api/projects/:project_id/squads`, it’s acceptable to include `project_id` in the response using the request context (not the squad record).
   - For global squad endpoints (later issue), `project_id` should be `null` or omitted.
6. **Fix compilation errors** across the codebase:
   - Grep for `.project_id` usage on squads.
   - Grep for `Repo.preload(:project)` on squad.

## Acceptance Criteria
- `squads` table no longer has a `project_id` column.
- The app compiles and boots.
- Existing functionality that lists squads for a project still works via deployments.
- No module assumes `Squad belongs_to Project`.

## Test Plan
- `mix ecto.migrate`
- `mix test`
- Manual: load the squad page and confirm squads display for the active project.
