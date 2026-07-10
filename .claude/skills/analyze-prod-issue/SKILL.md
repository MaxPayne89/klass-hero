---
name: analyze-prod-issue
description: >-
  Diagnose a production issue end-to-end across Honeycomb (error shape) and the
  prod DB error_tracker tables (who + why), scope impact honestly, and optionally
  file a PII-scrubbed issue. Invoke with: /analyze-prod-issue "<symptom>"
disable-model-invocation: true
---

# Analyze Prod Issue

Take a production symptom (e.g. "parents can't book") and diagnose it end-to-end by
correlating **two** sources — Honeycomb for the error *shape*, the prod DB `error_tracker`
tables for the *who + why* — then scope impact honestly and optionally file a scrubbed issue.

**Type:** Rigid workflow. Follow steps exactly.

**Prerequisite:** read-only prod DB access must be set up (`bin/prod-db`). If it errors, see
`docs/runbooks/prod-db-access.md` first.

The exact Honeycomb tool calls and prod SQL are in `references/cookbook.md` — read it when a
step says to.

---

## Step 1 — Orient (Honeycomb)

Call `mcp__honeycomb__get_workspace_context`. Note the environment slugs; production is the
`live` environment (there is also `dev`). Use `live` in every subsequent Honeycomb call.

**Done when:** you know the `live` env slug and its dataset.

## Step 2 — Find the error surface

- `mcp__honeycomb__list_spans` over `14d` — ranks span names by count with `root_count`.
  Scan for the failing area *and* for **funnel drops** (an entry span with many mounts but
  its terminal action span near zero often is the reported symptom).
- `mcp__honeycomb__run_query` with `filter error=true`, `breakdown ["name"]`, `time_range
  "14d"` — ranks the actually-failing spans by count.

**Done when:** you have candidate failing span name(s) with counts. If there are zero
`error=true` spans, the symptom is not an exception — pivot to the funnel-drop reading.

## Step 3 — Trace the causal chain

`mcp__honeycomb__get_trace` on a failing trace (`show_events: true`). Read the waterfall:
find the span where the error is *raised* and the call chain above it (HTTP entry → worker →
context function → repo query).

**Honeycomb gap to expect:** a DB error inside a rolled-back transaction surfaces only as
`query_error` / `status_message` with **no exception text** (spans carry no event). That
absence is the signal to go to the prod DB — do not stop here.

**Done when:** the failing chain and the raising span are mapped.

## Step 4 — Pull the real reason (prod DB)

Query `error_tracker` via `bin/prod-db -c "<SQL>"` (read-only reader role). See
`references/cookbook.md` for the schema and the exact queries.

- `error_tracker_errors` — `kind`, `reason`, `source_function`, `last_occurrence_at`,
  `status`. Find the error matching the trace.
- `error_tracker_occurrences` — `context` (Oban `job.args` + the full event payload:
  `event_type`, `entity_id`, user email/name), `stacktrace`, `breadcrumbs`, and
  `job.state` / `job.attempt`.

This is where the swallowed DB error, the affected user, the triggering event, and the Oban
disposition (`retryable` vs `discard`) actually live.

**Done when:** you know the underlying error, the affected entity, the triggering event, and
the occurrence count + date range.

## Step 5 — Cross-reference schema & data

Confirm the hypothesis against real rows before believing it:

- Does the row the handler tried to create **already exist**? (duplicate vs genuinely missing)
- What are the **actual** constraint/index names? (a changeset `unique_constraint` name
  mismatch makes a violation *raise* instead of returning a changeset error)
- **Affected-vs-total counts** — how many entities are in the bad state vs the population?

**Done when:** the mechanism is proven from data, not assumed.

## Step 6 — Scope impact honestly

The point of Step 5 is to *correct the premise*, not confirm it. Produce a one-paragraph
impact statement that:

- Separates **noise vs a real user-blocker** — an erroring/discarded job is not automatically
  a blocked user (the side effect may already have succeeded on another path).
- Quantifies affected users by **count**.
- **Splits disjoint phenomena** — two symptoms with the same surface can have different
  causes and different populations; do not conflate them.

**Done when:** an honest, numeric impact statement exists — even if it contradicts the
original complaint.

## Step 7 — Confirm root cause in code

Grep the implicated modules to anchor the fix. State explicitly whether the bug exists on
`main` or the behaviour is a **live-vs-main deploy lag** (live can raise what `main` already
handles). Check the current commit on `live` if it matters.

**Done when:** the fix direction names concrete files and says whether deploying `main` fixes it.

## Step 8 — (Optional) File a scrubbed issue

If the finding warrants tracking, hand off to `/create-issue`.

**Public-repo PII rule (non-negotiable):** reference affected users by **count + opaque UUID
only**. Never put names or emails in a public issue — GitHub edit history is public, so
scrubbing after the fact requires deleting and recreating the issue. Keep the
user_id ↔ identity mapping in the DB, not the issue.

**Done when:** the issue exists with count-only references, or you and the user decide not to file.

---

## Rules

- **Two sources, not one.** Honeycomb gives the *shape* (chain, span, timing); `error_tracker`
  gives the *who + why* (reason, event payload, stacktrace, Oban state). Neither alone is enough.
- **Read-only always.** Reach prod only through `bin/prod-db` (the SELECT-only `reader` role).
  Never open a write path against production.
- **Count, never names, in public artifacts.** PII stays in the DB; issues and PRs get counts
  and UUIDs.
- **Scope honestly.** "Erroring" ≠ "user-blocked." Prove impact from data before claiming it,
  and correct the premise when the data disagrees.
- **The rollback hides the error.** When Honeycomb shows only `:rollback` / `query_error` with
  no text, the real reason is in `error_tracker_occurrences.context`, not the span.
