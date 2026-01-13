# PRD 003: Global Squads — 009: Enforce global naming uniqueness + migration collision handling

## Background
The PRD requires global identifiers to not collide:
- squads must have a globally unique identifier (`slug` recommended)
- agents must have globally unique slugs

When moving from project-scoped squads to global squads, duplicates will exist (e.g. multiple projects each had a “Frontend Squad”). We need a deterministic migration/cleanup strategy.

## PRD References
- `.squads/prds/003-document.md:220` (Naming & Collision Rules)
- `.squads/prds/003-document.md:321` (Migration: naming collision handling)
- `.squads/prds/003-document.md:333` (Acceptance #7: uniqueness constraints prevent collisions)

## Dependencies
- Must complete `PRD 003: Global Squads — 004` (squads are global).
- Must complete `PRD 003: Global Squads — 006` (agents refactor).

## Current Code (Pointers)
- Squad schema currently has no slug: `lib/squads/squads/squad.ex`
- Agents are only unique per squad today: `priv/repo/migrations/20251231105748_create_core_tables.exs` (unique index on `(squad_id, slug)`)

## Goal
Add strong, DB-enforced global uniqueness for:
- `squads.slug`
- `agents.slug`

…and handle existing collisions safely.

## Requirements
1. Add `squads.slug` (string) and enforce global uniqueness.
2. Enforce global uniqueness for `agents.slug`.
3. Provide deterministic collision handling during migration.

## Tasks
1. **Squads: add slug + backfill**
   - Add `squads.slug` column.
   - Backfill slug from name (kebab-case).
   - Collision rule: if slug exists, append a short suffix (e.g. `-<4-6 char>` derived from id).
   - Add unique index on `squads.slug`.
2. **Agents: enforce global slug uniqueness**
   - Replace unique index `(squad_id, slug)` with unique index `(slug)`.
   - Backfill collisions:
     - If two agents share same slug, rename one using a deterministic prefix (e.g. `<squad_slug>-<agent_slug>`).
   - Update changeset validations and error messages.
3. **Update API/UI expectations**
   - Ensure UI uses slugs only as display identifiers (do not break primary key usage).
4. **Docs/Seeds**
   - Update `priv/repo/seeds.exs` to generate unique slugs.

## Acceptance Criteria
- DB enforces global uniqueness for `squads.slug` and `agents.slug`.
- Migration is idempotent and does not fail on pre-existing duplicates.
- Existing data is preserved (no silent drops).

## Test Plan
- `mix ecto.migrate`
- `mix test`
- Manual: create two squads with same name and verify slug collision handled.
