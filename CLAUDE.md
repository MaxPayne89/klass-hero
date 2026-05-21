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

### Bounded Contexts (DDD + Ports & Adapters)

Each context under `lib/klass_hero/` follows this internal structure:

```
context/
├── domain/
│   ├── models/          # Pure Elixir structs (entities, value objects)
│   ├── ports/           # Driven port contracts (flat = driven by convention)
│   │   └── driving/     # Driving port contracts (only in shared context)
│   ├── services/        # Domain logic
│   └── events/          # Domain events
├── application/
│   └── use_cases/       # Orchestration layer
└── adapters/
    ├── driven/          # Outbound adapters (persistence, ACL, notifications, infra)
    │   └── persistence/ # Ecto schemas, repos, mappers
    └── driving/         # Inbound adapters (event handlers, workers)
        ├── events/      # Domain & integration event handlers
        └── workers/     # Oban background job workers
```

**Active contexts:**

- **Accounts** (`accounts/`) - User auth via `phx.gen.auth`, scopes, roles, tokens
- **Family** (`family/`) - Parent profiles, children management, consents, referral codes
- **Provider** (`provider/`) - Provider profiles, staff members, verification documents
- **Program Catalog** (`program_catalog/`) - Program discovery, filtering, pricing, categories
- **Enrollment** (`enrollment/`) - Bookings, fee calculations, subscription tiers
- **Entitlements** (`shared/entitlements.ex`) - Pure domain service for subscription tier authorization (cross-context, no DB)
- **Messaging** (`messaging/`) - Conversations, messages, participants, retention policies
- **Participation** (`participation/`) - Session tracking, check-in/out, attendance rosters
- **Shared** (`shared/`) - Event publishing, Ecto helpers, pagination, domain events

See `.claude/rules/domain-architecture.md` for patterns. For context-specific details, read the code under `lib/klass_hero/<context>/` directly — Claude Code explores on-demand.

**Boundary enforcement:** Each context's root module (`lib/klass_hero/<context>.ex`) declares `use Boundary, deps: [...], exports: [...]`. Compile-time violations surface via `mix compile --warnings-as-errors`. There is no separate `boundary.ex`.

**CQRS direction:** New use cases go under `application/commands/` or `application/queries/`. New ports separate read contracts (`ForQuerying*`, `ForListing*`, `ForResolving*`) from write contracts (`ForStoring*`, `ForCreating*`, `ForUpdating*`). Existing `ForManaging*` ports will be split incrementally.

### Dependency Injection (Port Wiring)

Each bounded context's port-to-adapter bindings are configured in `config/config.exs` using a naming convention that mirrors the port behaviour names:

```elixir
# config/config.exs — each context gets a key with port → adapter mappings
config :klass_hero, :enrollment,
  for_managing_enrollments: EnrollmentRepository,
  for_resolving_participant_details: ParticipantDetailsACL,
  for_sending_invite_emails: InviteEmailNotifier

# config/test.exs can override with test doubles
```

When adding a new port: define the behaviour in `domain/ports/`, implement the adapter in `adapters/driven/`, then wire it in `config/config.exs` under the context's key.

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

**Internationalization:** Gettext with English (`en`) and German (`de`) in `priv/gettext/`.

## MCP Integration

**Tidewave MCP** (ALWAYS prefer over bash for Phoenix work): `project_eval`, `get_docs`, `execute_sql_query`, `get_logs`, `get_source_location`, `get_ecto_schemas`.

If Tidewave unavailable: Alert user immediately - indicates Phoenix server not running or MCP issue.

**Playwright MCP** for UI testing: test LiveView interactions, verify mobile-responsive designs.

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
| `mix compile --warnings-as-errors` | Unused vars/imports, deprecations, Boundary violations |
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

## graphify

This project has a knowledge graph at graphify-out/ with god nodes, community structure, and cross-file relationships.

Rules:
- For codebase questions, first run `graphify query "<question>"` when graphify-out/graph.json exists. Use `graphify path "<A>" "<B>"` for relationships and `graphify explain "<concept>"` for focused concepts. These return a scoped subgraph, usually much smaller than GRAPH_REPORT.md or raw grep output.
- If graphify-out/wiki/index.md exists, use it for broad navigation instead of raw source browsing.
- Read graphify-out/GRAPH_REPORT.md only for broad architecture review or when query/path/explain do not surface enough context.
- After modifying code, run `graphify update .` to keep the graph current (AST-only, no API cost).
