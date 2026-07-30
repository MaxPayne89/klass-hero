# Events are delivered by a transactional outbox, not by PubSub

The event system grew a two-tier model — **domain events** dispatched on a per-context
`DomainEventBus`, promoted into **integration events** published over PubSub — on the premise that
the tiers distinguish *scope*: internal to a context versus crossing a boundary. Measured against
the code, the tiers distinguish nothing useful, and the layer that does the real work is the one
nobody designed.

Of 55 handler registrations in `application.ex`, **30** exist only to rename two fields on a struct
and re-publish it, **18** exist only to call `PubSub.broadcast`, and **7** do business work. All 7
survivors are same-context (Provider→Provider, Enrollment→Enrollment), so the decoupling rationale
for the bus applies to none of them. The bus itself is not a queue: `dispatch/2` looks handlers up
in a GenServer and then runs them **inline in the caller's process** — a function call with a lookup
table in front of it, invisible to `mix xref` and Dialyzer.

Meanwhile three delivery defects were live in production:

- **The commit→publish window.** Every publish site is post-commit and un-transactional
  (`persist_provider_profile(...)` then `publish_verification_event(...)`). The VM dying in between
  loses the event permanently. The dual PubSub+Oban "belt and suspenders" does not help: both belts
  fasten to the same buckle, since both are invoked from the same post-commit line. They protect
  against *subscriber* failure and nothing else.
- **No `Oban.Plugins.Lifeline`.** With `auto_stop_machines = "suspend"`, a machine suspending
  mid-job leaves that job `executing` forever with nothing to rescue it.

Node topology was investigated and cleared. `klass-hero-live` runs two Fly machines, and BEAM
clustering is correctly configured: `rel/env.sh.eex` exports `DNS_CLUSTER_QUERY`,
`RELEASE_DISTRIBUTION=name` and an IPv6 `proto_dist` at release boot — verified on the running node,
where `Application.get_env(:klass_hero, :dns_cluster_query)` returns `"klass-hero-live.internal"`.
PubSub does fan out across machines today. This is recorded because the delivery model below
deliberately stops depending on that fan-out for anything durable, which is a change in *why*
projections must be stateless, not a fix for an existing divergence.

