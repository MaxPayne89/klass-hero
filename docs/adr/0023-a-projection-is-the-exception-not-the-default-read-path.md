# A projection is the exception, not the default read path

Four of the six CQRS projections were deleted, along with their read tables. A read
model is still separate from the write model — that is what CQRS asks for — but it is
now a *query*, not a second table maintained asynchronously. Adding a projection
requires naming the query that a facade call (ADR-0015) or a same-context query
cannot serve.

Retired: `program_listings`, `provider_programs`, `provider_session_stats`,
`messaging_enrolled_children`. Kept: `provider_session_details` and
`conversation_summaries`.

## Why

**The payoff was not there.** Measured against production the same week they were
removed: `program_listings` and `provider_programs` held 14 rows each,
`provider_session_stats` 5, `messaging_enrolled_children` 50. The largest read table
in the system holds 133. No projection avoided a query that is expensive at this
scale, or would be at a hundred times it.

**Two of the four were not denormalising anything.** `program_listings` was a 1:1
mirror of `programs` *inside the same context* — ProgramCatalog staged an integration
event, Oban delivered it, and a GenServer copied ProgramCatalog's own row into
ProgramCatalog's other table. `messaging_enrolled_children` had no reader outside the
projection layer at all: its only consumer was another projection.

**The cost was structural, not incidental.** Two independent things:

1. *Every projection is two implementations of one read.* `handle_event/2` maintains
   the table incrementally; `bootstrap_impl/0` recomputes it from scratch. They must
   agree forever, and three filed bugs (#782, #1299, #1329) were exactly those two
   paths disagreeing.
2. *Bootstrap hides the failure it should expose.* A deploy re-bootstraps and
   self-heals the read table while the delivery pipeline stays broken, so zero
   observed drift is the expected symptom rather than evidence of health. Every row
   in `undelivered_events` — six at the time of writing, none replayed — is a
   projection dispatch. All recorded event loss in this system has been projection
   maintenance.

**Tests could not see them.** `config/test.exs` sets `start_projections: false`, so
no projection GenServer runs under test; 45 test files hand-maintained read-table
rows instead, most inserting a projection row *and* a write row pinned to the same
id. #1196 is the precedent that matters: `VerifiedProviders` wrote the wrong value
for every row of its entire life because its GenServer never ran, and the test
asserted that artifact as the expected default.

**The direction was already set.** ADR-0015 made facade-direct the default for
cross-context reads at every layer. ADR-0016 superseded ADR-0002 by deleting a
denormalised instructor copy for a live facade read. #1196 deleted a projection for
one facade call; #1321 deleted a mirror after three drift bugs. These four were the
part that had not caught up.

## Consequences

- **The default read is a query over the write table**, returning the entity struct.
  Under schema-as-struct that struct *is* the DTO, so nothing is lost by not minting
  a second one. Where a distinct read type earns its place, the `read_models/` kind
  already exists — a query-shaped struct with no table behind it.
- **Deleting a mirror moves work to read time, and that is the trade.** The catalog
  page now queries `programs`; the provider overview counts `program_sessions`
  through an ACL; a conversation summary joins `enrollments`/`children`/`parents`
  when it is built. At current volumes these are indistinguishable from a table read,
  and every index the read tables carried already existed on the write side.
- **Consistency improves where it used to be eventual.** `SubmitIncidentReport`
  validated program ownership against `provider_programs`, which the projection's own
  moduledoc warned was unsuitable for a write-path guard; a report filed against a
  just-created program could be refused as foreign. It now reads the write model.
  Similarly, the provider programs list no longer needs the branch that existed
  purely to paper over projection lag after a save.
- **A UI update announced by a projection moves to whoever wrote the data.**
  `provider_session_stats` broadcast `:session_stats_updated` from inside the
  projection; that broadcast now comes from Participation's session-completion path,
  which is what the "UI updates are not events" rule prescribed all along.
- **Three topics lost their only consumer** — `integration:family:child_created`,
  `child_updated`, and `integration:enrollment:enrollment_cancelled`. `Outbox.stage/2`
  filters on the consumer registry, so they stop being staged with no producer
  change. #1511 will want `enrollment_cancelled` consumed again; adding a registry
  entry resumes staging.
- **The two survivors are on notice, not exempt.** `conversation_summaries` is the
  largest projection in the tree and the site of #1513, where it supplies the third
  of three disagreeing unread counters and the one users see is the wrong one.
  `provider_session_details` has the strongest case of any: a six-table join across
  three contexts with two LATERALs, sixteen topics, and attendance counters that are
  genuinely incremental.
- **The tables were dropped in the same release as the code.** Fly runs migrations as
  a `release_command`, before new machines take traffic, so the drop executes while
  the previous release is still reading those tables. #1321 split its equivalent drop
  across two releases to avoid exactly that window (#1347). Taking it here was a
  deliberate call given the traffic involved, not an oversight.
