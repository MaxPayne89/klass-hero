---
name: triage-qa-discussion
description: Use when the user wants to read a Daily QA discussion by number, triage the findings (Carried-Forward and New Code Review), assess validity against current code, present a structured summary, then systematically fix confirmed issues. Invoke with the discussion number as argument (e.g. `/triage-qa-discussion 449`).
---

# Triage QA Discussion

Read a Daily QA discussion, triage all findings, and systematically address confirmed issues.

**Type:** Rigid workflow. Follow steps exactly.

---

## Step 1: Get Repo Identifier

```bash
gh repo view --json nameWithOwner -q '.nameWithOwner'
```

Split into `{owner}` and `{repo}`.

## Step 2: Fetch Discussion

The argument passed to this skill is the discussion number `{number}`.

```bash
gh api graphql -f query='{ repository(owner: "{owner}", name: "{repo}") { discussion(number: {number}) { title body url } } }'
```

If the discussion does not exist or is not a Daily QA report, stop and tell the user.

Extract `title`, `body`, and `url`.

## Step 3: Parse Findings

Extract findings from **two** sections of the discussion body:

1. **"Carried-Forward Findings"** — recurring unfiled findings (primary target)
2. **"New Code Review"** — fresh findings from recently merged code

Each finding follows this format:
```
**⚠️ Title** (`file/path.ex` Lxx–yy)
- Context bullets
- Severity: Low / Low-Medium / Medium
- Fix: suggested resolution
```

**Skip these sections entirely** — they are already tracked or informational:
- "Pre-existing open issues"
- "Since last report" (merged PR summaries)
- "Actions taken"
- "Observations" without file references or fix suggestions

For each finding, extract:
- **Title** — the bold heading text
- **File path** — from parenthetical reference
- **Line range** — Lxx–yy if present
- **Severity** — as stated
- **Suggested fix** — the "Fix:" or "Recommended fix" text

## Step 4: Assess Each Finding

For each parsed finding:

1. **Read the referenced file** at the specified lines to get current state
2. **Check if already resolved** — the code may have changed since the report
3. **Check if a GitHub issue already exists** for this finding:
   ```bash
   gh issue list --search "keyword from finding title" --state open --json number,title
   ```
4. **Classify** using the table below

### Classification Table

| Classification | Meaning | Action |
|---|---|---|
| `actionable` | Real code/architecture issue confirmed in current code | Fix it |
| `migration-needed` | Requires a new Ecto migration (index, schema change) | Create migration |
| `test-gap` | Missing test coverage for an existing code path | Add tests |
| `already-resolved` | Code has changed since the report; finding no longer applies | Skip with note |
| `already-filed` | A GitHub issue already tracks this finding | Skip — reference issue # |
| `wont-fix` | Valid observation but intentional design or acceptable tradeoff | Skip with rationale |
| `needs-investigation` | Cannot determine validity without deeper analysis or user input | Flag for user |

## Step 5: Present Triage Summary

Present a table to the user:

```
| # | Finding | File | Severity | Classification | Rationale |
|---|---------|------|----------|----------------|-----------|
| 1 | Orphaned Task in DashboardLive | lib/.../dashboard_live.ex:30 | Low | actionable | Task.async without guaranteed await |
| 2 | Missing session_date index | program_sessions table | Low | migration-needed | Sequential scan on every page load |
```

After the table, output a stats summary:

```
Triage: X actionable, Y migration-needed, Z test-gaps, W already-resolved, V already-filed, U wont-fix, Q needs-investigation — N total
```

Ask the user which findings to address. Default: all `actionable` + `migration-needed` + `test-gap`. Let user include/exclude by number.

**Do NOT make any code changes before user confirmation.**

## Step 6: Invoke Idiomatic Elixir Skill

Before making any changes, invoke the `idiomatic-elixir` skill to load Elixir patterns and DDD guidance into context.

## Step 7: Systematically Fix

For each confirmed finding, in order:

1. Output progress: `Fixing 2/5: Missing session_date index on program_sessions`
2. Re-read the file to get current state (it may have changed from prior fixes)
3. Respect the project's conventional-Phoenix layout (flattened from DDD, #986–#1002):
   - **Entity logic + persistence** → the schema-as-struct module at the context root, e.g. `lib/klass_hero/{context}/{entity}.ex` (Ecto schema + struct + functional core); the context API is `lib/klass_hero/{context}.ex`
   - **CQRS projections / read-tables** → `lib/klass_hero/{context}/adapters/driven/projections/` and `.../persistence/` (projection tables only)
   - **Migrations** → `priv/repo/migrations/`
   - **LiveView** → `lib/klass_hero_web/live/`
   - **Tests** → mirror the source file path under `test/`
4. Make the minimal change that addresses the finding
5. Briefly note what was changed

**For migrations:** Generate timestamp with `date -u +"%Y%m%d%H%M%S"` and create the migration file at `priv/repo/migrations/{timestamp}_{description}.exs`.

**Error handling:** If a fix fails (file not found, ambiguous edit, compile error), log the failure with the reason, skip to the next finding, and collect all failures for the summary. **Never stop mid-fix.**

After ALL fixes are applied, run `mix precommit`. If tests fail, diagnose and fix regressions before proceeding.

## Step 8: Commit, Push, and Summary

**8a. Create GitHub issues for unfixed findings:**

For any `needs-investigation` or `wont-fix` finding without an existing GitHub issue, offer to create one:
```bash
gh issue create --title "QA: {finding title}" --body "{finding details and rationale}"
```

**8b. Commit and push:**

1. Stage only the changed files (not `git add -A`)
2. Commit with message: `fix: address QA findings from discussion #{number}`
3. Run `mix precommit` — if it fails, diagnose and fix before committing
4. `git push` — if push fails, resolve and retry until it succeeds

**8c. Present final summary:**

- Which findings were addressed and how
- Which were skipped and why (already-resolved, already-filed, wont-fix)
- Which failed during fixing and why
- Which GitHub issues were created
- Link to the original discussion

---

## Key `gh` Commands Reference

```bash
# Repo identifier
gh repo view --json nameWithOwner -q '.nameWithOwner'

# Fetch discussion by number (GraphQL — no CLI equivalent)
gh api graphql -f query='{ repository(owner: "{owner}", name: "{repo}") { discussion(number: {N}) { title body url } } }'

# Search for existing issues matching a finding
gh issue list --search "keyword" --state open --json number,title

# Create issue for unresolved finding
gh issue create --title "QA: ..." --body "..."
```

---

## Rules

- **Never change code before the user confirms the triage.** Present the summary first.
- **Read before editing.** Always read the current file state before making changes.
- **Verify against current code.** Findings reference a point-in-time snapshot — always check if the code has changed.
- **Minimal fixes.** Address exactly what the finding describes — don't refactor surrounding code.
- **Respect the conventional-Phoenix layout.** Entity logic + persistence go in the schema-as-struct module at the context root; keep the context API in `<context>.ex`.
- **Invoke idiomatic-elixir before implementation.** Load Elixir patterns into context before writing code.
- **Never stop mid-fix.** If a single finding can't be addressed, log the failure and continue.
- **Always run tests.** `mix precommit` is mandatory before committing.
- **Always push.** Work isn't done until `git push` succeeds.
- **Skip pre-existing issues.** If a finding already has a GitHub issue, classify as `already-filed`.
- **Offer issue creation.** For findings that won't be fixed this session, offer to create GitHub issues.
