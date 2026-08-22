# Available Skills

The following specialized skills are available for this repository and should be consulted when relevant:

## elixir-ecto-patterns

Phoenix Ecto patterns for clean, maintainable data access covering production-ready patterns.

**Use when:**

- Building Phoenix applications with database-backed features
- Designing clean context boundaries
- Optimizing database queries
- Implementing transactions
- Refactoring existing Ecto code

## phoenix-pubsub

Battle-tested Phoenix PubSub patterns for building real-time backends, from single-node fan-out to multi-region handoffs.

**Use when:**

- Building real-time features (live updates, notifications, collaboration)
- Scaling WebSocket connections
- Implementing pub/sub messaging patterns

## inversion

A mental model for solving complex problems by thinking in reverse - identify failure modes first, then design solutions to avoid them.

**Use when:**

- Making critical architectural decisions
- Conducting premortems
- Reviewing code for potential failure modes
- Planning security features

## second-order

A mental model for making better decisions by thinking beyond immediate effects - consider the consequences of consequences before acting.

**Use when:**

- Evaluating major technical decisions
- Assessing long-term impact of architectural choices
- Considering tradeoffs between short-term speed and long-term maintainability

## Project-Bespoke Skills (in `.claude/skills/`)

### triage-qa-discussion

Reads a Daily QA GitHub Discussion by number, triages Carried-Forward and New Code Review findings, and systematically addresses confirmed issues.

**Use when:** `/triage-qa-discussion <discussion-number>`

### build-elixir

