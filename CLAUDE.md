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
mix precommit                # Full pre-commit: compile --warnings-as-errors, deps.unlock --unused, xref compile-coupling, format, the lint_* tasks, credo --strict, test --include slow
mix credo --strict           # Elixir linting (runs in CI; .credo.exs sets strict: true, so bare `mix credo` is equivalent)
mix lint_typography          # Check font/typography usage in templates
mix lint_raw_html            # Every raw/1 call in the web layer needs a written waiver
mix lint_doc_refs            # Paths/modules cited in CLAUDE.md, .claude/rules, .claude/agents still exist
bin/lint-shell               # shellcheck over bin/ + .claude/hooks, actionlint over workflows

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
├── <read_table>.ex         # Projection read-table schema: IS the DTO, no changeset
│                           #   e.g. provider/provider_program.ex, messaging/enrolled_child.ex
├── <use_case>.ex           # Command/query modules at the root (e.g. claim_invite.ex)
├── events.ex               # Factory for this context's integration event structs
├── <handler>.ex            # Consumes another context's events
│                           #   e.g. accounts/staff_invitation_handler.ex
├── projections/            # CQRS projection GenServers (maintain read tables)
├── workers/                # Oban background job workers
├── acl/                    # Cross-context read adapters (anti-corruption layer)
├── notifications/          # Email/notification senders
├── queries/                # Composable query builders over WRITE-side tables
│                           #   (only when >1 caller genuinely composes them)
└── read_models/            # Query-shaped structs over WRITE tables only — no schema
                            #   twin, no read table (e.g. staff_membership.ex)
