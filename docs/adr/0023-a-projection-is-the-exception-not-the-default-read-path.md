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
  page queries `programs`; the provider overview asks ProgramCatalog for its programs
  and Participation how many of their sessions completed; a conversation summary joins
  `enrollments`/`children`/`parents` when it is built. At current volumes these are
  indistinguishable from a table read, and every index the read tables carried already
  existed on the write side.
- **Retiring a projection can retire the ACL that fed it.**
  `ParticipationSessionStatsACL` was justified under ADR-0015's "a query no facade
  expresses" — true while it computed a grouped count across every provider for a
  bootstrap. Narrowed to one provider read per render, the facade composition was two
  cheap calls, and the ACL no longer earned its place. Check the justification of
  anything a deleted projection was the sole caller of; it was written for a workload
  that no longer exists.
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
- **A mirror can be a trigger as well as a cache, and that is easy to miss.**
  `messaging_enrolled_children` looked like a cached join, so removing it looked
  like replacing a read. It was also the thing that *refreshed*
  `conversation_summaries.enrolled_child_names` whenever a roster changed —
  re-deriving on `enrollment_created`, `enrollment_cancelled`, `child_created` and
  `child_updated` and stamping every existing summary row. Deleting it initially
  left that column frozen at conversation-creation time, so a provider's thread
  would have kept the roster it opened with until the next deploy re-bootstrapped
  it. Caught in review; the four subscriptions now sit on `ConversationSummaries`
  itself, which owns the column, rather than on a second projection calling back
  into the first. When reviewing a projection deletion, ask what *else* subscribed
  to those topics, not only what read that table.
- **The two survivors are on notice, not exempt.** `conversation_summaries` is the
  largest projection in the tree and the site of #1513, where it supplies the third
  of three disagreeing unread counters and the one users see is the wrong one.
  `provider_session_details` has the strongest case of any: a six-table join across
  three contexts with two LATERALs, sixteen topics, and attendance counters that are
  genuinely incremental.

  **Amended:** `conversation_summaries` was subsequently retired, leaving
  `provider_session_details` as the only projection. Three findings from that
  retirement, none of which this ADR anticipated:

  - **A projection also captures the live-update notification.** Being the last
    writer, it is the only place that knows the read is current, so it ends up
    owning the PubSub message that tells a mounted view to refetch. That reasoning
    inverts when the read goes live — the producer's write has committed, so the
    producer is the right notifier — but nothing *makes* you notice. No test of the
    projection can see it, and deleting one without moving the broadcast leaves
    views that simply stop updating. Retiring a projection always has a PubSub half.
  - **Topics can lose their last consumer, and `Outbox.stage/2` then drops the
    event — in tests too.** Nine of eleven did here, turning ten assertions red
    across eight files. That is the filter working as designed, but it reaches
    beyond the context: a Shared test had borrowed one of those topics purely as a
    vehicle for a payload. Unconsumed producers were left in place and filed
    (#1562) rather than unwound inside the retirement.
  - **Reading live can expose a latent write-model defect.** The incremental counter
    never compared timestamps, so second-precision columns and random-UUID message
    ids left the unread comparison without a total order. Nothing observed it until
    the read became a comparison. A projection can be *hiding* a bug rather than
    merely duplicating a fact.
- **The tables were dropped in the same release as the code.** Fly runs migrations as
  a `release_command`, before new machines take traffic, so the drop executes while
  the previous release is still reading those tables. #1321 split its equivalent drop
  across two releases to avoid exactly that window (#1347). Taking it here was a
  deliberate call given the traffic involved, not an oversight.
