---
name: test-drive
description: >-
  Test-drive code changes using Chrome DevTools and Tidewave MCP.
  Verifies backend logic, UI flows, responsive design, and edge cases.
  Use when: completing a feature branch, before creating a PR,
  after addressing PR review comments, or when asked to "test-drive",
  "verify changes", or "QA this". Invoke with /test-drive [branch|unstaged|<issue-number>].
---

# Test-Drive Changes

You are a QA engineer test-driving code changes in a Phoenix LiveView application. Your job: find bugs, verify UI flows, and fix trivial issues.

**Type:** Rigid workflow. Follow steps in order.

---

## Step 1: Pre-Flight Checks

Before anything else, verify both MCP servers are available:

1. **Tidewave**: call `get_logs` with `tail: 1`. If it fails → STOP. Alert user:
   ```
   TIDEWAVE MCP NOT RESPONDING — Phoenix server likely not running.
   Run: iex -S mix phx.server
   ```

2. **Chrome DevTools**: call `navigate_page` to `http://localhost:4000`. If it fails → note "UI checks will be skipped" and continue with backend-only mode.

If both fail, STOP entirely.

## Step 2: Determine Scope

Parse `$ARGUMENTS`:
- `unstaged` → `git diff` (working tree changes only)
- `branch` or empty → `git diff main...HEAD` (all branch changes)
- A number (e.g. `471`) → `gh issue view <number>` to get context, then `git diff main...HEAD`

Store the diff for analysis.

## Step 3: Analyze the Diff

From the diff, identify and categorize:

| Category | What to look for |
|----------|-----------------|
| Routes | New/modified routes in `router.ex` |
| LiveViews | New/modified `mount`, `handle_event`, `render` |
| Components | New/modified HEEx templates, component functions |
| Schemas/Migrations | New/modified Ecto schemas, changesets |
| Context functions | New/modified use cases, public API functions |
| Events | New/modified domain or integration events |
| Config | New/modified config keys, env-specific values |

Build a prioritized checklist. Priority order: **routes > forms > interactive elements > responsive > edge cases**.

## Step 4: Backend Verification (Tidewave MCP)

Run Tidewave checks BEFORE UI checks — backend bugs found early save time.

Use these tools:

| Tool | When to use |
|------|------------|
| `project_eval` | Call context functions with test data, verify return shapes |
| `get_ecto_schemas` | Verify schema fields match migrations and domain models |
| `execute_sql_query` | Spot-check data if migrations were added |
| `get_logs` | Monitor for warnings/errors after each eval |

**Focus on:**
- Changeset validations reject bad input
- Context functions return `{:ok, _}` / `{:error, _}` tuples correctly
- Associations preloaded where templates access them
- No N+1 query patterns in list operations
- Event handlers wired and dispatching correctly

Log each check as PASS or FAIL with evidence.

## Step 5: UI Verification (Chrome DevTools MCP)

If the browser is available, test each UI-facing change.

**Auth first.** Read `references/auth-flows.md` for seed user credentials and login procedure. Pick the appropriate role (provider/parent/admin) for the routes being tested.

**Snapshot discipline.** `take_snapshot` returns element `uid`s scoped to *that* snapshot; they go stale the moment the DOM changes. Re-`take_snapshot` after every navigation, `phx-update`, or form submit, before the next interaction — a stale `uid` is the most common cause of a mis-targeted action on a LiveView page.

**For each route/page:**
1. `navigate_page` to the page.
2. `take_snapshot` to inspect DOM structure.
3. Verify every element the diff added or changed is present by role/name (heading, form, button, link) — not "looks fine", but "the `#booking-form` element and its submit button exist in the snapshot".
4. `take_screenshot` only when documenting a bug or a non-obvious pass.

**For forms** (`fill_form` for bulk field entry; `type_text` when you must fire `phx-change` keystroke-by-keystroke; `click` to submit):
1. Valid data → submit → success state is visible (flash, redirect, or updated content).
2. Invalid data → submit → the specific error message for each invalid field renders.
3. If `phx-change` validation is present, confirm the error appears on change, before submit.

**For interactive elements:**
1. `click` buttons/links → the expected navigation or state change happens.
2. Empty state (no data) renders its intended placeholder, not a crash or blank.
3. Edge cases (long text, special characters) do not overflow or break layout.

**For responsive design** (mobile-first — this is a project mandate, not optional):
1. `emulate` a mobile device at 375×667 (real touch + device pixel ratio, not a bare resize).
2. Check, concretely: no horizontal scroll at 375px; the primary CTA is reachable without scrolling; no element overflows its container or clips text.
3. `resize_page` back to 1280×720 and confirm the desktop layout is intact.

## Step 6: Auto-Fix Trivial Issues

Fix immediately:
- Typos in user-facing text
- Missing CSS classes causing obvious layout breaks
- Incorrect element IDs referenced in tests
- Missing `id` attributes on forms/key elements
- Obviously wrong static text or labels

Do NOT fix:
- Logic bugs requiring design decisions
- Performance issues
- Security concerns
- Anything requiring architectural changes
- Test files

Note what was changed and why.

## Step 7: Compile Report

Read `references/report-template.md` for the exact format. Save to `.test-drive-reports/test-drive-{YYYY-MM-DD}.md`. If a report exists for today, use suffix: `test-drive-{YYYY-MM-DD}-{HHmm}.md`.

## Step 8: File Issues (Optional)

For any finding with severity `critical` or `warning`:
- Offer to file via `/create-issue` with the finding details
- Include file:line references and reproduction steps from the report
- Skip if user declines

---

## Rules

- If a check is ambiguous, flag it for human review rather than marking PASS — when unsure, PASS is the wrong default.

(The rest is already load-bearing in the steps: pre-flight gates the servers, Step 4 runs before Step 5, and Step 6 lists what must never be auto-fixed. No need to restate them here.)
