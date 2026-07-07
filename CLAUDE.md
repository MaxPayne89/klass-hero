# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Klass Hero is a platform for afterschool activities, camps, and class trips management, connecting parents, instructors, and administrators.

**Tech Stack:** Elixir 1.20 + Phoenix 1.8 + LiveView 1.1 + PostgreSQL + Tailwind CSS + Oban + Backpex

## Commands

```bash
# Development
mix setup                    # Complete setup (deps, database, seeds, assets)
mix phx.server               # Start dev server (localhost:4000)
iex -S mix phx.server        # Start with interactive console

# Testing
mix test                     # Run all tests
mix test path/to/test.exs    # Run specific file
mix test path/to/test.exs:42 # Run specific test at line
mix test --failed            # Re-run failed tests
mix test.e2e                 # Run end-to-end tests (Wallaby)

# Quality
mix precommit                # Full pre-commit: compile --warnings-as-errors, deps.unlock --unused, format, lint_typography, test
mix credo --strict           # Elixir linting (runs in CI)
mix lint_typography          # Check font/typography usage in templates

# Database
mix ecto.migrate             # Run migrations
mix ecto.reset               # Drop, create, migrate
mix run priv/repo/seeds.exs  # Seed development data
mix test.setup               # Setup Docker test database
mix test.clean               # Clean test database (removes volumes)

# Documentation lookup
mix usage_rules.docs Enum.zip           # Get docs for function/module
mix usage_rules.search_docs "query"     # Search across all packages
```

## Architecture

### Bounded Contexts (conventional Phoenix, post-flatten)

