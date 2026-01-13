# PRD 003: Global Squads — 007: Squad-to-squad communication (Leader ↔ Leader) via Mail MCP

## Background
We already have:
- `squad_connections` (a graph of allowed squad relationships)
- Mail tables for messaging agents inside a project
- An MCP server named `agent_mail` that exposes tools like `send_message` and `escalate`

The PRD changes the semantics:
- mail/MCP should be **squad-to-squad**
- messages are **leader-to-leader**
- `squad_connections` acts as an allowlist

## PRD References
- `.squads/prds/003-document.md:196` (Mail MCP becomes squad-oriented; propose `send_squad_message`)
- `.squads/prds/003-document.md:157` (mail stays project-scoped but is squad-addressed)
- `.squads/prds/003-document.md:149` (squad_connections becomes global allowlist policy)
- `.squads/prds/003-document.md:331` (Acceptance #5: Squad A → Squad B delivered to B’s leader)
- `.squads/prds/003-document.md:334` (Acceptance #8: squad_connections blocks disallowed comms)

## Dependencies
- Must complete `PRD 003: Global Squads — 006` (leader flag exists).
- Must complete `PRD 003: Global Squads — 005` (deployments exist + project context for squads is clear).

## Current Code (Pointers)
- MCP tools: `lib/squads/mcp.ex` (`handle_request("agent_mail", ...)`)
- Mail context: `lib/squads/mail.ex` (`send_message/1` expects `to: [agent_id]`)
- Squad message endpoint: `lib/squads_web/controllers/api/squad_controller.ex:143` (sends to all agents in target squad)

## Goal
Implement leader-to-leader messaging:
- A squad leader can message another squad (by id/slug) within a project.
- Delivery resolves to the recipient squad leader.
- Server-side enforcement prevents non-leaders from using squad-to-squad messaging.

## Requirements
1. Add a new MCP tool `send_squad_message` (or modify existing `send_message` to support squad addressing).
2. Update `escalate` semantics: escalation should go to squad leader (not mentor/senior).
3. Update the HTTP squad message endpoint to deliver to leaders, not all agents.
4. Enforce allowlist via `squad_connections`.

## Tasks
1. **MCP tool** (`lib/squads/mcp.ex`):
   - Add `send_squad_message` tool definition in `list_tools`.
   - Implement handler that accepts:
     - `project_id`
     - `from_squad_id` (optional)
     - `to_squad_id` or `to_squad_slug`
     - `sender_agent_id` (required for enforcement)
     - `subject`, `body_md`, `importance`, `ack_required`
2. **Routing logic**:
   - Verify `sender_agent_id` belongs to `from_squad_id` and is the squad leader.
   - Resolve `to_squad_id` to that squad’s leader agent.
   - Verify `squad_connections` allows communication between the squads.
   - Verify both squads are deployed to the same `project_id` (v1 rule).
   - Call `Mail.send_message/1` with `to: [leader_agent_id]`.
   - Store `from_squad_id`/`to_squad_id` in `mail_messages.metadata` (v1 minimal approach).
3. **Escalation**:
   - Update MCP `escalate` tool implementation to route to the agent’s squad leader (not mentor).
   - Update tool description accordingly.
4. **HTTP API**:
   - Update `POST /api/squads/:id/message` to:
     - deliver only to the target squad leader
     - enforce allowlist
     - require/validate project context
5. **Tests**:
   - Happy path: leader A can message leader B when connected.
   - Failure path: non-leader cannot send.
   - Failure path: no connection → forbidden.

## Acceptance Criteria
- Leader-to-leader messages are delivered to exactly one recipient (the leader).
- Non-leaders are blocked from squad-to-squad messaging.
- `squad_connections` is enforced.

## Test Plan
- `mix test test/squads_web/controllers/api/squad_connection_controller_test.exs`
- Add new tests in an appropriate location for MCP mail routing.
