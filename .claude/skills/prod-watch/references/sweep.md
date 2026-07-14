# prod-watch sweep recipes

The exact queries and template for `/prod-watch`. Read when a step points here. Builds on
`analyze-prod-issue/references/cookbook.md` (schemas + Honeycomb recipes); this file adds only the
since-`watermark` sweep that the cookbook lacks.

`error_tracker_errors` columns used: `id, kind, reason, source_function, status, fingerprint,
last_occurrence_at, muted`. The `fingerprint` column is error_tracker's own stable dedup key —
prod-watch dedups on it, never invents one.

---

## Sweep SQL (Step 2)

Ranked list of errors newly active since the watermark. `$WATERMARK` is `last_run_at` from
`state.json` (ISO-8601). Run via `bin/prod-db -c "<SQL>"`.

```sql
select e.fingerprint,
       e.kind,
       e.source_function,
       left(e.reason, 90)                          as reason,
       e.status,
       count(o.id)                                 as occurrences,
       to_char(e.last_occurrence_at,'MM-DD HH24:MI') as last_seen
  from error_tracker_errors e
  join error_tracker_occurrences o on o.error_id = e.id
 where e.last_occurrence_at > '$WATERMARK'
   and e.status = 'unresolved'   -- error_tracker's live status (there is no 'open')
   and e.muted = false
 group by e.id, e.fingerprint, e.kind, e.source_function, e.reason, e.status,
          e.last_occurrence_at
 order by occurrences desc;
```

## Re-alert predicate (Step 3)

Given the sweep rows and `filed_fingerprints` from `state.json`, decide which **already-filed**
fingerprints deserve a *fresh* issue anyway (a recurrence after resolution) versus which to stay
quiet on (a still-open error we already reported). This is the alerting-idempotency call — too
loose spams duplicate issues, too tight swallows a real regression.

Anchor "recurrence" to the human-meaningful event — **the issue we filed was closed, yet the error
is back** — rather than to extra persisted counters. Every sweep row is already `status = 'unresolved'
AND muted = false` (the sweep query enforces it), so the only question left is the issue's state.
Apply this rule to each candidate:

| Candidate | Prior open issue? (`gh issue list --search "<fp>" --state open`) | Action |
|---|---|---|
| `fingerprint` NOT in `filed_fingerprints`, no open issue | — | **File** (new) |
| in `filed_fingerprints`, an open issue exists | yes | **Drop** — still being worked |
| in `filed_fingerprints`, no open issue | no (prior issue was closed) | **Re-file** — recurrence after a supposed fix |

A `muted` error never reaches this table — muting is an explicit "stop telling me," and the sweep
excludes it. This keeps `state.json` to just the watermark + fingerprint set: recurrence detection
borrows the closed-issue signal from GitHub, needing no per-fingerprint count baseline.

## Honeycomb scan (Step 2, funnel drops)

The DB misses symptoms that aren't exceptions (a booking funnel that quietly drops). Same
`run_query` recipe as the cookbook, pointed at the sweep window:

```
mcp__honeycomb__run_query
  environment_slug: "live"
  dataset_slug: "klass-hero"
  query_spec:
    calculations: [{ "op": "COUNT" }]
    filters:      [{ "column": "error", "op": "=", "value": true }]
    breakdowns:   ["name"]
    orders:       [{ "op": "COUNT", "order": "descending" }]
    time_range:   43200        # 12h in seconds
```

Cross-check the top spans here against the SQL sweep — a span erroring in Honeycomb with no
matching `error_tracker` row is itself worth a candidate.

## Issue-body template (Step 5)

Count-only, fingerprint-marked. Fill the angle-bracket slots from the `/analyze-prod-issue`
diagnosis.

```markdown
<!-- prod-watch-fingerprint: <fp> -->

**Auto-filed by `/prod-watch`** — sweep of <window>.

## Symptom
<one-paragraph: what's failing, from the error kind + source_function>

## Impact (honest scope)
<N> users affected (of <population>). <noise-vs-blocker note from analyze-prod-issue Step 6.>
Occurrences since watermark: <count>. Oban disposition: <retryable | discard | n/a>.

## Root cause
<the raised error + the real reason from error_tracker_occurrences.context>

## Fix direction
<concrete files>. On `main`: <fixed | still-present | live-vs-main deploy lag>.

## References
- error_tracker fingerprint: `<fp>`
- affected entities: <opaque UUIDs only — no names/emails>
```
