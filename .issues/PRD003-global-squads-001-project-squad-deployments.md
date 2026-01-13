# PRD 003: Global Squads — 001: Add Squad Deployments (`project_squads`) + list deployed squads

## Background
Today a squad is created *inside* a project (via `squads.project_id`). The PRD changes the primitive: squads become global templates, and projects get **deployments** of those squads.

This issue introduces the deployment join table (`project_squads`) and switches *project squad listing* to be driven by deployments. This is the foundation for making squads global later.

## PRD References
- `.squads/prds/003-document.md:107` (create `project_squads` join table)
- `.squads/prds/003-document.md:85` (v1 deliverable: deploy/undeploy squads)
- `.squads/prds/003-document.md:303` (Migration Phase 0: add + backfill `project_squads`)

## Dependencies
- None

## Current Code (Pointers)
- DB schema: `priv/repo/migrations/20251231105748_create_core_tables.exs` (creates `squads` with `project_id`)
- Squad model: `lib/squads/squads/squad.ex` (`belongs_to :project` today)
- Project model: `lib/squads/projects/project.ex` (`has_many :squads` today)
- Listing logic: `lib/squads/squads.ex` (`list_squads_for_project/1` filters by `s.project_id`)
- API: `lib/squads_web/controllers/api/squad_controller.ex:20` (`GET /api/projects/:project_id/squads`)

## Goal
Create `project_squads` (deployment primitive) and make `GET /api/projects/:project_id/squads` list squads via deployments.

Important: **Do not remove `squads.project_id` yet** in this issue. Keep compatibility while we build new primitives.

## Requirements
1. Add a new `project_squads` table.
2. Backfill deployment rows for existing squads.
3. Add an Ecto schema for deployments.
4. Update list queries to use deployments.

## Tasks
1. **DB migration**: create `project_squads`.
   - Columns:
     - `id` (binary_id)
     - `project_id` (FK to `projects`, `on_delete: :delete_all`)
     - `squad_id` (FK to `squads`, `on_delete: :delete_all`)
     - `enabled` boolean (default true)
     - `config` map (default `%{}`)
     - timestamps
   - Indexes:
     - unique index on `(project_id, squad_id)`
     - index on `project_id`
     - index on `squad_id`
2. **Backfill** `project_squads` from current `squads` rows.
   - Insert `(project_id, squad_id)` for every existing squad.
   - Ensure it’s idempotent (safe to run once; no duplicate rows).
3. **Add schema module** `Squads.Squads.ProjectSquad`.
   - `belongs_to :project, Squads.Projects.Project`
   - `belongs_to :squad, Squads.Squads.Squad`
4. **Update Ecto associations**:
   - In `Squads.Projects.Project`: add a `many_to_many :squads, join_through: "project_squads"` (or `has_many :project_squads` + through).
   - In `Squads.Squads.Squad`: add a `many_to_many :projects, join_through: "project_squads"` (or `has_many :project_squads`).
   - Keep the existing `belongs_to :project` association *for now* (until the global migration issue).
5. **Update list query**:
   - Change `Squads.Squads.list_squads_for_project/1` to query squads via `project_squads` join (filter `enabled = true`).
   - Ensure `SquadsWeb.API.SquadController.index` still works unchanged.
6. **Tests**:
   - Add/update tests to ensure project squad listing is driven by deployments.
   - Minimal test: create a squad, create a `project_squads` row, ensure it appears in `GET /api/projects/:project_id/squads`.

## Acceptance Criteria
- `project_squads` table exists with the expected columns/indexes.
- Existing data is backfilled (each existing squad has exactly one deployment to its prior project).
- `GET /api/projects/:project_id/squads` returns squads via deployments.
- No behavioral change to squad create/update/delete endpoints in this issue.

## Test Plan
- `mix ecto.migrate`
- `mix test test/squads_web/controllers/api/squad_controller_test.exs`
- `mix test test/squads/squad_connections_test.exs` (sanity: should not regress)