User-invoked umbrella router for TDD-first, design-heavy Elixir/Phoenix development. Sequences `/design-an-interface` (surface rival designs — user picks), `/tdd` (red→green), `exunit-testing` (fold tests lean via tabular for-comprehensions + property tests), auto-attaching idiom/Iron-Law/LiveView guidance, then verify. Generic Elixir idioms live in `.claude/rules/elixir-style.md` + `domain-architecture.md` and the `phx` plugin, not a skill — see [Elixir/Phoenix Plugin (`phx`)](#elixirphoenix-plugin-phx) below for what it adds and who wins on overlap.

**Use when:** `/build-elixir <what you're building>`

### create-issue

Creates well-formed GitHub issues from findings or hypotheses. Validates against current code, gathers references, drafts using project issue templates.

**Use when:** `/create-issue "description"` or when asked to file/open/create an issue

### test-drive

Test-drives code changes using Chrome DevTools and Tidewave MCP. Verifies backend logic, UI flows, responsive design, and edge cases. Includes pre-flight checks, prioritized test ordering, and structured report generation. References auth flows with seed user credentials.

**Use when:** `/test-drive [branch|unstaged|<issue-number>]` or when asked to "test-drive", "verify changes", or "QA this"

### gen-migration

Scaffolds a database-backed entity following conventional Phoenix (schema-as-struct): a migration and one entity module (Ecto schema + struct + functional core) at the context root, plus a test. Updates the context facade with CRUD. No domain model, mapper, repository, port, or DI wiring.

**Use when:** `/gen-migration <context> <entity> [field:type ...]`

### address-pr-comments

Fetches, triages, and addresses PR review comments for the current branch. Classifies each as actionable, nit, question, or dismissible.

**Use when:** `/address-pr-comments` or when asked to "handle review feedback", "fix PR comments"

### dep-upgrade

Upgrades Hex dependencies with semver classification, changelog review, and test verification. Handles single-package or all-packages mode with confirmation gates.

**Use when:** `/dep-upgrade [package-name|--all]` or when asked to "upgrade deps", "update dependencies", "check outdated"

### dream

Performs memory consolidation — a reflective pass that synthesizes recent learnings into durable, well-organized memories. Supports full 4-phase consolidation (orient, gather, consolidate, prune) or a lighter prune-only mode.

**Use when:** `/dream [consolidate|prune]` or when asked to "consolidate memories", "clean up memories", or at the end of a productive session

### review-architecture

Runs a comprehensive 21-check review of conventional-Phoenix conventions by spawning the `architecture-reviewer` (8 structural checks), `boundary-checker` (5 semantic checks), and `regression-analyzer` (8 behaviour checks) agents in parallel, scoped to changed files. Consolidates findings into a unified report.

**Use when:** `/review-architecture` or when reviewing a PR, checking architecture before merge, or after modifying bounded context code

### analyze-prod-issue

Diagnoses a production issue end-to-end: Honeycomb for the error shape, the prod DB `error_tracker` tables (via `bin/prod-db`) for the who + why, schema cross-referencing to scope impact honestly, then an optional PII-scrubbed issue. Read-only. Needs prod DB access set up (`docs/runbooks/prod-db-access.md`).

**Use when:** `/analyze-prod-issue "<symptom>"`

### prod-watch

Proactive counterpart to `analyze-prod-issue`. Sweeps the prod `error_tracker` (via `bin/prod-db`) + Honeycomb for issues newly active since a stored watermark, dedups on error_tracker's native `fingerprint`, diagnoses survivors through `/analyze-prod-issue`, then **auto-files** a `bug` + `priority:high` issue per real user-blocker and notifies. Runs unattended on a 12h launchd schedule (`docs/runbooks/prod-watch-scheduling.md`) or by hand.

**Use when:** `/prod-watch`

## Custom Agents (in `.claude/agents/`)

### architecture-reviewer

Reviews code for conventional-Phoenix convention compliance (post-flatten). Runs 8 checks covering schema-as-struct integrity, no reintroduced ports/DI/Boundary, cross-context-via-facade access, and correct placement of the surviving projection/event/worker/ACL subdirectories.

**Use when:** Architecture review needed during PR review or after structural changes. Spawn as a subagent.

### boundary-checker

Detects semantic cross-context boundary violations (boundaries are convention-only since the `boundary` library was removed). Checks for reaching into another context's internals instead of its root facade, cross-context Repo/schema access, event-handler facade use, event/read-model purity, and ACL adapter correctness. Supports `changed-files` or `full` scan scope.

**Use when:** Deep boundary analysis needed, especially after adding cross-context features. Spawn as a subagent.

## Elixir/Phoenix Plugin (`phx`)

Installed as `elixir-phoenix` (marketplace `oliver-kriska`, v3.0.1); invoked as `/phx:*` because its `plugin.json` sets `"name": "phx"`. Ships **51 skills and 25 agents**. The sibling `ecto@oliver-kriska` and `lv@oliver-kriska` plugins are thin aliases onto the same codebase (`/ecto:*`, `/lv:*`) — no separate capability.

### Reach for these — no project equivalent exists

| Command / agent | What it does that nothing here does |
|---|---|
| `/phx:investigate` | Structured root-cause on a stack trace. `--parallel` fans `deep-bug-investigator` across 4 tracks (repro / root cause / impact / fix strategy). |
| `/phx:trace`, `phx:call-tracer`, `phx:xref-analyzer` | Call trees from entry points and module-dependency maps via `mix xref` — run before a signature change or a refactor. |
| `/phx:n1-check`, `/phx:perf`, `/phx:assigns-audit` | N+1 detection, Ecto/GenServer bottlenecks, LiveView assign bloat and missing `temporary_assigns`/streams. |
| `/phx:boundaries` | `mix xref` coupling analysis — **structural**, where `boundary-checker` is semantic. Different instruments; run both. |
| `/phx:oban` + `phx:oban-specialist` | Worker idempotency, queue config, cron, string-keyed args. Five contexts here have `workers/` and no Oban review skill. |
| `/phx:verify` + `phx:verification-runner` | Project-aware verify loop that reads `mix.exs` to discover credo/dialyzer/sobelow aliases. |
| `/phx:techdebt`, `/phx:audit` | Duplicate detection and whole-project health sweeps. |
| `/phx:compound`, `/phx:recall` | Capture a solved bug as a searchable solution doc; recall past fixes. Complements the `remember` memory store. |
| `/phx:watch-pr` | Background-watches a PR for new bot/human comments and CI results. |
| `phx:requirements-verifier` | Cross-checks an implementation against the originating GitHub issue — pairs with `/read-and-assess-issue`. |
| `phx:otp-advisor`, `phx:liveview-architect`, `phx:ecto-schema-designer` | Design-stage specialists. Spawn directly rather than reasoning solo. |

### Precedence where they overlap

**Project rules win on project-specific conventions; phx wins on generic Elixir/OTP.**

| phx | project | Who wins |
|---|---|---|
| `phx:phoenix-contexts` | `domain-architecture.md` | **Project** — this repo is post-flatten conventional Phoenix with schema-as-struct, not generic contexts. |
| `phx:testing` | `exunit-testing` | **Project** — both auto-attach to `test/**/*_test.exs`; ours knows the `async: false` projection rule. |
| `phx:ecto-patterns` | `database.md`, `/gen-migration` | **Project** for schema/migration shape; phx for generic changeset/Multi idiom. |
| `phx:liveview-patterns` | `liveview.md` | **Project.** |
| `phx:security` | `authentication.md` | **Project** on scopes/`phx.gen.auth`; phx for generic OWASP sweeps. |
| `phx:pr-review` | `/address-pr-comments` | **Project** for triage; phx `watch-pr` still useful for the background watch. |
| `phx:deps-audit`/`update`/`vet` | `/dep-upgrade` | **Project** for routine bumps; `phx:deps-audit` adds supply-chain checks (bidi chars, compile-time exec, typosquats) ours lacks. |
| `phx:review` | `/review-architecture` | **Both** — phx checks generic Elixir/OTP/security/test quality and Iron Laws; ours checks structural conventions. |
| `phx:elixir-idioms` | `elixir-style.md` | **Both** — different altitude: OTP process design vs syntax-level gotchas. |

### Already active — don't re-invent

- **Auto-attaching skills** load themselves on matching files (`user-invocable: false` + `paths:` globs): `ecto-patterns`, `liveview-patterns`, `testing`, `security`, `phoenix-contexts`, `elixir-idioms`, `oban`, `ash-framework`.
- **`SubagentStart` → `inject-iron-laws.sh`** puts the Iron Laws into *every* subagent spawned — one more reason fan-out is cheap here.
- **`UserPromptSubmit` → `route-intent.sh`** suggests `/phx:pr-review`, or `/phx:investigate` on a stack-trace paste or Tidewave page context. Silent on any prompt starting with `/`; fires at most once per category per session.
- **`PostToolUseFailure` → `error-critic.sh` / `elixir-failure-hints.sh`** fire on failing `mix` commands.
- **`PostToolUse` → `format-elixir.sh`** is check-only by design (never writes, avoiding a "file modified since read" race). The project's `.claude/hooks/format.sh` is the one that actually formats, and also covers `.heex`. Both stay.
