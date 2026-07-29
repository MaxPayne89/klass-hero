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
- **Unclustered multi-node PubSub.** `klass-hero-live` runs two Fly machines with
  `DNS_CLUSTER_QUERY` unset, so `DNSCluster` starts as `:ignore` and every `Phoenix.PubSub`
  broadcast is node-local. Each node carried its own copy of all 7 projections — including
  `VerifiedProviders`' in-memory `MapSet` — which silently diverged whenever both machines were up.
  This is a second, independent generator of the "missing in the UI, appears after restart" symptom
  we had previously attributed only to missing dispatches on the write path.
- **No `Oban.Plugins.Lifeline`.** With `auto_stop_machines = "suspend"`, a machine suspending
  mid-job leaves that job `executing` forever with nothing to rescue it.

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

- **Projections are stateless — read tables only, no in-memory state.** This is what makes
  correctness independent of node topology: the job writes the table once and both nodes read the
  same rows. `VerifiedProviders`' `MapSet` becomes a query or a TTL cache.

- **Projections read the write model; they do not fold events.** `project_participant_added` looks
  the conversation up in the `conversations` table rather than accumulating prior events. This is
  what makes out-of-order and duplicate delivery safe, and it was previously an accident that no
  test asserted and no document named. **It is now an invariant.** A projection that folds events
  instead is silently corrupted by the at-least-once, unordered delivery this ADR introduces.

- **BEAM clustering is enabled**, but only so live UI updates reach users on either machine.
  Correctness no longer depends on it — that is the point of the layering.

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

- **Fixing only the clustering.** One secret, and it does make PubSub fan out. Rejected as a
  complete fix because it leaves correctness dependent on distribution: any netsplit or misconfigured
  secret silently reintroduces divergence, and the commit→publish window is untouched.

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

## Sequence

Six PRs, risk-ordered so the live defects are fixed before the structural churn. Each is
independently valuable and revertable.

| # | Change | Removes / fixes |
|---|---|---|
| 1 | `DNS_CLUSTER_QUERY` secret | #1189 — node-local live UI updates |
| 2 | Stateless projections | #1189 — per-node read-table divergence |
| 3 | UI tagged tuples | `NotifyLiveViews`, `WithDomainEvents`, `build_message_from_event`, 9 LiveViews |
| 4 | Outbox + Lifeline + `max_attempts` | #1190, #1191; 11 `EventSubscriber` specs |
| 5 | One struct, kill promotion | `DomainEvent`, 30 handlers, 7 modules, 2 publishers, 4 behaviours |
| 6 | Delete the bus, inline the 7 | 55 registrations, `subscribe/4` owner-scoping machinery |

The three defects are live today and independent of the refactor: PRs 1, 2 and the Lifeline half of
4 are worth landing whatever happens to the rest.
