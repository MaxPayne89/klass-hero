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
├── events.ex               # Factory for this context's integration events
├── <handler>.ex            # Consumes another context's events
├── <worker>.ex             # Oban worker
├── projections/            # CQRS projection GenServers          (3+ files)
├── workers/                # Oban workers                         (3+ files)
├── acl/                    # Cross-context read adapters          (3+ files)
├── notifications/          # Email/notification senders           (3+ files)
├── queries/                # Composable write-side query builders (3+ files)
└── read_models/            # Query-shaped structs over WRITE tables (3+ files)
```

**One level, and only when it earns it.** A kind gets its own directory once it
holds **3+ files**; below that its modules sit at the context root. Same
extraction threshold the front end uses for components (`frontend.md`).

The threshold covers **only the kinds listed above**. It does not license a
catch-all: `services/`, `helpers/`, `support/` are not kinds — "service" is DDD
for "module I could not otherwise place", and such a directory sorts modules by
having no category. Pure domain-logic modules (`program_pricing.ex`,
`csv_parser.ex`, `referral_code_generator.ex`) sit at the **context root** beside
the use cases, however many there are.

There is no `adapters/` or `domain/` layer, and no `driven`/`driving` split. The
kind name already carries directionality — a handler or worker is inbound, a
projection, ACL, or notification is outbound — so encoding it a second time in
the path bought nothing and cost two segments on every module name.

`accounts/` is the reference: nothing there reaches three files, so the whole
context is flat.

See ADR 0018 for the reasoning.

> **Migration in progress.** Accounts, Provider, Family and Messaging are flat. The other three contexts still carry
> the old `adapters/{driven,driving}/…` + `domain/…` tree and are being converted
> one PR at a time. **Both shapes are legal until that finishes** — do not flag an
> unconverted context as a violation, and do not half-convert one as a drive-by.
> When reading the sections below, `adapters/driven/projections/` and
> `projections/` name the same thing.

### Schema-as-struct

An entity is **one module** that is simultaneously:
- the **Ecto schema** + changesets (the validation gatekeeper at the DB boundary), and
- the **struct** callers pattern-match on, and
- the **functional core** — pure business logic ported from the former domain model (state machines like `transition_invitation/2`, `full_name/1`, `initials/1`, domain validators returning `{:error, [message]}` lists).

`provider/staff_member.ex` is the canonical example — read its moduledoc. No separate `domain/models/`, no mappers, no ports.

### Which kinds exist

The flatten deleted aggregate ports, mappers, and DI wiring. These kinds remain — each at
the context root, or in a same-named directory once it holds 3+ files:

- `projections/` — CQRS projection GenServers
- `queries/` — composable query builders over a context's own **write-side** tables
  (Messaging's `conversation_queries.ex`, `message_queries.ex`). Only earns its place when
  the bindings are genuinely composed by more than one caller
- `acl/` — cross-context read adapters (anti-corruption layer)
- `notifications/` — email/notification senders
- event handlers reacting to other contexts' events — named for what they consume
  (`staff_invitation_handler.ex`), not filed under an `events/` directory
- `workers/` — Oban workers
- `events.ex` — the factory for the context's own integration event structs

**Shared is the exception.** `shared/adapters/driven/persistence/{repositories,schemas}/`
holds the event and job infrastructure tables (`processed_events`, `job_compensations`,
`undelivered_events`) — internal to Shared's exactly-once and dead-letter machinery, as each
schema's moduledoc says, never domain models. No bounded context has a repository left; do
not copy this into one.

## Cross-Context Access

- Call other contexts **only** through their root `<context>.ex` module — never their internal schemas/Repo.
- For cross-context **reads**: **call the owning context's root facade directly** (ADR 0015). This is the default at every layer — a projection, event handler, worker or web helper calls the facade with no adapter in between. Reach for something heavier only when it earns its place:
  - an **ACL adapter** (`acl/`) when there is genuine translation to do — remapping the other context's errors into your vocabulary, masking fields behind a business rule, cycle-breaking direct table access, or a query no facade expresses. An ACL that only forwards a call is indirection without a payer; fold it into the caller.
  - a **projection** when a per-render facade call cannot serve the read path.
- **One-shot migration backfills are exempt**, and only they. A module under
  `lib/klass_hero/release/` called from a migration's `up/0` may read another
  context's tables directly in raw SQL, with no facade and no `acl_span`. A facade
  is compiled against *today's* schema and is the wrong shape to point at a
  mid-migration database, and a per-row round-trip would turn one statement into N.
  The rules that keep it honest: the transform lives outside the migration so it is
  unit-tested (#966), it is idempotent, and it raises rather than guessing on a row
  it cannot resolve. Each one states its reasoning in a "Why this bypasses…"
  moduledoc section — precedent: `dedup_active_staff_memberships.ex` (#969),
  `backfill_direct_conversation_principals.ex` (#747).
  **`mix lint_acl_boundary` cannot see these reads** — it matches Ecto's schemaless
  `in "table"` binding, not a table name inside a SQL heredoc — so the moduledoc is
  the only record that the exemption was taken deliberately.
- There is **no** per-context *aggregate* `config :klass_hero, :<context>, for_managing_*: Adapter` DI wiring anymore. Call collaborators directly. (Shared is the exception: its genuine env-swapped adapter seams — `outbox`, `feature_flags`, `storage`, `for_tracking_processed_events` — keep a slim behaviour at the Shared root + a config-selected impl. That is idiomatic Elixir DI, not ceremony; see ADR 0006.)

## Event System

- **One `Event` struct**, staged inside the producer's transaction via `Shared.Outbox.transact/2` and delivered by `EventDeliveryWorker`, an Oban job. Consumers are registered per topic under `:event_consumers` in `config/config.exs`; that registry is also the staging filter, so an event nobody consumes is dropped rather than staged.
- **Same-context reactions are not events.** A producer calls them directly, inside its own transaction, so the write and its consequence commit together.
- **UI updates are not events either.** A LiveView receives a plain tagged tuple over `Phoenix.PubSub` naming what changed, broadcast post-commit by whoever wrote the data.
- **Shared event infrastructure** (`shared/outbox.ex`, `shared/adapters/driven/events/`, `shared/adapters/driven/workers/event_delivery_worker.ex`): staging adapters, the consumer registry, the exactly-once gate, retry helpers, test doubles. Context consumers live in the context that consumes the event.

## CQRS Read Models

- Projection GenServers in `projections/` subscribe to events and denormalize into dedicated read tables.
- **Three read-side kinds, three homes.** Getting this wrong is what produced #1254/#1258, so pick deliberately:

  | Kind | Home | Shape | Example |
  |---|---|---|---|
  | Projection read **table** | context root | Ecto schema **is** the DTO; **no changeset** — the projection owns every write; string columns are **`text`**, never a capped `varchar` | `provider/provider_program.ex`, `messaging/enrolled_child.ex` |
  | Query-shaped struct over **write** tables | `read_models/` | plain struct, no schema twin, no table; built by a `select:` or a `from_*/1` narrowing | `provider/read_models/staff_membership.ex` |
  | Event-maintained table with **no** projection | context root + an ops submodule | schema **keeps** its changeset, because a handler writes it directly | *none — see below* |

- **A length cap on a read table is unenforceable, so it is a liability.** The
  no-changeset rule is what makes it one: a `varchar(n)` there cannot reject an
  over-long value, only raise 22001 inside `EventDeliveryWorker`, exhaust Oban's ten
  attempts and discard the event — losing every field of that update, not just the
  long one (#1376). Read-table string columns are `text`; caps belong on the write
  side, where a changeset turns them into a user-visible error. Enforced by
  `test/klass_hero/shared/read_table_column_types_test.exs`, which reads
  `information_schema` — `mix lint_read_tables` is text-based and cannot see it.

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
- Canonical examples: `provider/projections/provider_programs.ex` for the projection GenServer, and `program_catalog/program_listing.ex` for the read table a projection maintains — copy the latter for the schema-is-the-DTO shape. Program Catalog, Messaging, and Provider all have projections.

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
- `lib/klass_hero/provider/projections/provider_programs.ex` — projection pattern
- `lib/klass_hero/shared/` — event infrastructure, projection macro, interaction/tracing
- `config/config.exs` — `:event_consumers` registry (DI port maps are gone)