The corrective instinct — "events should be async, so make dispatch async" — is aimed one layer too
high. Async *dispatch* would break the three places where synchronous execution is load-bearing
(priority-ordered handlers on `:invite_claimed`, the `dispatch_or_error` gate in the GDPR cascade,
error propagation into the caller's `with`). What actually needs to be asynchronous and durable is
**delivery**.

## Decision

- **Cross-context events are delivered by a transactional outbox.** The Oban job is enqueued
  *inside* the transaction that changed the state, so the event and the fact it describes commit or
  roll back together. The commit→publish window closes because there is no window: there is one
  commit.

- **One event struct.** `IntegrationEvent` survives (dropping the prefix); `DomainEvent` and its
  publisher, its two behaviours, `EventPublishing` and `WithDomainEvents` are deleted. The
  `version` field stayed `1` across 35 event types because one release deploys producer and consumer
  together — there is no skew to version against. What is worth keeping from that tier is
  `validate_critical_payload!`, which guards Oban's jsonb round-trip (#1010); it moves onto the
  single struct.

- **The `DomainEventBus` is deleted, not made async.** Its 7 surviving handlers are same-context and
  become direct calls, which restores compile-time checking, `xref` visibility, natural error
  propagation, and line-order sequencing. The runtime `subscribe/4` API — with its owner scoping,
  `:"$callers"` walking and `:DOWN` handling — had zero production callers and existed to stop async
  tests hearing each other; it moves to test support or goes.

- **The outbox job invokes anything that owns persistent state; PubSub carries only ephemeral UI.**
  A job that merely broadcasts is durable up to the broadcast and no further — a restarting
  subscriber still loses the event, and Oban has already marked the job complete. So the job calls
  cross-context handlers and projections directly and fails (and retries) if they fail. The 11
  `EventSubscriber` GenServers are deleted. LiveViews keep PubSub, because a dropped UI refresh is
  the one loss this system is allowed to take.

- **One job per transaction, carrying its events in order.** Four sites emit several events from one
  transaction. Batching them preserves today's inline in-order semantics exactly, which keeps "did
  this change behaviour?" answerable, and costs one insert per transaction instead of N.

- **Projections are stateless — read tables only, no in-memory state.** This is a *consequence* of
  the previous decision, not an independent one. Once the outbox job invokes projections directly
  instead of broadcasting, delivery reaches one node — the node running the job. A read table is
  shared, so that is fine; `VerifiedProviders`' in-memory `MapSet` is not, and the other machine's
  copy would never update. The `MapSet` becomes a query or a TTL cache. The payoff beyond enabling
  job-invoked delivery is that correctness stops depending on distribution at all: no netsplit,
  misconfigured release env, or future topology change can reintroduce divergence.

- **Projections read the write model; they do not fold events.** `project_participant_added` looks
  the conversation up in the `conversations` table rather than accumulating prior events. This is
  what makes out-of-order and duplicate delivery safe, and it was previously an accident that no
  test asserted and no document named. **It is now an invariant.** A projection that folds events
  instead is silently corrupted by the at-least-once, unordered delivery this ADR introduces.

- **Clustering stays as it is** — already correctly configured, and after this change it carries
  only ephemeral UI fan-out. That is the intended layering: distribution is a liveness concern, never
  a correctness one.

- **`processed_events` stays.** Oban is at-least-once, so the idempotency gate is still required.
  `RetryHelpers` goes: Oban owns retry, and three stacked retry policies for one row insert is two
  too many.

## Considered and rejected

- **Making bus dispatch async.** The stated goal, and the wrong layer. It severs the caller's Ecto
  sandbox connection (breaking projection tests), drops `Tracing.Context` unless threaded by hand,
  makes `dispatch_or_error` unable to return an error, and replaces free ordering with explicit
  sequencing — all to add asynchrony to seven same-context function calls.

- **Keeping post-commit dual delivery.** Cheapest, no call sites restructured. Rejected because the
  crash window is precisely the failure this system keeps producing, and the existing dual path
  demonstrably does not cover it.

- **Outbox for the critical 13 only.** Smaller change. Rejected because `provider_verified` — the
  event feeding two projections, and the one whose absence hides published programs — is not among
  the 13. Criticality was assigned per-event by hand and is not a reliable proxy for "must not be
  lost".

- **Leaning on clustering.** PubSub already fans out across machines, so in-memory projection state
  is consistent today and job-invoked delivery could be replaced by a cluster-wide broadcast.
  Rejected because a broadcast is durable only up to the broadcast: the job would be marked complete
  the instant the message was sent, so a subscriber restarting at that moment still loses the event
  with nothing to retry. That is the same hole the outbox exists to close, moved one hop later.

- **Keeping both structs and dropping only the promotion layer.** Deletes the 30 translation
  handlers without collapsing the model. Rejected because every new event then needs a
  which-struct decision, forever, with no rule that decides it.

- **Deleting the event struct entirely** and broadcasting plain entities. Rejected: it gives up
  `event_id` (so `processed_events` has no key), payload validation, and a stable Oban serialization
  contract.

## When to revisit

- **If a projection ever needs to fold events** rather than read the write model — for a running
  total, a history, or anything the source tables cannot answer. That breaks the stated invariant and
  forces per-entity ordering (an Oban partition key on `entity_id`) before it can be built.
- **If cross-context reaction latency becomes user-visible.** Reactions now land on Oban pickup
  rather than instantly. `user_registered → create parent profile` is the one to watch; the
  `user_confirmed` compensation path exists because that ordering has bitten before.
- **If the batch grain hurts.** One job per transaction means a poisoned event re-publishes its
  siblings on retry (deduped by `processed_events`, but wasted work). Per-event jobs with an
  `entity_id` partition key are the escape hatch.
- **If the app scales past a couple of machines**, where the `email: 1` queue comment already flags a
  known problem — that queue is per-node, so concurrency is already the machine count, not 1.

## Sequence — shipped

Six PRs, risk-ordered so the live defects were fixed before the structural churn.

| # | Change | Removed / fixed | PR |
|---|---|---|---|
| 1 | `Oban.Plugins.Lifeline` + raise `max_attempts` | #1191 — orphaned jobs never rescued | #1193 |
| 2 | Stateless projections | `VerifiedProviders`' in-memory `MapSet` | #1196 |
| 3 | Outbox + job-invoked consumers | #1190 — commit→publish window; 11 `EventSubscriber` specs | #1207 |
| 4 | UI tagged tuples | `NotifyLiveViews`, `WithDomainEvents`, 9 LiveViews | #1208 |
| 5 | One struct, kill promotion | `DomainEvent`, 30 handlers, 7 promoters, 2 publishers | #1211 |
| 6 | Delete the bus, inline the 7 | `DomainEventBus`, `EventDispatchHelper`, `subscribe/4` | — |

PR 6 found the bus emptier than this ADR's count implies. Of 27 dispatch call sites, **21 targeted
a bus with no handler registered for that event type** — five of the seven bus instances ran with
`handlers: []`. It also retired the parallel durable-retry path (`CriticalEventWorker`), which
existed only because a bus handler ran inside the producer's process and a failure there had
already escaped the transaction.

Two of this ADR's three reasons for keeping dispatch synchronous had decayed before PR 6 started:
the priority ordering on `:invite_claimed` lost its second handler in PR 5, and the GDPR cascade's
`dispatch_or_error` gate was replaced in PR 4. Only error propagation was still load-bearing, at
two call sites, and inlining preserved it.

PR 1 is a live defect fix independent of everything else and should land whatever happens to the
rest. PR 4 is independent of 1–3 and can be reordered freely. PR 2 must precede PR 3, because
job-invoked delivery reaches one node and an in-memory projection on the other would never update.
