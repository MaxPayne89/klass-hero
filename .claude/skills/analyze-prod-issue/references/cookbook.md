# analyze-prod-issue — cookbook

Loaded from SKILL.md steps 2–5. Concrete Honeycomb tool calls and prod SQL, copied from a
real end-to-end investigation so they run as written. Adjust identifiers to the case at hand.

---

## Honeycomb recipes (env slug: `live`)

**Orient (Step 1):**
```
mcp__honeycomb__get_workspace_context   # no args → team, environments, dataset counts
```

**Span landscape + funnel drops (Step 2):**
```
mcp__honeycomb__list_spans
  environment_slug: "live"
  time_range: "14d"
  items_per_page: 200
```
Read `count` vs `root_count`: `root_count == count` = trace entry point (HTTP handler, root
job). A high-count entry span whose terminal action span is near zero is a funnel drop.

**Rank failing spans (Step 2):**
```
mcp__honeycomb__run_query
  environment_slug: "live"
  dataset_slug: "klass-hero"
  query_spec:
    calculations: [{ "op": "COUNT" }]
    filters:      [{ "column": "error", "op": "=", "value": true }]
    breakdowns:   ["name"]
    orders:       [{ "op": "COUNT", "order": "descending" }]
    time_range:   "14d"
```
Add `include_samples: true` and a `filter name = "<span>"` to see raw sample rows (columns
like `db.statement`, `status_message`, `trace.trace_id`) for one failing span.

**Trace the chain (Step 3):**
```
mcp__honeycomb__get_trace
  environment_slug: "live"
  trace_id: "<32-hex from the sample>"
  time_range: "14d"
  show_events: true
```
`ERROR` / `error=true` rows mark the failing spans; the parent chain above the raising span
is the causal path. Expect DB errors to appear only as `query_error` with no exception text.

---

## error_tracker SQL cookbook (via `bin/prod-db -c "<SQL>"`)

ErrorTracker persists to two tables. `bin/prod-db` runs SQL read-only as the `reader` role.

**Schemas:**
```
error_tracker_errors:       id, kind, reason, source_line, source_function, status,
                            fingerprint, last_occurrence_at, inserted_at, updated_at, muted
error_tracker_occurrences:  id, context, reason, stacktrace, error_id, inserted_at, breadcrumbs
```
`context` is JSONB holding the Oban job (`job.state`, `job.attempt`, `job.args`) and, for
event-driven workers, the full event payload under `job.args -> payload`.

**1. Recent errors, newest first (Step 4):**
```sql
select id, kind, left(reason,90) as reason, source_function, status,
       to_char(last_occurrence_at,'MM-DD HH24:MI') as last_seen
  from error_tracker_errors
 order by last_occurrence_at desc;
```

**2. Latest occurrence context for one error (Step 4):**
```sql
select id, inserted_at, context
  from error_tracker_occurrences
 where error_id = <ID>
 order by inserted_at desc limit 1;
```

**3. All occurrences of one error, with who + when (Step 4):**
```sql
select to_char(inserted_at,'MM-DD HH24:MI') as seen,
       context->>'job.state'                            as state,
       context->'job.args'->>'event_type'              as event,
       context->'job.args'->'payload'->>'email'        as email,
       context->'job.args'->'payload'->>'user_id'      as user_id
  from error_tracker_occurrences
 where error_id = <ID>
 order by inserted_at desc;
```

**4. Impact sizing — are the error victims actually in a bad state? (Steps 5–6):**
Cross-reference the affected user_ids against the domain table. Example used to prove the
error was noise (every victim still had a profile):
```sql
with victims as (
  select distinct (context->'job.args'->'payload'->>'user_id')::uuid as user_id
    from error_tracker_occurrences where error_id = <ID>
)
select count(*) as victims, count(p.id) as have_row, count(*) - count(p.id) as missing
  from victims v
  left join parents p on p.identity_id = v.user_id;
```

**5. Population-level bad-state count — the disjoint set (Step 6):**
Find entities genuinely missing the side effect, independent of the error. Example: confirmed
parents with no profile row (a *different* population than the error victims above):
```sql
select count(*) filter (where p.id is null) as confirmed_parents_no_profile
  from users u
  left join parents p on p.identity_id = u.id
 where 'parent' = any(u.intended_roles) and u.confirmed_at is not null;
```

**Verify the mechanism, not just the symptom (Step 5):**
```sql
-- does the row the handler tried to create already exist?
select id, inserted_at from parents where identity_id = '<uuid>';
-- actual constraint/index names (a changeset name mismatch makes violations RAISE)
select indexname, indexdef from pg_indexes where tablename = '<table>';
```
