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
- There is **no** `config :klass_hero, :<context>, for_managing_*: Adapter` DI wiring anymore. Call collaborators directly.

## Event System

Directionality still classifies the surviving event code:

> If Oban or the event bus triggers it, it's **driving**. If the application calls it outward, it's **driven**.

- **Domain events** (non-critical) — published via PubSub for real-time UI updates.
- **Integration events** (critical) — routed through the `critical_event_handlers` registry in `config/config.exs` to Oban-backed handlers for durable, at-least-once cross-context delivery.
- **Shared event infrastructure** (`shared/adapters/driven/events/` + `shared/domain_event_bus.ex`, `event_dispatch_helper.ex`, `integration_event_publishing.ex`): publishers, subscriber, registry, retry helpers, test doubles — driven, because the application calls them outward. Individual context handlers live under their own `adapters/driving/events/`.

## CQRS Read Models

- Projection GenServers in `adapters/driven/projections/` subscribe to events and denormalize into dedicated read tables.
- Read-model DTOs in `domain/read_models/` are display-optimized structs with no business logic.
- Build new projections on `KlassHero.Shared.Projection` (base macro); optionally `KlassHero.Shared.Projection.WithBootstrapRetry` (linear-backoff retry). Declare `:topics` in `use Projection, ...` and implement `bootstrap_impl/0` and `handle_event/2`.
- Canonical example: `provider/adapters/driven/projections/provider_programs.ex`. Program Catalog and Messaging also have projections.

## Recommended Reads

- `lib/klass_hero/provider/staff_member.ex` — schema-as-struct with inlined functional core
- `lib/klass_hero/provider/adapters/driven/projections/provider_programs.ex` — projection pattern
- `lib/klass_hero/shared/` — event infrastructure, projection macro, interaction/tracing
- `config/config.exs` — `critical_event_handlers` registry (DI port maps are gone)
