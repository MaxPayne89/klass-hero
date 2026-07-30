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
├── <use_case>.ex           # Command/query modules at the root
├── domain/
│   ├── events/             # Domain & integration event structs
│   └── read_models/        # CQRS read-model DTOs (no logic)
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
- `adapters/driven/persistence/` — Ecto schemas/repos for **projection read tables only**
- `adapters/driven/acl/` — cross-context read adapters (anti-corruption layer)
- `adapters/driven/notifications/` — email/notification senders
- `adapters/driving/events/` — event handlers reacting to other contexts' events
- `adapters/driving/workers/` — Oban workers

## Cross-Context Access

- Call other contexts **only** through their root `<context>.ex` module — never their internal schemas/Repo.
- For cross-context **reads**: use an ACL adapter (`adapters/driven/acl/`) or subscribe an event handler that builds a local read model. Prefer projections over ACLs for hot read paths.
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
- Read-model DTOs in `domain/read_models/` are display-optimized structs with no business logic.
- Build new projections on `KlassHero.Shared.Projection` (base macro); optionally `KlassHero.Shared.Projection.WithBootstrapRetry` (linear-backoff retry). Declare `:topics` in `use Projection, ...` and implement `bootstrap_impl/0` and `handle_event/2`.
- Canonical example: `provider/adapters/driven/projections/provider_programs.ex`. Program Catalog and Messaging also have projections.

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
- `lib/klass_hero/provider/adapters/driven/projections/provider_programs.ex` — projection pattern
- `lib/klass_hero/shared/` — event infrastructure, projection macro, interaction/tracing
- `config/config.exs` — `:event_consumers` registry (DI port maps are gone)
