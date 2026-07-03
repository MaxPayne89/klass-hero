# Available Skills

The following specialized skills are available for this repository and should be consulted when relevant:

## idiomatic-elixir

Elixir idioms for writing clean, functional, and domain-driven code covering patterns from pattern matching to Phoenix contexts.

**Use when:**

- Writing new Elixir code
- Designing Phoenix applications with bounded contexts (conventional Phoenix)
- Refactoring code
- Implementing bounded contexts
- Leveraging OTP patterns effectively

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

### idiomatic-elixir (project version)

Enhanced version of the global skill with auto-triggering on `.ex`/`.exs` files and modern Elixir 1.17–1.20 patterns (type system, Duration, built-in JSON, parameterized tests).

**Triggers automatically** when working on any Elixir file.

### create-issue

Creates well-formed GitHub issues from findings or hypotheses. Validates against current code, gathers references, drafts using project issue templates.

**Use when:** `/create-issue "description"` or when asked to file/open/create an issue

### test-drive

Test-drives code changes using Playwright and Tidewave MCP. Verifies backend logic, UI flows, responsive design, and edge cases. Includes pre-flight checks, prioritized test ordering, and structured report generation. References auth flows with seed user credentials.

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

## Custom Agents (in `.claude/agents/`)

### architecture-reviewer

Reviews code for conventional-Phoenix convention compliance (post-flatten). Runs 8 checks covering schema-as-struct integrity, no reintroduced ports/DI/Boundary, cross-context-via-facade access, and correct placement of the surviving projection/event/worker/ACL subdirectories.

**Use when:** Architecture review needed during PR review or after structural changes. Spawn as a subagent.

### boundary-checker

Detects semantic cross-context boundary violations (boundaries are convention-only since the `boundary` library was removed). Checks for reaching into another context's internals instead of its root facade, cross-context Repo/schema access, event-handler facade use, event/read-model purity, and ACL adapter correctness. Supports `changed-files` or `full` scan scope.

**Use when:** Deep boundary analysis needed, especially after adding cross-context features. Spawn as a subagent.
