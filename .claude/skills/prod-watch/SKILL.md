---
name: prod-watch
description: >-
  Proactive prod-issue sweep. Discover what's new/worst since the last watermark,
  diagnose each via /analyze-prod-issue, auto-file a bug + priority:high issue, and
  notify. Runs unattended on a 12h schedule (launchd) or by hand. Invoke with: /prod-watch
disable-model-invocation: true
---

# Prod Watch

Proactively find production issues instead of waiting for a reported symptom. Each run does a
**sweep** for what's newly broken since the last **watermark**, diagnoses the survivors with the
existing `/analyze-prod-issue` workflow, auto-files a scrubbed `bug` + `priority:high` issue for
each real user-blocker, and notifies you it's ready to pick up.

**Type:** Rigid workflow. Follow steps exactly.

**Prerequisite:** read-only prod DB access (`bin/prod-db`) and the Honeycomb MCP session must be
live — same as `/analyze-prod-issue`. If `bin/prod-db --check` fails, see
`docs/runbooks/prod-db-access.md`.

The exact sweep SQL, the Honeycomb scan, and the issue-body template are in
`references/sweep.md` — read it when a step says to.

---

## Step 1 — Take the watermark from the wrapper

The wrapper (`bin/prod-watch`) owns state I/O and supplies it in the invocation: a `watermark`
timestamp and the `filed_fingerprints` array already filed. **Use those — do not read
`.prod-watch/state.json` yourself** (a headless run can't reliably write it back, so the wrapper
handles both ends). The wrapper defaults the watermark to now − 12h on the first run.

**Done when:** you hold the wrapper-supplied watermark and the set of already-filed fingerprints.

## Step 2 — Sweep for candidates

Run the sweep from `references/sweep.md`:

- **prod DB** — `error_tracker_errors` where `last_occurrence_at > watermark`,
  `status = 'unresolved'` (error_tracker's live status — there is no `'open'`), `NOT muted`, joined
  for an occurrence count, ranked by count descending.
- **Honeycomb** — the `error=true` scan over the 12h window for funnel drops the DB won't show
  (an entry span with many mounts but its terminal action near zero).

**Done when:** you have a ranked candidate list, each with its `fingerprint`, `kind`,
`source_function`, and occurrence count.

## Step 3 — Dedup

Drop any candidate whose `fingerprint` is in `filed_fingerprints`. As a second guard that survives
a lost state file, also run `gh issue list --search "<fingerprint>" --state open` and drop
candidates that already have an open issue. Apply the re-alert predicate in `references/sweep.md`
(a resolved-then-recurring error should re-alert; a still-open known one should not). Cap the
survivors to the top **3** by occurrence count.

**Done when:** a deduped candidate list of at most 3 remains (may be empty — then jump to Step 6).

## Step 4 — Diagnose each (delegate)

For each surviving candidate, run the full `/analyze-prod-issue` workflow, using the candidate's
error (`kind` + `source_function` + `reason`) as the symptom. Do **not** restate diagnosis here —
`/analyze-prod-issue` owns it. Its Step 6 honest-scoping is the quality gate: a candidate it
demotes to "noise / not a user-blocker" is **dropped, not filed**.

**Done when:** each candidate has either a real-blocker diagnosis (root cause + count-scoped impact
+ fix direction) or a "dropped as noise" verdict.

## Step 5 — File (auto)

For each candidate that survived as a real blocker, create the issue directly (the loop is
unattended — do not route through `/create-issue`, whose confirmation gate cannot run here):

```bash
gh issue create --label "bug,priority:high" --assignee MaxPayne89 \
  --title "[BUG] <one-line symptom>" \
  --body "$(cat <<'EOF'
<body from references/sweep.md template>
EOF
)"
```

The body carries the fingerprint marker `<!-- prod-watch-fingerprint: <fp> -->` so the next
sweep can dedup on it. **Count + opaque UUID only — never names or emails** (the repo is public;
inherit the PII rule from `/analyze-prod-issue`).

**Done when:** each real blocker has an issue URL, or is recorded as dropped-noise.

## Step 6 — Notify + report what you filed

Send one `PushNotification` per filed issue: `prod-watch filed #NNN: <one-line>`. If nothing was
filed, send none. Then **report** the error_tracker fingerprints you filed this run (a JSON array,
possibly empty) between these exact markers, and finish:

```
PROD_WATCH_FILED_BEGIN
["<fingerprint>", ...]
PROD_WATCH_FILED_END
```

Do **not** write `.prod-watch/state.json` — the wrapper stamps the new watermark and unions these
fingerprints into state. Emit the block even on a clean sweep (`[]`), so the wrapper always advances
the watermark.

**Done when:** notifications sent (or none needed) and the `PROD_WATCH_FILED` block is emitted.

---

## Rules

- **Auto-file only what survives honest scoping.** An erroring or discarded Oban job is not a
  filed issue — `/analyze-prod-issue` Step 6 must confirm a real user-blocker first.
- **Count, never names.** PII stays in the DB; issues get counts and UUIDs. GitHub edit history
  is public — scrubbing after the fact means deleting the issue.
- **Dedup on the error_tracker `fingerprint`**, not on title text. Re-alert only when a known
  error recurs after its prior issue was closed (see the re-alert predicate in
  `references/sweep.md`).
- **Read-only prod always** — reach production only through `bin/prod-db` (SELECT-only `reader`).
- **The watermark is the single cursor.** Never re-scan below it; never file a fingerprint twice.
