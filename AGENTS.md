## Issue Tracking with GitHub Issues

**IMPORTANT**: This project uses **GitHub Issues** for ALL issue tracking.

Squads syncs and operates on GitHub issues labeled `squads`. Avoid duplicating tracking systems (no bd/beads, no ad-hoc TODO files).

### Labels / Conventions

- `squads` - Marks issues that should be synced into Squads
- `type:<bug|feature|task|epic|chore>`
- `priority:<0-4>`
- `status:<in_progress|blocked>`
- `agent:<slug>` - Which agent is working the ticket

### Claim / Workflow

- Claim sets the GitHub assignee to the authenticated user (token owner) and adds:
  - `agent:<slug>`
  - `status:in_progress`
- Block sets `status:blocked`
- Closing a ticket closes the GitHub issue

### Configuration

Squads needs to know which repo to use:

- Preferred: set `integrations.github.repo` in the project `.squads/config.json` (value `owner/repo`)
- Fallback: `git remote get-url origin` is parsed when present

Squads needs a GitHub token in one of:

- `GITHUB_TOKEN` (preferred)
- `GH_TOKEN`
- `GITHUB_PAT`

### Managing AI-Generated Planning Documents

AI assistants often create planning and design documents during development:
- PLAN.md, IMPLEMENTATION.md, ARCHITECTURE.md
- DESIGN.md, CODEBASE_SUMMARY.md, INTEGRATION_PLAN.md
- TESTING_GUIDE.md, TECHNICAL_DESIGN.md, and similar files

**Best Practice: Use a dedicated directory for these ephemeral files**

**Recommended approach:**
- Create a `history/` directory in the project root
- Store ALL AI-generated planning/design docs in `history/`
- Keep the repository root clean and focused on permanent project files

**Example .gitignore entry (optional):**
```
# AI planning documents (ephemeral)
history/
```

### Important Rules

- ✅ Use GitHub Issues for ALL task tracking
- ✅ Only issues labeled `squads` are synced into Squads
- ✅ Keep ticket metadata in labels (`type:*`, `priority:*`, `status:*`, `agent:*`)
- ❌ Do NOT use bd/beads for issue tracking
- ❌ Do NOT create markdown TODO lists in the repo root
- ❌ Do NOT duplicate tracking systems
