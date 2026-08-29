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
- **A facade owns its return types, so naming what it returns is not a violation.**
  `Provider.get_staff_member/2` yields `{:ok, %StaffMember{}}`, so any caller must name that
  struct to spec it, match on it, or read a field off it — and may re-export it through its
  own `@spec`. Alias, typespec, pattern match, field read and re-export are all fine. The
  coupling is created by the shape of the facade's public API, not by the caller's alias;
  chasing the alias without changing the return type would only replace a named struct with
  an unnamed one, and under schema-as-struct the entity **is** the DTO, so a struct twin to
  hide it is the wrong trade. The violation line is `Repo`/query access to the other
  context's tables — that, not the alias, is what to look for. Reference: `accounts.ex`
  names `Provider.StaffMember` in four `@spec`s and three pattern matches and issues no
  query against Provider's tables (#1434).
- **Never declare a `belongs_to`/`has_one` onto another context's schema.** Store the
  correlation id as a plain `field` and read across via the facade. ADR 0001 already forbids
  the SQL join; the association is the thing that makes one reachable, from any call site,
  with a single `Repo.preload/2`. #1434 removed the ten that existed — eight had never been
  preloaded at all. Two traps when removing one: without `define_field: false` the
  `belongs_to` is the **sole** declaration of the id field, so it must be *replaced* with
  `field :x_id, :binary_id`, not deleted — deleting it silently drops a column the changeset
  still casts; and `foreign_key_constraint/2` and `unique_constraint/2` keep working either
  way, since both key off the field name rather than the association.
  **One survives, on the cycle-breaking ground ADR 0015 already grants:**
  `Enrollment.program` → `ProgramCatalog.Program`. ProgramCatalog depends on Enrollment for
  capacity, so Enrollment cannot call its facade, and direct `programs` access is sanctioned
  for that pair (`enrollment/…/acl/program_catalog_acl.ex`). `Admin.BookingLive` needs a real
  association for its Backpex `Fields.BelongsTo` to search and sort by title. The test is the
  ADR-0015 justification, not the module name — no other pair currently has one, and a new
  association still has to earn it.
  **A Backpex `Fields.BelongsTo` is a consumer no grep will find.** It names the association
  declaratively — no `preload`, no `Repo.preload`, no `assoc/2` — and joins the other table to
  search and sort. Check `lib/klass_hero_web/live/admin/` before concluding an association is
  unused.
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

CQRS here means a read model separate from the write model. It does **not** mean a
second table maintained asynchronously — that is one implementation of it, and the
expensive one. Two of the three kinds below need no projection at all.

- **A projection is the exception, and needs justifying.** Four were retired by
  ADR-0023 because they earned nothing: `program_listings` mirrored
  `programs` 1:1 inside the same context, `provider_programs` mirrored three of its
  columns into Provider, `provider_session_stats` denormalised one integer, and
  `messaging_enrolled_children` had no reader outside another projection. Before
  adding one, answer: what query cannot be served by a facade call (ADR-0015) or a
  same-context query, at the scale this system actually runs at?

- **What a projection costs, so the trade is visible.** Two implementations of the
  same read — `handle_event/2` incrementally and `bootstrap_impl/0` from scratch —
  which must agree forever; three bugs (#782, #1299, #1329) were those two paths
  disagreeing. Bootstrap also *hides* failure: a deploy re-bootstraps and self-heals
  the table while the pipeline stays broken, so zero observed drift is the symptom
  rather than evidence of health. Every row in `undelivered_events` to date has been
  a projection dispatch.

- **Three read-side kinds, three homes.** Getting this wrong is what produced
  #1254/#1258, so pick deliberately:

  | Kind | Home | Shape | Example |
  |---|---|---|---|
  | Query over the **write** table | the context module | ordinary `Repo` query returning the entity struct; the default | `program_catalog.ex`'s `list_programs_for_provider/1` |
  | Query-shaped struct over **write** tables | `read_models/` | plain struct, no schema twin, no table; built by a `select:` or a `from_*/1` narrowing | `provider/read_models/staff_membership.ex` |
  | Projection read **table** | context root, or `projections/` | Ecto schema **is** the DTO; **no changeset** — the projection owns every write; string columns are **`text`**, never a capped `varchar` | `provider/session_detail.ex` |

- **A length cap on a read table is unenforceable, so it is a liability.** The
  no-changeset rule is what makes it one: a `varchar(n)` there cannot reject an
  over-long value, only raise 22001 inside `EventDeliveryWorker`, exhaust Oban's ten
  attempts and discard the event — losing every field of that update, not just the
  long one (#1376). Read-table string columns are `text`; caps belong on the write
  side, where a changeset turns them into a user-visible error. Enforced by
  `test/klass_hero/shared/read_table_column_types_test.exs`, which reads
  `information_schema` — `mix lint_read_tables` is text-based and cannot see it.

- **A table maintained by events but with no projection is worse still.** It has no
  bootstrap and no rebuild, so nothing but an event can ever correct it. Its only
  instance was `messaging/program_staff_participant.ex`, a mirror of Provider's
  staffing that #1321 deleted after three drift bugs (#1309, #1312, #1320). If the
  data is derivable from another context, call that context's facade and keep no
  copy.

- **Queries go in the context module or a context-root submodule** (`provider/programs.ex`, `provider/assignments.ex`) — never behind a per-table repository wrapper. A read-only module that just wraps `where`/`order_by`/`Repo.all` is indirection without a payer.
- No mappers, and no separate DTO twinned with a projection schema. If you are writing a `to_dto/1`, the two modules should be one.
- Build a projection — once justified — on `KlassHero.Shared.Projection` (base macro); optionally `KlassHero.Shared.Projection.WithBootstrapRetry` (linear-backoff retry). Declare `:topics` in `use Projection, ...` and implement `bootstrap_impl/0` and `handle_event/2`.
- Canonical example: `provider/projections/provider_session_details.ex` with its read table `provider/session_detail.ex`. It is the one that earns its place — a six-table join across three contexts with two LATERALs, and genuinely incremental attendance counters. It is also the only projection left anywhere: `conversation_summaries` was retired once the inbox, the unread badge and conversation titling all read the write model live.

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
- `lib/klass_hero/provider/session_detail.ex` — read-table schema as the display DTO
- `lib/klass_hero/provider/projections/provider_session_details.ex` — projection pattern
- `lib/klass_hero/shared/` — event infrastructure, projection macro, interaction/tracing
- `config/config.exs` — `:event_consumers` registry (DI port maps are gone)
