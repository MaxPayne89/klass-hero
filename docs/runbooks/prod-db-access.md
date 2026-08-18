# Runbook: Read-only prod DB access

Reproducible, read-only access to the production Managed Postgres cluster for
debugging — e.g. reading `error_tracker_errors` / `error_tracker_occurrences`,
which hold the full exception, `context` (Oban job args, event payload), and
`stacktrace` that the Honeycomb spans do not carry.

## Facts

| Thing | Value |
|---|---|
| Cluster name | `klass-hero-live-db` |
| Cluster ID | `ey5qn0y5d47o8zmw` |
| Org | `klass-hero` |
| Region | `fra` |
| Attached app | `klass-hero-live` |
| Database | `fly-db` |
| Flavor | Fly **Managed** Postgres (MPG) — use `fly mpg`, not `fly pg` |
| Read-only user | `debug-ro` (role `reader`, SELECT only) |

## How it works

`fly mpg connect` opens its own proxy **and** resolves the user's password
internally — Fly never exposes the raw password, so there is no standalone
`psql` DSN and no `.env` file. `bin/prod-db` wraps `fly mpg connect` as the
single reliable transport.

## One-time setup

```bash
# 1. authenticate
fly auth login

# 2. read-only role (already created; re-run only if it was deleted)
fly mpg users create ey5qn0y5d47o8zmw -u debug-ro -r reader
#    NB: MPG usernames allow lowercase/dashes only — no underscores.

# 3. psql client (used for the interactive mode)
brew install libpq && brew link --force libpq
```

## Use

```bash
bin/prod-db -c "select count(*) from error_tracker_errors;"   # one-shot
echo "select 1;" | bin/prod-db                                # SQL from stdin
bin/prod-db                                                    # interactive psql
bin/prod-db --check                                           # verify prereqs
```

### Useful queries

```sql
-- recent tracked errors, newest first
select id, kind, left(reason,90) as reason, source_function, status,
       to_char(last_occurrence_at,'MM-DD HH24:MI') as last_seen
  from error_tracker_errors order by last_occurrence_at desc;

-- full context (Oban job args + event payload) for one error's latest occurrence
select context from error_tracker_occurrences
 where error_id = <ID> order by inserted_at desc limit 1;
```

`reason` is narrowed before it is stored (#1398), so it reads as the exception's leading clause
plus a marker — `key :program_id not found in: [redacted]`. A reason of
`[reason redacted: unrecognised message shape]` means the message matched no known shape and was
dropped whole; identify the error from `kind`, `source_function` and the occurrence's stacktrace,
and if the shape is one that carries no user data, add it to
`KlassHero.Shared.ErrorReasonFilter`'s allowlist so the next occurrence reads properly.

## Safety model

- `debug-ro` is the MPG `reader` role — **SELECT-only, structurally**. Writes are
  impossible, not merely discouraged. Never use the cluster's `schema_admin`
  logins for debugging reads.
- `fly mpg connect` proxies to the cluster **primary**; the read-only role — not
  a replica target — is what makes that safe.
- Revoke anytime: `fly mpg users delete ey5qn0y5d47o8zmw -u debug-ro`.

## Troubleshooting

| Symptom | Cause / fix |
|---|---|
| `not logged in` | `fly auth login` |
| `psql not found` (interactive mode) | `brew install libpq && brew link --force libpq` |
| `user_name must contain only lowercase letters, numbers, and dashes` | MPG rejects underscores — use `debug-ro`, not `debug_ro` |
| port 16380 in use | another `fly mpg connect` is still running |