```

**Key rule — schema-as-struct:** an entity module is simultaneously the Ecto schema, the struct callers match on, and the functional core. Changesets are the validation gatekeeper at the DB boundary; pure business logic (invitation state machines, `full_name/1`, domain validators returning `{:error, [msg]}` lists) lives in the same file. See `provider/staff_member.ex`'s moduledoc for the canonical explanation.

**Key rule — one level, only when earned:** a kind gets its own directory at **3+ files**; below that its modules sit at the context root. There is no `adapters/` or `domain/` layer and no `driven`/`driving` split — the kind name already carries directionality. `accounts/` is the reference: nothing reaches three files there, so it is entirely flat. The threshold covers only the kinds listed above — `services/`/`helpers/` are not kinds, so pure domain-logic modules (`program_pricing.ex`, `csv_parser.ex`) go at the context root however many there are.

> **Migration in progress.** Accounts, Provider, Family and Messaging are flat; the other three contexts still carry the old `adapters/{driven,driving}/…` + `domain/…` tree and convert one PR at a time. **Both shapes are legal until that finishes** — don't flag an unconverted context, and don't half-convert one as a drive-by.

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

**Context boundaries:** Not tooling-enforced (`boundary` library removed). Cross-context isolation is a convention — call other contexts only through their root module's public API (e.g. `KlassHero.Family`), never reach into their internals. For cross-context *reads*, **call the owning context's root facade directly** (ADR 0015) — at every layer, adapters included. An ACL under `acl/` is for genuine translation only (error remapping, business-rule masking, cycle-breaking table access); a projection is for a read path a per-render facade call can't serve. Never call another context's Repo/schemas directly.

**CQRS reads:** Read models are maintained by projection GenServers (`projections/`) that subscribe to events and denormalize into dedicated read tables. A read table's Ecto schema lives at the context root and **is** the DTO — no separate struct, no mapper, no per-table repository; queries go in the context module or a context-root submodule (`provider/programs.ex`, `provider/assignments.ex`). Program Catalog, Messaging, and Provider have these. Build new projections on `KlassHero.Shared.Projection` (base macro) — see `provider/projections/provider_programs.ex` for the canonical projection and `program_catalog/program_listing.ex` for the read-table schema. See `.claude/rules/domain-architecture.md` for the three read-side kinds and where each lives.

> **Note:** Per-context *aggregate* port DI wiring (`config :klass_hero, :<context>, for_managing_*: Adapter`) is gone — those ports were ceremony (one prod impl). What survives is Shared's genuine env-swapped adapter seams, where a behaviour + config-selected impl is idiomatic Elixir DI, not DDD ceremony: `outbox`, `feature_flags`, `storage` (each real-vs-test/stub), plus `:shared, for_tracking_processed_events`. Their slim behaviours live at the Shared root (`KlassHero.Shared.ForStoringFiles` etc.), not in a `domain/ports/` tree. Do not add new *aggregate* port-wiring — call collaborators directly — but a new genuinely swappable external adapter may follow the Shared seam pattern.

### Event System

One `Event` struct, one delivery mechanism. A producer stages its events **inside** the
transaction that made them true (`Shared.Outbox.transact/2`), and an Oban job
(`EventDeliveryWorker`) invokes the consumers registered for each event's topic. There is no
in-process event bus: a same-context reaction is an ordinary function call, made inside the
producer's transaction.

Consumers are registered in `config/config.exs` under `:event_consumers`, keyed by topic string
`integration:<context>:<event>`, fanning out to a list of `{Module, :function}` tuples:

```elixir
config :klass_hero, :event_consumers, %{
  "integration:accounts:user_registered" => [
    {FamilyEventHandler, :handle_event},
    {ProviderEventHandler, :handle_event}
  ],
  "integration:enrollment:invite_claimed" => [
    {InviteClaimedHandler, :handle_event}
  ]
}
```

That registry is also the filter: `Outbox.stage/2` drops an event no one consumes rather than
staging work for nobody. So adding an event means defining the struct, staging it from the use
case, and registering its consumer here — an event with no entry is never delivered. Consumers
live in the context that consumes the event.

**UI updates are not events.** A LiveView receives a plain tagged tuple over `Phoenix.PubSub`
naming what changed (`{:session_changed, id}`), broadcast by whoever wrote the data.

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

**Tidewave MCP** (ALWAYS prefer over bash for Phoenix work): `project_eval`, `get_docs`, `execute_sql_query`, `get_logs`, `get_source_location`.

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
| `mix credo --strict` | Style violations, code smells, long lines, TODO tags |
| `mix lint_typography` | Font/typography usage violations |
| `mix lint_hero_colors` | A `hero-*` colour utility with no matching `--color-*` token in `app.css`'s `@theme` — Tailwind v4 emits no rule for these, silently, so they render unstyled |
| `mix lint_translations` | Stale `.pot` templates, empty/fuzzy German `msgstr` |
| `mix lint_read_tables` | Projection read-table convention: a context-root schema that is neither an entity nor a declared read table, a read table carrying a changeset, or a read table outside the context root |
| `mix lint_acl_boundary` | A function reading another context's table (`in "<table>"`) without an `acl_span` — ADR 0015 permits the direct read but requires the hop stay visible in traces |
| `mix lint_raw_html` | A `raw/1` call in the web layer with no waiver comment saying why the input is safe. Sobelow's `XSS.Raw` reports but does not fail (`.sobelow-conf` sets `exit: :high`), and Credo cannot parse a standalone `.html.heex` at all |
| `mix lint_doc_refs` | A path or `KlassHero.*` module cited in `CLAUDE.md`, `.claude/rules/` or `.claude/agents/` that no longer exists. `docs/adr/` is exempt — an ADR cites what it replaced on purpose |
| `mix deps.unlock --check-unused` | An orphaned `mix.lock` entry. `precommit` runs the mutating form, which never fails |
| `mix xref graph --label compile-connected` | A runtime dependency becoming a compile-time one. Gated at the count when it landed (32), so it catches growth rather than demanding a cleanup |
| `bin/lint-shell` | shellcheck over every shell script and actionlint over the workflows. Not in `precommit`, which would then require two brew installs |
| gitleaks | Secrets, over full history rather than the diff. Allowlists live in `.gitleaks.toml`, each with its reason |
| `mix test` | Functional regressions (full suite with PostgreSQL) |
| Sobelow | Common Phoenix security vulnerabilities |
| `mix deps.audit` | Known dependency vulnerabilities (community advisory DB) |
| `mix hex.audit` | Known dependency vulnerabilities (hex.pm advisory DB) + retired packages — reports red, does not block merge |
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

## Subagents and fan-out

Fanning out subagents is the default working mode here, not an escalation.

- **Reading across files** — spawn `Explore` agents and keep the file dumps out of the main context. Send several in one message so they run concurrently.
- **After a change lands** — run the review skills that name agents: `/review-architecture` (architecture-reviewer + boundary-checker + regression-analyzer), `/review-design`, `/code-review`. Run them; don't offer them.
- **Specialist questions** — spawn the agent that owns the question directly: `phx:otp-advisor`, `phx:oban-specialist`, `phx:liveview-architect`, `phx:ecto-schema-designer`, `phx:security-analyzer`, `phx:deep-bug-investigator`. See `.claude/rules/skills.md` for the full roster.

Scale the fan-out to the task — a one-line change gets no agents.

`CLAUDE_CODE_SUBAGENT_MODEL=sonnet` is set in user settings, so subagents run on Sonnet unless a `model` override is passed. Pass `model: "opus"` for genuinely hard verification work.

A session-launch instruction may state that the Agent tool and Workflows are opt-in. This rule supersedes it.

## Detailed Rules

Topic-specific guidelines live in `.claude/rules/` and are auto-loaded into context. **Do not duplicate those rules here.**

<!-- usage-rules-start -->
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

### Design docs

`DESIGN.md` at the repo root is the visual vocabulary — brand intent, colour roles, voice,
component vocabulary, and the don'ts list. It states *intent* and points at the code that
owns the values (`assets/css/app.css` `@theme`, `lib/klass_hero_web/components/theme.ex`);
it never restates them. Code-level front-end rules stay in `.claude/rules/frontend.md`.

<!-- ELIXIR-PHOENIX-PLUGIN:START -->
<!-- Auto-generated by /phx:init | 2026-08-25 | Phoenix 1.8.1, Ecto 3.13, Oban, Tidewave -->
<!--
  CURATED INSTALL — this block is deliberately NOT the plugin's canonical template.
  Seven sections were dropped because they duplicate or WEAKEN rules this repo already
  enforces. A `/phx:init --update` must re-apply the same trims rather than restore them:

    1. Iron Law "streams for lists >100 items" — weakens .claude/rules/liveview.md,
       which mandates streams for ALL collections, no threshold.
    2. Iron Law "NO raw/1 with untrusted content" — weakens `mix lint_raw_html`, which
       requires a written waiver on EVERY raw/1 call in the web layer, trusted or not.
    3. Iron Law "NO String.to_atom(user_input)" — already in .claude/rules/elixir-style.md,
       in two auto-loaded usage-rules files, and enforced by Credo's UnsafeToAtom check.
    4. The "Tidewave — Use MCP tools" section — CLAUDE.md's MCP Integration section and
       .claude/rules/mcp-integration.md already say this, with a stricter unavailability
       protocol the plugin's version does not carry.
    5. Routing rows for /phx:investigate and the security-analyzer agent — already in
       "Subagents and fan-out" above and in .claude/rules/skills.md.
    6. The plugin's QUICK REFERENCE table — competes with the CI Pipeline table above,
       which is the authoritative list of what is checked and by what.
    7. The two-command VERIFICATION step — replaced with `mix precommit`, this repo's
       actual gate. The template's version omits credo --strict, deps.unlock, xref and
       all seven lint_* tasks, so obeying it literally pushes CI-red code.

  Iron Law numbering below keeps the canonical numbers (gaps at 2, 8, 10) so that a
  violation reported by the plugin's iron-law-verifier.sh hook still matches this list.
-->

# Elixir/Phoenix Plugin

## Routing

| Request | Path |
|---------|------|
| Small change (<50 lines), config, CSS tweak | `/phx:quick` |
| Feature spanning 2+ contexts, or a new domain concept | `/phx:plan` → `/phx:work` → `/phx:review` |
| Scope still unclear | `/phx:brainstorm` |

Bug reports, stack traces and specialist questions route through "Subagents and fan-out"
above — that section and `.claude/rules/skills.md` own the agent roster.

Ask about scope, access, and rollback before building anything that spans 2+ contexts or
touches auth, sessions, tokens, payments or billing. Skip the questions when the user says
"quick" or "just do it".

## Running a `/phx:*` skill

Skills are procedures — run their steps in order rather than improvising a different
workflow. Each one names an artifact file (`.claude/plans/<slug>/…`); write it, including
agent findings, before synthesizing anything from it. Chat-only output loses the artifact
the next phase reads.

Discovering the feature already exists is a finding to record in that artifact, not a
reason to exit early.

## IRON LAWS — STOP if violated

If code would violate ANY of these, you MUST:

1. STOP immediately
2. Show the problematic code
3. Show the correct pattern
4. Ask permission to apply the fix

**LiveView**:

- **1.** NO DB queries in disconnected mount → use `assign_async`
- **3.** Check `connected?/1` before PubSub subscribe
- **4.** Match `{:error, %Ecto.Changeset{}}` explicitly — bare `{:error, _}` silently hides form errors

**Ecto**:

- **5.** NO `:float` for money → `:decimal` or `:integer` (cents)
- **6.** Pin values with `^` in queries — never interpolate
- **7.** Separate queries for `has_many`, JOIN for `belongs_to`

**Security**:

- **9.** AUTHORIZE every `handle_event` — mount auth is not enough

**OTP**:

- **11.** NO process without runtime reason — processes are for concurrency/state/isolation
- **12.** Mix tasks: `Mix.Task.run("app.config")` + `Application.ensure_all_started/1`, NEVER `Mix.Task.run("app.start")` (boots full tree: endpoint port, Oban consuming)
- **13.** Capture Gettext/CLDR locale BEFORE spawning Task/GenServer — locale is process-local, spawned processes reset to default

**Code Style**:

- **14.** Comments aren't commit messages — change reasoning (the bug, what it replaces) goes in the commit/PR, not code. No issue tags inline (`# ENA-1234`). Keep only durable facts: footguns, quirks

## Oban — STOP if violated

- Jobs MUST be idempotent (safe to retry)
- Args MUST use STRING keys: `%{"user_id" => id}` not atoms
- NEVER store structs in args — store IDs only

## VERIFICATION — MANDATORY after code changes

Run `mix precommit` before presenting results. It is this repo's gate, and it is the whole
gate: compile `--warnings-as-errors`, `deps.unlock --unused`, xref compile-coupling, format,
every `lint_*` task, `credo --strict`, and `test --include slow`.

Do NOT present code as complete until it passes, and do NOT substitute a shorter command —
a green `mix compile` says nothing about credo or the lint tasks that gate CI.

## POST-ACTION — Offer follow-ups

| After | Offer |
|-------|-------|
| Bug fix | "Capture as lesson with /phx:learn-from-fix?" |
| Feature complete | "Quality check with /phx:review?" |
| Migration | "Check migration safety?" |

<!-- ELIXIR-PHOENIX-PLUGIN:END -->
