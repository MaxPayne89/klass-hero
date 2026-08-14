# Domain Architecture

The project **used to** follow Domain-Driven Design with Ports & Adapters (Hexagonal). All 7 bounded contexts were flattened to **conventional Phoenix** (PRs #986→#1002); the `boundary` library was removed. Contexts remain as bounded contexts by convention — this doc describes the post-flatten shape.

## Bounded Contexts

Domain contexts under `lib/klass_hero/`, each with a public API module `<context>.ex`:

1. **Accounts** — auth (`phx.gen.auth`), scopes, roles, tokens
2. **Program Catalog** — program discovery, details, availability, pricing
3. **Enrollment** — enrollment/booking from selection to payment
4. **Family** — parent profiles, children, consents, referral codes, GDPR family data
5. **Provider** — provider profiles, staff members, verification/incident documents
6. **Messaging** — conversations, messages, participants, support inbox, email
7. **Participation** — session tracking, check-in/out, attendance, behavioral notes
8. **Shared** — event infrastructure, projection macro, interaction/tracing, entitlements

(Progress Tracking and Review & Rating are planned, not yet implemented.)

## Context Layout (conventional Phoenix)

```
context.ex                  # Public API — the ONLY module other contexts call
context/
├── <entity>.ex             # Schema-as-struct (see below)
├── <read_table>.ex         # Projection read-table schema — IS the DTO, no changeset
├── <use_case>.ex           # Command/query modules at the root
├── domain/
│   ├── events/             # Domain & integration event structs
│   └── read_models/        # Query-shaped structs over WRITE tables only (no logic,
│                           #   no schema twin) — see "CQRS Read Models"
└── adapters/
    ├── driven/{projections,persistence,acl,notifications}/
    └── driving/{events,workers}/
```

### Schema-as-struct

An entity is **one module** that is simultaneously:
- the **Ecto schema** + changesets (the validation gatekeeper at the DB boundary), and
- the **struct** callers pattern-match on, and
- the **functional core** — pure business logic ported from the former domain model (state machines like `transition_invitation/2`, `full_name/1`, `initials/1`, domain validators returning `{:error, [message]}` lists).

`provider/staff_member.ex` is the canonical example — read its moduledoc. No separate `domain/models/`, no mappers, no ports.

### What survives in `adapters/`

The flatten deleted aggregate ports, mappers, and DI wiring. Subdirectories remain only where indirection earns its place:

- `adapters/driven/projections/` — CQRS projection GenServers
- `adapters/driven/persistence/queries/` — composable query builders over a context's own
  **write-side** tables (Messaging's `conversation_queries.ex`, `message_queries.ex`). Only
  earns its place when the bindings are genuinely composed by more than one caller
- `adapters/driven/persistence/{repositories,schemas}/` — **Shared only**, for the event and
  job infrastructure tables (`processed_events`, `job_compensations`, `undelivered_events`).
  Internal to Shared's exactly-once and dead-letter machinery — each schema's moduledoc says
  so — never domain models. No bounded context has a repository left; do not copy this into one
- `adapters/driven/acl/` — cross-context read adapters (anti-corruption layer)
- `adapters/driven/notifications/` — email/notification senders
- `adapters/driving/events/` — event handlers reacting to other contexts' events
- `adapters/driving/workers/` — Oban workers

## Cross-Context Access

- Call other contexts **only** through their root `<context>.ex` module — never their internal schemas/Repo.
- For cross-context **reads**: **call the owning context's root facade directly** (ADR 0015). This is the default at every layer — a projection, event handler, worker or web helper calls the facade with no adapter in between. Reach for something heavier only when it earns its place:
  - an **ACL adapter** (`adapters/driven/acl/`) when there is genuine translation to do — remapping the other context's errors into your vocabulary, masking fields behind a business rule, cycle-breaking direct table access, or a query no facade expresses. An ACL that only forwards a call is indirection without a payer; fold it into the caller.
  - a **projection** when a per-render facade call cannot serve the read path.
- There is **no** per-context *aggregate* `config :klass_hero, :<context>, for_managing_*: Adapter` DI wiring anymore. Call collaborators directly. (Shared is the exception: its genuine env-swapped adapter seams — `outbox`, `feature_flags`, `storage`, `for_tracking_processed_events` — keep a slim behaviour at the Shared root + a config-selected impl. That is idiomatic Elixir DI, not ceremony; see ADR 0006.)

## Event System

Directionality still classifies the surviving event code:

> If Oban triggers it, it's **driving**. If the application calls it outward, it's **driven**.

- **One `Event` struct**, staged inside the producer's transaction via `Shared.Outbox.transact/2` and delivered by `EventDeliveryWorker`, an Oban job. Consumers are registered per topic under `:event_consumers` in `config/config.exs`; that registry is also the staging filter, so an event nobody consumes is dropped rather than staged.
- **Same-context reactions are not events.** A producer calls them directly, inside its own transaction, so the write and its consequence commit together.
- **UI updates are not events either.** A LiveView receives a plain tagged tuple over `Phoenix.PubSub` naming what changed, broadcast post-commit by whoever wrote the data.
- **Shared event infrastructure** (`shared/outbox.ex`, `shared/adapters/driven/events/`, `shared/adapters/driven/workers/event_delivery_worker.ex`): staging adapters, the consumer registry, the exactly-once gate, retry helpers, test doubles — driven, because the application calls them outward. Context consumers live under their own `adapters/driving/events/`.

## CQRS Read Models

- Projection GenServers in `adapters/driven/projections/` subscribe to events and denormalize into dedicated read tables.
- **Three read-side kinds, three homes.** Getting this wrong is what produced #1254/#1258, so pick deliberately:

  | Kind | Home | Shape | Example |
  |---|---|---|---|
  | Projection read **table** | context root | Ecto schema **is** the DTO; **no changeset** — the projection owns every write | `provider/provider_program.ex`, `messaging/enrolled_child.ex` |
  | Query-shaped struct over **write** tables | `domain/read_models/` | plain struct, no schema twin, no table; built by a `select:` or a `from_*/1` narrowing | `provider/domain/read_models/staff_membership.ex` |
  | Event-maintained table with **no** projection | context root + an ops submodule | schema **keeps** its changeset, because a handler writes it directly | *none — see below* |

- **The third kind currently has no instance, and that is a warning, not an
  omission.** Its only example was `messaging/program_staff_participant.ex` +
  `messaging/staff_participants.ex`, a mirror of Provider's staffing that #1321
  deleted. A table with no projection has no bootstrap and no rebuild, so nothing
  but an event can ever correct it — and three bugs (#1309, #1312, #1320) were
  drift between that copy and its source. Before reaching for this kind, check
  whether the data is **derivable** from another context: if it is, call that
  context's facade (ADR-0015) and keep no copy. Reserve the kind for state that is
  genuinely yours and has no source to re-derive from — rows carrying their own
  history, like join/leave times or read receipts.

- **Queries go in the context module or a context-root submodule** (`provider/programs.ex`, `provider/assignments.ex`) — never behind a per-table repository wrapper. A read-only module that just wraps `where`/`order_by`/`Repo.all` is indirection without a payer.
- No mappers, and no separate DTO twinned with a projection schema. If you are writing a `to_dto/1`, the two modules should be one.
- Build new projections on `KlassHero.Shared.Projection` (base macro); optionally `KlassHero.Shared.Projection.WithBootstrapRetry` (linear-backoff retry). Declare `:topics` in `use Projection, ...` and implement `bootstrap_impl/0` and `handle_event/2`.
- Canonical examples: `provider/adapters/driven/projections/provider_programs.ex` for the projection GenServer, and `program_catalog/program_listing.ex` for the read table a projection maintains — copy the latter for the schema-is-the-DTO shape. Program Catalog, Messaging, and Provider all have projections.

## Domain Modeling Idioms

DDD coding patterns for this project (generic BEAM/Phoenix idioms live in `elixir-style.md` and the `elixir-phoenix` plugin; these are the domain-modeling-specific ones):

- **Protocols for polymorphic data** — use `defprotocol`/`defimpl` when different domain types need the same operation with different implementations (`Priceable`, `Serializable`). Protocols for data; behaviours only for genuinely swappable *modules* (feature-flag adapters, external clients) — never to wrap `Repo` (ports were deleted, #986–#1002).
- **Contexts are DDD bounded contexts** — each context owns its data and logic; other contexts talk only to its public `<context>.ex` API, never its internals (see `## Cross-Context Access`).
- **Aggregates with structs** — an aggregate root enforces its invariants; external code never mutates nested entities directly, only through the root.
- **Changesets are the validation boundary** — validate at the DB boundary; changesets are the gatekeepers that accumulate errors and admit only valid data. Context-specific (create vs update) changesets are expected.
- **Functional core, imperative shell** — the core computes (pure, framework-agnostic, exhaustively unit-tested); the shell acts (side effects, integration-tested). Schema-as-struct entities *are* the functional core (validators, state machines inline); the context module is the shell.

Schema-as-struct itself is covered above under `## Context Layout` and `## Recommended Reads` — new query/persistence code goes in `<context>.ex`, new validation in the entity's changesets.

## Recommended Reads

- `lib/klass_hero/provider/staff_member.ex` — schema-as-struct with inlined functional core
- `lib/klass_hero/program_catalog/program_listing.ex` — read-table schema as the display DTO
- `lib/klass_hero/provider/adapters/driven/projections/provider_programs.ex` — projection pattern
- `lib/klass_hero/shared/` — event infrastructure, projection macro, interaction/tracing
- `config/config.exs` — `:event_consumers` registry (DI port maps are gone)
