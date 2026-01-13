# PRD 003: Global Squads — 008: UI updates for Global Squad Library + Project Deployments

## Background
The current UI (`/squad`) assumes squads are created per project. In the new model:
- Squads are global templates.
- Projects deploy squads.
- Users manage the deployed squads per project.

This issue updates the UI to reflect that new mental model.

## PRD References
- `.squads/prds/003-document.md:235` (UX/UI requirements)
- `.squads/prds/003-document.md:85` (deliverables include UI for global squads + deployments)
- `.squads/prds/003-document.md:279` (concrete example: deploy squad to multiple projects)

## Dependencies
- Must complete `PRD 003: Global Squads — 005` (API for global squads + deploy/undeploy).
- Must complete `PRD 003: Global Squads — 006` (leader flag + OpenCode agent name in API).

## Current Code (Pointers)
- Main UI route: `assets/src/routes/squad.tsx`
- API hooks: `assets/src/api/queries.ts` (`useSquads`, `useCreateSquad`, etc.)

## Goal
Update the UI so an operator can:
1. See global squads (library)
2. Deploy/undeploy squads into the active project
3. See deployed squads in the active project
4. See which agent is the leader

## Requirements
- The UI must keep a clear distinction between:
  - **Global squads** (templates)
  - **Deployed squads** (project context)

## Tasks
1. **API hooks**:
   - Add `useGlobalSquads()` to query `GET /api/squads`.
   - Add `useDeploySquad()` / `useUndeploySquad()` for deployments.
   - Update `useSquads(projectId)` to remain “deployed squads for project”.
2. **Squad page layout changes** (`assets/src/routes/squad.tsx`):
   - Rename UI language from “Create Squad” to “Create Global Squad” (if supported) or “Deploy Squad”.
   - Add a panel/modal to pick a global squad and deploy it into the active project.
   - Keep the existing list rendering for deployed squads.
3. **Leader display**:
   - In each squad card, identify which agent is leader (badge).
   - If leader is missing, show a warning state.
4. **Create flow** (pick one):
   - Option A: allow creating a global squad and immediately deploying it.
   - Option B: separate flows (create in library first, then deploy).
5. **Messaging UI**:
   - Update copy/behavior to reflect leader-to-leader messaging (if issue 007 shipped).

## Acceptance Criteria
- Operator can deploy a global squad into the active project from the UI.
- Deployed squads list updates correctly.
- Leader is visible in the UI.

## Test Plan
- Manual smoke test:
  - create a global squad
  - deploy into two projects
  - verify both projects show the same squad deployed
