---
name: review-design
description: >-
  Review frontend/design changes for klass-hero by spawning the
  design-system-guardian (static code: tokens, duplication, lint_typography +
  credo) and ui-critic (rendered: hierarchy, spacing, contrast, accessibility,
  mobile) agents in parallel, then consolidating into a unified report. Use when:
  reviewing a PR that touches LiveViews/components/templates/CSS, checking UI or
  design quality before merge, validating frontend changes, or after editing
  anything under lib/klass_hero_web/ or assets/css/. Invoke with: /review-design
---

# Review Design

Run a comprehensive frontend/design review by dispatching two specialized agents in
parallel — one static (code), one rendered (browser) — then consolidating their reports.

**Type:** Rigid workflow. Follow steps exactly. Do not improvise a single manual review
in place of the agents — spawning both is the entire point (see Rules).

This skill reviews the *visual quality and design-system consistency of a change*. Flow /
journey friction is **out of scope** here — that's `product-flow-designer`, run standalone.

---

## Step 1: Determine Changed Frontend Files

Detect the review scope relative to the base branch, including unstaged and untracked work.

```bash
BASE=$(git merge-base HEAD main 2>/dev/null || echo "main")
# committed vs base
git diff --name-only "$BASE"...HEAD -- 'lib/klass_hero_web/**/*.ex' 'lib/klass_hero_web/**/*.heex' 'assets/css/app.css'
# unstaged
git diff --name-only -- 'lib/klass_hero_web/**/*.ex' 'lib/klass_hero_web/**/*.heex' 'assets/css/app.css'
# untracked
git ls-files --others --exclude-standard -- 'lib/klass_hero_web/**/*.ex' 'lib/klass_hero_web/**/*.heex' 'assets/css/app.css'
```

Union the three lists. Keep only front-end files: anything under `lib/klass_hero_web/`
(LiveViews, components, templates) and `assets/css/app.css`.

If the union is empty, STOP:

```
No frontend files changed. Nothing to review.
```

(`/review-architecture` covers backend `.ex`; this skill is front-end only.)

## Step 2: Map Changes to Affected Routes

The guardian works on the file list directly. The critic is **route-scoped** — it needs URLs
to visit, not files. Derive them:

- Changed **LiveView** module → its route(s). Grep `lib/klass_hero_web/router.ex` for the module.
- Changed **component** → grep for the component's usages → the LiveView(s) that render it →
  their route(s).
- Changed `app.css` → pick a few representative routes that exercise the affected styles.

Also note the **role** each route needs (parent / provider / admin) so the critic logs in with
the right seed user. Display:

```
Affected routes: /provider/dashboard (provider), /dashboard (parent)
```

If a changed component has no on-screen consumer yet (dead/new code), say so — the critic can't
render what isn't wired up; the guardian still reviews it statically.

## Step 3: Server Preflight (for the rendered lens)

The critic must drive the running app. Probe `http://localhost:4000` (and one real route
like `/programs`) — the server must be **healthy**, not merely listening. A stale process
returning `5xx` counts as down.

- **Healthy (2xx/3xx):** proceed with both agents.
- **Down or erroring (no response, or 5xx):** ask the user to (re)start it (`mix phx.server`).
  If they decline, proceed with the **guardian only** and mark the report
  `rendered lens skipped — server unavailable`. Never let the critic fabricate a review from
  code; it STOPs without a healthy server by design.

## Step 4: Spawn Both Agents in Parallel

Launch both **in the same message** so they run concurrently.

### Agent 1: Design System Guardian (static lens)

Use the `design-system-guardian` subagent. Provide:

```
Review these changed frontend files for design-system consistency.

Scope: changed-files
Changed files:
<file list>

Run all 8 checks scoped to these files. Run mix lint_typography and mix credo for ground
truth. Report findings in your standard output format.
```

### Agent 2: UI Critic (rendered lens)

Use the `ui-critic` subagent. Provide:

```
Review the rendered UI for these screens.

Routes: <affected routes, with the role to log in as for each>
Server: http://localhost:4000 (confirmed up)

Walk each route at 375/768/1280 and the relevant interaction states. Run all 10 checks.
Report findings in your standard output format.
```

(If the server was unavailable and the user declined to start it, skip Agent 2 and note it.)

## Step 5: Consolidate Reports

Merge into one report. The two agents are designed with disjoint lanes, so overlap is small —
but reconcile these:

### Deduplication

- **Typography** — guardian flags raw `font-display` / wrong atom from *code* (with `file:line`
  + linter); critic flags type-scale / hierarchy from the *render*. If it's the same element,
  keep the guardian's framing (it has the file + linter evidence) and fold in the critic's
  visual note.
- **Spacing / consistency** — guardian = off-scale token in code; critic = visual rhythm on
  screen. Same element → merge into one finding.
- Everything else is single-lens: contrast / focus / tap-targets / viewport → critic only;
  duplication / token gaps / variant logic / credo → guardian only.

### Unified Severity

The agents use different ladders. Map both onto one:

| Unified | ui-critic | design-system-guardian |
|---------|-----------|------------------------|
| **Blocker** | Blocker | Must-fix (breaks precommit/CI) |
| **Major** | Major | Should-fix |
| **Minor** | Minor | (lesser Should-fix) |
| **Nit / Opportunity** | Nit | Opportunity |

### Unified Report Format

```markdown
# Design Review Report

**Branch:** [branch name]
**Affected routes:** [list]   **Files reviewed:** [count]
**Rendered lens:** ran @375/768/1280  |  skipped — server unavailable

## Summary

| Source | Checks | Blocker | Major | Minor | Nit/Opp |
|--------|--------|---------|-------|-------|---------|
| Static (design-system-guardian) | 8 | N | N | N | N |
| Rendered (ui-critic) | 10 | N | N | N | N |
| **Total** | **18** | **N** | **N** | **N** | **N** |

Linters: lint_typography PASS|FAIL (n) · credo n design-relevant findings

## Findings
(grouped Blocker → Major → Minor → Nit/Opp; omit empty)

### [Blocker] <title>
- **Where:** <route / file:line / element>
- **Issue:** what is wrong (note lens: static | rendered)
- **Fix:** specific — name the Theme atom / token / component, or the design change

## Passed / clean
- [checks that returned nothing]
```

Order by severity, then by file/route.

## Step 6: Present and Advise

- **Zero findings:** confirm the change is visually and design-system sound.
- **Only Minor/Nit:** note them, confirm the change is acceptable.
- **Blocker/Major:** list the specific files/screens and changes needed; offer to fix.
- If the rendered lens was skipped, say so explicitly — the review is partial.

---

## Rules

- **Always spawn both agents in parallel** in one message. Do NOT substitute an improvised
  manual review for the agents — the failure mode this skill prevents is a single hand-rolled
  pass that skips the browser and the linters.
- **Both lenses or say which is missing.** Static-only (server down + user declined) is allowed
  but must be labelled partial. Never silently drop the rendered lens.
- **Scope to changes.** Guardian gets the changed-file list; critic gets the routes those
  changes render on. Don't run full-codebase sweeps from this skill (run an agent standalone for
  that).
- **Run the linters for typography/credo** (via the guardian) — don't eyeball them.
- **Deduplicate across lenses.** Same element flagged twice → one finding, guardian's framing for
  code-level, critic's for rendered.
- **Never auto-fix without confirmation.** Present findings first, then offer to fix.
- **Flow/journey friction is out of scope.** That's `product-flow-designer`, run separately.
- **Include the full check count** (18) even when everything passes, so the user knows what was verified.
```
