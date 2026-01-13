# PRD 003: Global Squads — 005: API for Global Squads CRUD + deploy/undeploy deployments

## Background
After squads are global (no `project_id` on squads), we need API endpoints that:
- manage the global squad library (CRUD)
- deploy/undeploy squads into projects

We also need to keep the existing UI working where possible (currently it creates squads under a project).

## PRD References
- `.squads/prds/003-document.md:85` (deliverables: global squads CRUD + deploy/undeploy)
- `.squads/prds/003-document.md:253` (API requirements section)
- `.squads/prds/003-document.md:74` (squads are templates; deployments per project)

## Dependencies
- Must complete `PRD 003: Global Squads — 004` (squads are global in DB + schema).

## Current Code (Pointers)
- Router: `lib/squads_web/router.ex` (current squad routes are project-nested for index/create)
- SquadController: `lib/squads_web/controllers/api/squad_controller.ex` (create currently requires `project_id`)
- SquadJSON: `lib/squads_web/controllers/api/squad_json.ex`

## Goal
Expose a clean backend API for global squad templates and project deployments.

## Requirements
1. Global squads CRUD:
   - `GET /api/squads` (list global squads)
   - `POST /api/squads` (create global squad)
   - `PATCH /api/squads/:id` (update)
   - `DELETE /api/squads/:id` (delete)
2. Project deployments:
   - `GET /api/projects/:project_id/squads` (list deployed squads)
   - `POST /api/projects/:project_id/squads/:squad_id/deploy`
   - `DELETE /api/projects/:project_id/squads/:squad_id/deploy`

## Tasks
1. **Router updates** (`lib/squads_web/router.ex`):
   - Add the global `GET /api/squads` and `POST /api/squads` routes.
   - Add deploy/undeploy routes under projects.
2. **Controller changes**:
   - Add `index` + `create` actions for global squads.
   - Add deploy/undeploy actions (either in `SquadController` or a new `ProjectSquadController`).
     - Deploy action creates a `project_squads` row.
     - Undeploy deletes or disables that row.
3. **Context functions**:
   - Add functions in `Squads.Squads` context:
     - `list_squads/0` (global)
     - `deploy_squad(project_id, squad_id)`
     - `undeploy_squad(project_id, squad_id)`
4. **JSON rendering**:
   - Decide the response shape for deployed squads. Recommended:
     - keep returning a `Squad`-shaped JSON object + include `project_id` from the request context.
   - Ensure global list returns squads without project fields.
5. **Backward compatibility** (optional but recommended):
   - Keep `POST /api/projects/:project_id/squads` as a “create + deploy” convenience:
     - create a new global squad
     - deploy it to the project
   - This avoids breaking the existing UI immediately.
6. **Tests**:
   - Add controller tests for deploy/undeploy.
   - Add tests for global squads list/create.

## Acceptance Criteria
- Global squads can be created/listed without any project.
- A squad can be deployed to and undeployed from a project.
- Project squad listing returns only deployed squads.

## Test Plan
- `mix test test/squads_web/controllers/api/squad_controller_test.exs`
- `mix test test/squads/squads_test.exs` (if exists; otherwise add targeted tests in the closest context)
