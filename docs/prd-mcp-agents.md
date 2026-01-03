# PRD: Agent Advanced Instructions + Squad MCP Management

## Summary
Squads should simplify agent creation by hiding advanced fields and consolidate system instructions into a single, optional override. At the same time, MCPs should be configurable at the squad level with Docker MCP catalog discovery and optional auto-installation via Docker.

## Problem
- Agent creation surfaces two system-instruction fields (default + override), increasing cognitive load.
- MCPs are configured only in project config and not exposed in UI, despite a built-in `agent_mail` MCP.
- There is no catalog-driven discovery or guided setup for MCP servers.

## Goals
- Reduce agent creation friction by moving system instruction into a collapsed Advanced section.
- Provide squad-level MCP configuration with catalog discovery and manual entry.
- Use Docker MCP catalog metadata for discovery and setup.
- Prefer Docker Engine API for auto-install; fall back to Docker CLI/Toolkit if needed.

## Non-Goals
- Replacing Docker MCP Toolkit or Docker MCP Gateway.
- Full secrets manager or policy engine in v1.
- Supporting MCP registries beyond Docker MCP.

## Users
- Squad owners and project admins configuring tools per team.
- Power users onboarding external MCP servers quickly.

## Current State
- Create Agent modal: `assets/src/routes/squad.tsx` shows role, level, default system instruction, override, model, name.
- Edit Agent modal: `assets/src/routes/agent.$agentId.tsx` mirrors default + override fields.
- MCP endpoints exist but return empty or stubbed responses: `lib/squads_web/controllers/api/mcp_controller.ex`.
- MCP configuration is read from OpenCode config (`opencode.json`) via `Squads.OpenCode.Config`, with a built-in `agent_mail` MCP.

## Proposed UX
### Agent Creation and Edit
- Primary fields: Role, Level, Model (required), Agent Name.
- Advanced (collapsed by default):
  - Single "System Instruction" textarea.
  - Placeholder text shows the default system instruction derived from role + level.
  - Helper text: "Leave blank to use the default system instruction."
- Behavior:
  - Role/level changes update the placeholder.
  - Empty textarea on submit results in no override set.

### Squad MCP Settings
- Location: Squad details page, new tab "MCP" (or "Tools").
- Sections:
  - Installed MCPs list with status, enable/disable, edit, remove.
  - "Add MCP" flow with two options:
    - Docker MCP Catalog search and import.
    - Custom MCP (manual URL or container config).
- Built-in `agent_mail` MCP appears as installed by default; optionally toggleable.

## Functional Requirements
### Agent Advanced Section
- Replace "Default System Instruction" + "System Instruction Override" with a single advanced field in both create and edit modals.
- Model remains required and stays in the primary section.
- System instruction override is optional and stored only when set.

### Squad MCP Management
- Squad-level MCP configuration stored in DB.
- Support MCP types:
  - Remote MCP: URL + headers + optional auth metadata.
  - Container MCP: image + command/args + env/secrets.
- Enable/disable per squad with status feedback.
- Import from Docker MCP catalog:
  - Use `server.yaml` metadata to prefill image, tags, and required secrets.
  - Optional display of `tools.json` in detail view.

### Auto-Install
- Preferred path: Docker Engine API to pull/run containers and expose a local MCP URL.
- Fallback: use Docker CLI / Desktop Toolkit commands if available.
- If neither is available, allow "manual" configuration without auto-install.

## Non-Functional Requirements
- Secrets are masked in UI and never logged in plaintext.
- MCP list and status load quickly; avoid blocking agent UX.
- Clear error messages for missing Docker runtime or auth issues.

## Data Model (Proposed)
- `squad_mcp_servers`
  - `squad_id`, `name`, `source` (builtin/registry/custom), `type` (remote/container)
  - `image`, `command`, `args`, `url`, `headers`, `enabled`, `status`
  - `secrets` (references only)

- Optional: `agent_mcp_overrides`
  - `agent_id`, `mcp_server_id`, `enabled`

## API (Proposed)
- `GET /api/mcp?squad_id=...` -> list MCP servers with status.
- `POST /api/mcp` -> create MCP server.
- `PATCH /api/mcp/:name` -> update configuration.
- `POST /api/mcp/:name/connect` -> enable/start.
- `POST /api/mcp/:name/disconnect` -> disable/stop.
- `GET /api/mcp/catalog` -> Docker MCP catalog search proxy (server-side cache).

## Integration: Docker MCP Catalog
- Catalog source: `docker/mcp-registry` metadata on GitHub.
- Surface categories and tags from `server.yaml`.
- Provide a direct link to Docker Hub listing for each MCP.

## Detailed Docker MCP Integration Analysis
### Catalog Browsing
- Recommended: ingest the Docker registry repo (`docker/mcp-registry`) and parse `servers/<name>/server.yaml` plus `tools.json` for each entry. This is stable, versioned, and does not require Docker Desktop or CLI on the host.
- Optional: use `docker mcp catalog show docker-mcp` to list servers if the CLI plugin is available. This gives a single source of truth but depends on Docker being installed.
- Fallback: link to `https://hub.docker.com/mcp` for manual browsing.

### Authorization and Secrets
- OAuth for remote servers is handled by Docker MCP Toolkit or the CLI:
  - `docker mcp oauth authorize <provider>` opens a browser login.
  - `docker mcp oauth ls` lists authorized services.
  - `docker mcp oauth revoke <provider>` revokes access.
- Secrets management is handled by the CLI (`docker mcp secret ...`). The exact subcommands need to be verified and wrapped in an Elixir module; the PRD assumes a CLI path rather than storing raw tokens in Squads.

