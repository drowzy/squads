# Squads Summary

Squads is a local, multi-agent orchestration app that turns an agentic programming flywheel into a repeatable product: plan, ticket, execute, review, iterate. It optimizes for cheap parallel execution, structured coordination, and safe code changes.

## Core Loop

1. Plan with a high-capability model.
2. Convert the plan into Beads tickets (dependency graph).
3. Execute tickets with fast models in parallel.
4. Review with stronger models and generate follow-up tickets.
5. Repeat until all tickets are closed.

## Architecture (MVP)

- Backend: Phoenix + SQLite, per-project `.squads/` storage.
- Frontend: Vite + React + TanStack + Tailwind (TUI-themed) embedded in Phoenix assets (no esbuild).
- Real-time updates: SSE from backend.
- Dev servers bind to `0.0.0.0` for LAN/mobile access.

## Integrations

- OpenCode: start/manage multiple sessions per project, stream logs/events, send commands/prompts. Read configured models/providers from the OpenCode server (and fall back to config file parsing when needed).
- Beads: source-of-truth ticket graph; Squads mirrors assignment/state for UI.
- Mail (in-house MCP): inbox/outbox, threads, ack/read, and file reservations (DB-only for MVP).
- Git worktrees: isolated changes per agent with senior review gates.

## Conventions

- Agent names: curated, human-friendly `AdjectiveNoun` (e.g., `GreenPanda`, `BlueRock`), with slug form for paths.
- Worktree and branch names: `<agent-slug>-<ticket-key>` (base branch `main`).
- Thread IDs: Beads ticket IDs (e.g., `bd-123`).

## MVP Scope

- Project init and `.squads/config.json`.
- OpenCode session orchestration + logs.
- Beads ticket board with ready/in-progress/blocked views.
- Mailbox + reservations with manual `/check-mail`.
- Worktree creation, PR summary artifact, review queue UI.

## Later Iterations

- Autonomous mail polling and escalation.
- Stronger policy enforcement and automation.
- Richer analytics and multi-project dashboards.
