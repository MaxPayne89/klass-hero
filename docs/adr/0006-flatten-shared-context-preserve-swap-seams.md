# Flattening the Shared context keeps its env-swapped adapter seams

**Shared** (`lib/klass_hero/shared/`) was the 8th and last bounded context still carrying the DDD/Ports & Adapters directory tree after the #986→#1002 flatten. It retained `domain/ports/`, `domain/models/`, `domain/services/`, `domain/types/`, `domain/validation.ex`, and `adapters/driven/`. Unlike the earlier flattens — whose aggregate ports were pure ceremony (a single production impl hiding behind an interface) — Shared's ports back **genuine env-swapped adapter seams** the test suite depends on:

- `for_publishing_events` → `PubSubEventPublisher` (prod) vs `TestEventPublisher` (test)
- `for_publishing_integration_events` → real vs `TestIntegrationEventPublisher`
- `for_managing_feature_flags` → `FunWithFlagsAdapter` vs `StubFeatureFlagsAdapter`
- `for_storing_files` → `S3StorageAdapter` vs `StubStorageAdapter`
- `for_tracking_processed_events` → `ProcessedEventRepository` (transactional idempotency boundary)

A behaviour module + config-selected impl is **idiomatic Elixir dependency injection**, not DDD ceremony. The flatten must remove the *port/adapter directory ceremony* and any dead indirection — never the swap mechanism.

The conventional-Phoenix target tree also *keeps* `domain/events/` (event structs) and all of `adapters/driven/**` (driven adapters). So Shared's event-envelope structs (`DomainEvent`/`IntegrationEvent`/`EventMetadata`) and every driven adapter stay exactly where they are. The flatten is therefore a **namespace collapse of the ports/services/types/validation/models modules only**, not a rewrite.

> **Amended by #1358.** None of those three module names survives. `DomainEvent` and `IntegrationEvent` collapsed into one `Event` struct in ADR-0014, which this line predates. `EventMetadata` is gone too: #1358 retired the `metadata` field it was named for, leaving only a UUID mint (inlined into `Event.new/5`) and a jsonb guard (now `PayloadGuard`, beside `PayloadCodec`). The claim this paragraph was actually making — that `domain/events/` and `adapters/driven/**` keep their shape through the flatten — still holds.

## Decision

Collapse the `Domain.Ports` / `Domain.Services` / `Domain.Types` namespaces; keep each swap behaviour as a **standalone slim behaviour module** at the context root. Modules keep their identity — only their path shortens. (The deeper "inline each `@callback` into its facade" variant was rejected: more edits, more risk, no payoff for a behaviour-preserving refactor.)

Per-seam verdict:

| Current module | Target | Verdict |
|---|---|---|
| `Shared.Domain.Ports.ForPublishingEvents` | `Shared.ForPublishingEvents` | keep behaviour — real swap |
| `Shared.Domain.Ports.ForPublishingIntegrationEvents` | `Shared.ForPublishingIntegrationEvents` | keep behaviour — real swap |
| `Shared.Domain.Ports.ForManagingFeatureFlags` | `Shared.ForManagingFeatureFlags` | keep behaviour — real swap |
| `Shared.Domain.Ports.ForStoringFiles` | `Shared.ForStoringFiles` | keep behaviour — real swap |
| `Shared.Domain.Ports.ForTrackingProcessedEvents` | `Shared.ForTrackingProcessedEvents` | keep behaviour — transactional seam |
| `Shared.Domain.Ports.Driving.ForHandlingEvents` | `Shared.ForHandlingEvents` | keep behaviour — impl'd by 7 contexts |
| `Shared.Domain.Ports.Driving.ForHandlingIntegrationEvents` | `Shared.ForHandlingIntegrationEvents` | keep behaviour — impl'd by 7 contexts |
| `Shared.Domain.Services.CriticalEventDispatcher` | `Shared.CriticalEventDispatcher` | move to root |
| `Shared.Domain.Types.Money` | `Shared.Money` | move to root |
| `Shared.Domain.Types.Pagination` | `Shared.Pagination` | move to root |
| `Shared.Domain.Models.PersistenceSupport` | — | **delete — zero callers (dead)** |
| `Shared.Domain.Validation` | — | **delete — zero callers, no test (dead)** |
| `Shared.Domain.Events.*` | unchanged | stays in `domain/events/` (sanctioned) |
| `Shared.Adapters.Driven.**` | unchanged | stays (sanctioned driven adapters) |

**Config wiring is unchanged.** Adapters are wired by alias (`config :klass_hero, :feature_flags, adapter: FunWithFlagsAdapter`), never by port module path, and the driven adapters do not move. The `config :klass_hero, :shared, for_tracking_processed_events: ProcessedEventRepository` key stays.

## Consequences

- **Five config-selected seams remain legitimate**, not one. The prior CLAUDE.md note framing `for_tracking_processed_events` as the sole residual port key understated it: the four env-swapped adapter behaviours (`event_publisher`, `integration_event_publisher`, `feature_flags`, `storage`) are equally legit DI seams. The docs are corrected to say so, and to distinguish these live swap seams from the deleted aggregate-port ceremony.
- Two dead modules (`PersistenceSupport`, `Validation`) are deleted outright — the flatten is a net simplification, not just a move.
- `domain/{ports,services,types,models}/` directories are removed; only `domain/events/` survives under `shared/domain/`, matching every other context.
- No migration, no schema change, no config-wiring change. The single risk is a rename silently miswiring a swap seam — mitigated by the existing suite plus explicit both-env resolution checks.

## When to revisit

- If a fifth env-swapped adapter is ever added, follow the same rule: a slim behaviour at the context root + a config-selected impl, not a `domain/ports/` directory.
- If a swap behaviour ever collapses to a single impl with no test double, inline its `@callback` into the facade and drop the standalone module — the indirection would then be ceremony.