All 7 contexts were flattened from DDD/Ports & Adapters to conventional Phoenix (PRs #986→#1002, `boundary` library removed). Each context under `lib/klass_hero/` now looks like:

```
context.ex                  # Public API — the ONLY module other contexts call
context/
├── <entity>.ex             # Schema-as-struct: ONE module that is the Ecto schema,
│                           #   the struct consumers pattern-match, AND the functional
│                           #   core (validators, state machines). No mappers, no ports.
│                           #   e.g. provider/staff_member.ex, family/child.ex
├── <use_case>.ex           # Command/query modules at the root (e.g. claim_invite.ex)
├── domain/
│   ├── events/             # Domain & integration event structs
│   └── read_models/        # CQRS read-model DTOs (display-optimized, no logic)
└── adapters/
    ├── driven/
    │   ├── projections/     # CQRS projection GenServers (maintain read tables)
    │   ├── persistence/     # Ecto schemas/repos for PROJECTION read tables only
    │   └── acl/             # Cross-context read adapters (anti-corruption layer)
    └── driving/
        ├── events/          # Event handlers (react to other contexts' events)
        └── workers/         # Oban background job workers
```

**Key rule — schema-as-struct:** an entity module is simultaneously the Ecto schema, the struct callers match on, and the functional core. Changesets are the validation gatekeeper at the DB boundary; pure business logic (invitation state machines, `full_name/1`, domain validators returning `{:error, [msg]}` lists) lives in the same file. See `provider/staff_member.ex`'s moduledoc for the canonical explanation.

**What survives in subdirs:** only indirection that earns its place — CQRS projections + read-models, event handlers/workers, and cross-context ACL adapters. Aggregate ports, mappers, and DI wiring were deleted.

**Active contexts:**

- **Accounts** (`accounts/`) - User auth via `phx.gen.auth`, scopes, roles, tokens
- **Family** (`family/`) - Parent profiles, children management, consents, referral codes
- **Provider** (`provider/`) - Provider profiles, staff members, verification documents
- **Program Catalog** (`program_catalog/`) - Program discovery, filtering, pricing, categories
- **Enrollment** (`enrollment/`) - Bookings, fee calculations, subscription tiers
- **Entitlements** (`shared/entitlements.ex`) - Pure domain service for subscription tier authorization (cross-context, no DB)
- **Messaging** (`messaging/`) - Conversations, messages, participants, retention policies
- **Participation** (`participation/`) - Session tracking, check-in/out, attendance rosters
- **Shared** (`shared/`) - Event publishing, projections base macro, interaction/tracing, Ecto helpers
- **Admin** (`admin/queries.ex`) - Backpex admin read queries

See `.claude/rules/domain-architecture.md` for patterns. For context-specific details, read the code under `lib/klass_hero/<context>/` directly — Claude Code explores on-demand.

**Context boundaries:** Not tooling-enforced (`boundary` library removed). Cross-context isolation is a convention — call other contexts only through their root module's public API (e.g. `KlassHero.Family`), never reach into their internals. For cross-context *reads*, use an ACL adapter under `adapters/driven/acl/` or subscribe an event handler to build a local read model — never call another context's Repo/schemas directly.

**CQRS reads:** Read models are maintained by projection GenServers (`adapters/driven/projections/`) that subscribe to events and denormalize into dedicated read tables, exposed as read-model DTOs (`domain/read_models/`). Program Catalog, Messaging, and Provider have these. Build new projections on `KlassHero.Shared.Projection` (base macro) — see `provider/adapters/driven/projections/provider_programs.ex` for the canonical example.

> **Note:** Per-context *aggregate* port DI wiring (`config :klass_hero, :<context>, for_managing_*: Adapter`) is gone — those ports were ceremony (one prod impl). What survives is Shared's genuine env-swapped adapter seams, where a behaviour + config-selected impl is idiomatic Elixir DI, not DDD ceremony: `event_publisher`, `integration_event_publisher`, `feature_flags`, `storage` (each real-vs-test/stub), plus `:shared, for_tracking_processed_events`. Their slim behaviours live at the Shared root (`KlassHero.Shared.ForStoringFiles` etc.), not in a `domain/ports/` tree. Do not add new *aggregate* port-wiring — call collaborators directly or via an ACL module — but a new genuinely swappable external adapter may follow the Shared seam pattern.

### Event System (Two-Tier)

- **Domain events** (non-critical): Published via PubSub (`PubSubEventPublisher`). Used for real-time UI updates and non-essential side effects.
- **Integration events** (critical): Routed through `critical_event_handlers` registry in `config/config.exs` to Oban-backed handlers for durable, at-least-once delivery. Used for cross-context workflows.

Registry shape — topic strings keyed `integration:<context>:<event>` map to a list of `{Handler, :function}` tuples (fan-out supported):

```elixir
# config/config.exs
config :klass_hero, :critical_event_handlers, %{
  "integration:accounts:user_registered" => [
    {FamilyEventHandler, :handle_event},
    {ProviderEventHandler, :handle_event}
  ],
  "integration:enrollment:invite_claimed" => [
    {InviteClaimedHandler, :handle_event}
  ]
}
```

When adding a new integration event: define the event struct, publish it from the use case, then register the handler(s) here. Handlers live under their own context's `adapters/driving/events/`.

### Feature Flags

Uses `FunWithFlags` for runtime feature toggling. Adapter is configurable per environment (`StubFeatureFlagsAdapter` in test).

### Authentication & Role-Based Routing

Uses Phoenix `phx.gen.auth` with scope-based pattern:

- **Always use `@current_scope`** (not `@current_user`)
- Access user via `@current_scope.user`

Router defines 5 `live_session` scopes with role-based access:

- `:public` - Optional auth (home, programs, about, contact, legal pages)
- `:authenticated` - Auth required (dashboard, settings, booking, messages)
- `:require_provider` - Provider role (`/provider/*` routes)
- `:require_parent` - Parent role (`/parent/*` routes)
- `:require_authenticated_user` - Auth pages (user settings, email confirmation)

### Web Layer Patterns

**Components** organized by domain in `lib/klass_hero_web/components/` (ui, composite, program, booking, provider, participation, messaging, review, theme).

**Presenters** in `lib/klass_hero_web/presenters/` transform domain models for templates.

**Internationalization:** Gettext with English (`en`, source/fallback) and German (`de`) in `priv/gettext/`. New `gettext(...)`/`dgettext(...)` calls must ship with a German translation in the **same PR** (or, for an intentional English passthrough, an entry with a reason in `priv/gettext/de/untranslated_allowlist.exs`). Enforced by `mix lint_translations` (in `precommit` and CI), which fails on stale `.pot` templates, empty `de` `msgstr`, or `fuzzy` entries. Run `mix gettext.extract && mix gettext.merge priv/gettext` after adding strings, then translate the new `de` entries.

## MCP Integration

**Tidewave MCP** (ALWAYS prefer over bash for Phoenix work): `project_eval`, `get_docs`, `execute_sql_query`, `get_logs`, `get_source_location`, `get_ecto_schemas`.

If Tidewave unavailable: Alert user immediately - indicates Phoenix server not running or MCP issue.

**Chrome DevTools MCP** for UI testing: test LiveView interactions, verify mobile-responsive designs (via `emulate`), run Lighthouse a11y audits.

## Project Constraints

- **Mobile-first design** - Design for mobile before desktop
- **Warnings as errors** - All warnings must be resolved before commit
- **Tests before commit** - If tests fail, fix before proceeding — never commit with failing tests
- **No Claude references** - Never mention Claude in commits, PRs, or issues
- Merchant codes: set under `sumup.merchant.code` attribute

## Git Conventions

Use semantic commit messages: `type: description`

Types: `feat`, `fix`, `chore`, `docs`, `refactor`, `test`, `ci`, `perf`

Examples: `feat: add staff invitation flow`, `fix: correct enrollment fee calculation`, `ci: split test workflow into parallel jobs`

**Merge strategy:** Squash-merge all PRs onto `main`; always rebase the branch onto `origin/main` before opening or updating a PR. See `.claude/rules/workflow.md#merge-strategy`.

## CI Pipeline

These checks run automatically on every PR — don't manually recheck what CI catches:

| Check | Catches |
|---|---|
| `mix compile --warnings-as-errors` | Unused vars/imports, deprecations |
| `mix format --check-formatted` | Formatting issues |
| `mix credo --min-priority=high` | Style violations, code smells |
| `mix lint_typography` | Font/typography usage violations |
| `mix test` | Functional regressions (full suite with PostgreSQL) |
| Sobelow | Common Phoenix security vulnerabilities |
| `mix deps.audit` | Known dependency vulnerabilities |
| Conventional commits | PR title format validation |

## Ecto Anti-Patterns

- **Never** use `Multi.run` for side-effects — `Multi.run` is for operations that need to be part of the transaction
- **Never** read data outside a `Multi` transaction and use it inside — fetch within the Multi to avoid race conditions

## PR Review Comments

When addressing PR review comments, follow this workflow:

1. Fetch all comments on the PR
2. Triage: classify as actionable fix, style nit, or dismissible bot noise
3. Confirm with user before dismissing any comments
4. Apply fixes for actionable items
5. Run `mix precommit`, then commit and push

## Detailed Rules

Topic-specific guidelines live in `.claude/rules/` and are auto-loaded into context. **Do not duplicate those rules here.**

<!-- usage-rules-start -->
<!-- igniter-start -->
## igniter usage
_A code generation and project patching framework_

[igniter usage rules](deps/igniter/usage-rules.md)
<!-- igniter-end -->
<!-- usage_rules-start -->
## usage_rules usage
_A config-driven dev tool for Elixir projects to manage AGENTS.md files and agent skills from dependencies_

[usage_rules usage rules](deps/usage_rules/usage-rules.md)
<!-- usage_rules-end -->
<!-- usage_rules:elixir-start -->
## usage_rules:elixir usage
[usage_rules:elixir usage rules](deps/usage_rules/usage-rules/elixir.md)
<!-- usage_rules:elixir-end -->
<!-- usage_rules:otp-start -->
## usage_rules:otp usage
[usage_rules:otp usage rules](deps/usage_rules/usage-rules/otp.md)
<!-- usage_rules:otp-end -->
<!-- phoenix:ecto-start -->
## phoenix:ecto usage
[phoenix:ecto usage rules](deps/phoenix/usage-rules/ecto.md)
<!-- phoenix:ecto-end -->
<!-- phoenix:elixir-start -->
## phoenix:elixir usage
[phoenix:elixir usage rules](deps/phoenix/usage-rules/elixir.md)
<!-- phoenix:elixir-end -->
<!-- phoenix:html-start -->
## phoenix:html usage
[phoenix:html usage rules](deps/phoenix/usage-rules/html.md)
<!-- phoenix:html-end -->
<!-- phoenix:liveview-start -->
## phoenix:liveview usage
[phoenix:liveview usage rules](deps/phoenix/usage-rules/liveview.md)
<!-- phoenix:liveview-end -->
<!-- phoenix:phoenix-start -->
## phoenix:phoenix usage
[phoenix:phoenix usage rules](deps/phoenix/usage-rules/phoenix.md)
<!-- phoenix:phoenix-end -->
<!-- usage-rules-end -->

## Landing the Plane (Session Completion)

Work is NOT complete until `git push` succeeds. Session-end work lands via PR from a feature branch; direct pushes to `main` are blocked by the ruleset.

```bash
git fetch origin
git rebase origin/main
git push --force-with-lease   # only on your own feature branch
git status                     # MUST show "up to date with origin"
```

- File issues for follow-up work before closing the session
- Run `mix precommit` if code changed; do not push with failing checks
- Force-push only with `--force-with-lease`, only on your own feature branch, never on `main`
- If push fails, resolve and retry — do not leave work stranded locally

## Agent skills

### Issue tracker

Issues live in the `MaxPayne89/klass-hero` GitHub repo, managed via the `gh` CLI. See `docs/agents/issue-tracker.md`.

### Triage labels

Five canonical roles use their default label strings (`needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`); `wontfix` already exists in the repo. See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: one `CONTEXT.md` + `docs/adr/` at the repo root. See `docs/agents/domain.md`.
