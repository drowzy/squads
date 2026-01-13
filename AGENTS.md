# AGENTS.md (Squads)

This file is for agentic coding tools operating in this repository.

## Non-negotiable behavior

- Do not write code before stating assumptions.
- Do not claim correctness you haven’t verified (tests/logs/curl/etc.).
- Do not handle only the happy path; consider validation, nil/error branches, timeouts, and partial failures.
- Prefer minimal, surgical changes in existing codebases.
- Do not `git commit`/`git push` unless explicitly asked.

## Project overview

- Backend: Elixir + Phoenix (`lib/`, `config/`). HTTP server uses Bandit.
- DB: SQLite via Ecto (`ecto_sqlite3`).
- Frontend: React + TypeScript + Vite in `assets/`.
  - Vite build outputs to `priv/static/` (see `assets/vite.config.ts`).
  - TanStack Router plugin generates `assets/src/routeTree.gen.ts`.

## Build / test / lint / format

### Backend (Elixir)

- Install deps + setup DB:
  - `mix setup`
  - Equivalent: `mix deps.get && mix ecto.setup`
- Run server (dev):
  - `mix phx.server`
  - The dev config includes a watcher that runs `npm run dev` in `assets/`.
- Run tests (default):
  - `mix test`
  - Note: `mix test` alias runs `ecto.create` + `ecto.migrate` quietly first (see `mix.exs`).
- Run a single test:
  - By file: `mix test test/path/to/foo_test.exs`
  - By line: `mix test test/path/to/foo_test.exs:123`
  - By tag: `mix test --only some_tag`
  - Show per-test output: `mix test --trace ...`
- Format:
  - `mix format`
  - Check only: `mix format --check-formatted`
  - Formatting config: `.formatter.exs` (includes `Phoenix.LiveView.HTMLFormatter`).
- “Precommit” check (strict-ish):
  - `mix precommit`
  - Alias: compile with warnings as errors, `deps.unlock --unused`, format, test.

### Frontend (assets)

- Install deps:
  - `npm --prefix assets install`
- Dev build/watch (usually started by Phoenix watcher):
  - `npm --prefix assets run dev`
- Production build:
  - `npm --prefix assets run build`
- Preview build:
  - `npm --prefix assets run preview`
- Typecheck (there is no explicit script; TS is `strict: true`):
  - `npx --yes tsc -p assets/tsconfig.json --noEmit`

### Linting

- Elixir: no Credo/Dialyzer config detected; rely on `mix format`, compiler warnings, and tests.
- Frontend: no ESLint/Prettier config detected; rely on TypeScript strictness and existing code style.

## Common workflows

- Reset dev DB:
  - `mix ecto.reset`
- Run migrations:
  - `mix ecto.migrate`
- Seeds:
  - `mix run priv/repo/seeds.exs`

## Code style guidelines

### Elixir / Phoenix

Formatting and layout
- Run `mix format` for any Elixir/HEEx changes.
- Keep modules structured in this order (typical in this repo):
  - `use ...`
  - `require ...`
  - `alias ...`
  - module attributes (`@...`)
  - public functions
  - `defp` helpers

Imports / aliasing
- Prefer `alias` over `import`.
- Avoid `import` except for small, local scopes or highly idiomatic cases.
- Use `require Logger` and structured logs (keyword metadata) for operational errors.

Naming
- Modules: `Squads.*` for domain, `SquadsWeb.*` for web layer.
- Functions/vars: `snake_case`.
- File names: `snake_case.ex` matching module names.

Error handling and control flow
- Prefer explicit `{:ok, value} | {:error, reason}` returns for domain functions.
- In controllers, prefer `with ... do ... else ... end` and return `{:error, ...}` for the fallback controller.
  - Example pattern: cast/lookup/list in `with`, map `nil`/`:error` to `{:error, :not_found}`.
- Preserve error information at boundaries:
  - Validation errors often come back as `{:error, {:validation, changeset}}` from artifacts and are translated to `{:error, changeset}` at the controller boundary.
- Avoid raising for expected failures (bad input, missing records, IO issues).

HTTP/API patterns
- Controllers use `action_fallback SquadsWeb.FallbackController`.
- Prefer `render(conn, :action, assigns...)` over building JSON by hand unless needed.

Security and unsafe inputs
- Treat any path/command inputs as hostile.
- For filesystem artifacts under `.squads/`, always use the established path safety helpers and validation schema code.
- Avoid shelling out with untrusted strings; prefer structured argument lists.

### TypeScript / React (assets)

Type safety
- TS is `strict: true` (`assets/tsconfig.json`). Prefer typed objects/interfaces over `any`.
- Use `type` imports for types when helpful (repo already does this).

Imports
- Keep imports grouped: external packages first, then internal relative imports.
- Keep import lists readable; don’t micro-optimize ordering unless there’s an existing pattern in the file.

Components and hooks
- Prefer function components.
- Keep state updates and query cache updates localized; be careful with streaming/event-source code paths.

Generated files
- Do not hand-edit `assets/src/routeTree.gen.ts`; regenerate via `npm --prefix assets run build`.
- Vite output goes to `priv/static/`; don’t manually edit built assets.

## Repository rule files

### Cursor
- No Cursor rule files found (`.cursorrules` or `.cursor/rules/`).

### GitHub Copilot
- A Copilot instruction file exists at `.github/copilot-instructions.md`.
- Note: it appears to describe a different project (“Beads”, Go + SQLite + Cobra).
  - Treat it as potentially stale/mismatched for this repo.
  - If you need to follow it anyway, the key directives are:
    - Always write tests for new features.
    - Run lint/tests before committing.
    - Use the project’s own issue tracking workflow (it mentions `bd`/JSONL).