### Gateway and Client Connection
- The MCP Gateway is the runtime aggregator. With Docker Desktop + MCP Toolkit enabled, it runs automatically.
- For manual use, the CLI starts the gateway:
  - `docker mcp gateway run` (stdio)
  - `docker mcp gateway run --port 8080 --transport streaming`
- VS Code uses stdio to launch the gateway directly, which we can reuse for CLI-driven clients:
  ```json
  "mcp": {
    "servers": {
      "MCP_DOCKER": {
        "command": "docker",
        "args": ["mcp", "gateway", "run"],
        "type": "stdio"
      }
    }
  }
  ```

### Server Enablement and Status
- Enable or disable servers using the CLI:
  - `docker mcp server enable <server>`
  - `docker mcp server disable <server>`
  - `docker mcp server ls`
  - `docker mcp server inspect <server>`
- Tool list discovery:
  - `docker mcp tools ls --format=json` (documented in the gateway README).

### Per-Squad Isolation vs Global Docker Config
- `docker mcp` stores config under `~/.docker/mcp/` (global per user).
- In v1, we should treat Docker MCP as a shared runtime and store per-squad allowlists in Squads.
- Strict per-squad isolation would require one of:
  - Running separate gateway instances with isolated config directories (needs CLI support investigation).
  - A custom gateway deployment per squad (out of scope for v1).

## Implementation Plan (Backend-First)
Focus is on Elixir modules and backend components. UI flow changes are deferred.

### Phase 1: Data Model and Core Context
1) **Database migrations**
   - Create `squad_mcp_servers` table:
     - `squad_id` (FK), `name`, `source` (builtin/registry/custom), `type` (remote/container)
     - `image`, `url`, `command`, `args` (json), `headers` (json)
     - `enabled` (bool), `status` (string), `last_error` (text)
     - `catalog_meta` (json) and `tools` (json) for cached registry data
   - Optional join table `squad_mcp_activations` if we need to track shared enablement across squads.

2) **Schemas + Context**
   - `Squads.MCP.Server` schema for `squad_mcp_servers`.
   - Extend `Squads.MCP` context with CRUD, validation, and status updates.

### Phase 2: Catalog Ingestion (Docker MCP Registry)
3) **Catalog fetcher module**
   - `Squads.MCP.Catalog`:
     - Fetch registry metadata from `docker/mcp-registry` (GitHub raw or tarball).
     - Parse `server.yaml` + `tools.json`.
     - Cache results in `squad_mcp_servers.catalog_meta/tools` or separate cache table with TTL.

4) **Catalog API**
   - `GET /api/mcp/catalog` served by `Squads.MCP.Catalog` with search/filter support.

### Phase 3: Docker CLI Integration
5) **Docker MCP CLI wrapper**
   - `Squads.MCP.DockerCLI`:
     - `catalog_show/0`, `server_enable/1`, `server_disable/1`, `server_ls/0`, `server_inspect/1`.
     - `oauth_authorize/1`, `oauth_ls/0`, `oauth_revoke/1`.
     - `tools_ls/0` (JSON parsing when supported).
   - Use `System.cmd/3` for short-lived commands, `Port` for long-running gateway if needed.
   - Add config for CLI path override, with fallback to `docker` in PATH.

6) **Enable/Disable behavior**
   - When a squad enables a server:
     - Persist to DB, then call `docker mcp server enable`.
     - If OAuth required, expose a backend action to trigger `docker mcp oauth authorize`.
   - When disabling:
     - Avoid disabling globally if another squad still requires it (optional activations table).

### Phase 4: Status Sync + Observability
7) **Status sync job**
   - Periodic task to run `docker mcp server ls` and update per-squad statuses.
   - Store `last_seen_at` and `last_error` for support/debugging.

8) **Telemetry + audit**
   - Log enable/disable and auth events (without secrets).

### Phase 5: API Endpoints (No UI changes yet)
9) **Controllers**
   - Expand `SquadsWeb.Api.McpController` to support:
     - `GET /api/mcp?squad_id=...` (list)
     - `POST /api/mcp` (create)
     - `PATCH /api/mcp/:name` (update)
     - `POST /api/mcp/:name/connect` (enable)
     - `POST /api/mcp/:name/disconnect` (disable)
     - `GET /api/mcp/catalog` (catalog list)

10) **Tests**
   - Context tests for CRUD and state transitions.
   - CLI wrapper tests with command stubs (no real Docker dependency).

## Phases
1) Agent advanced section (create + edit) and per-squad MCP CRUD without auto-install.
2) Docker MCP catalog search and import.
3) Auto-install via Docker Engine API; CLI/Toolkit fallback.
4) Enhanced status/health checks and optional auth flows.

## Risks
- Docker runtime might be unavailable or locked down on some systems.
- Long system-instruction defaults may be hard to view if only a placeholder.
- Secrets storage needs careful handling to avoid leaks.

## Open Questions
- Should `agent_mail` be toggleable or always enabled for squads?
- Should MCP status be polled or event-driven?
- Should squad MCPs override or merge with project-level `opencode.json` MCP config?

## References
- Docker MCP Catalog and Toolkit announcement: https://www.docker.com/blog/announcing-docker-mcp-catalog-and-toolkit-beta/
- Docker MCP Catalog (Hub): https://hub.docker.com/mcp
- Docker MCP registry repo: https://github.com/docker/mcp-registry
- Docker MCP docs: https://docs.docker.com/ai/mcp-catalog-and-toolkit/
