---
name: build-elixir
description: >-
  Deliberate TDD-first, design-heavy workflow for building an Elixir/Phoenix
  change end-to-end — surface rival designs, pick one, drive red→green, keep the
  test suite lean. Invoke with: /build-elixir <what you're building>
disable-model-invocation: true
---

# Build Elixir

**Type:** Rigid workflow. Follow the phases in order. This skill routes over other
skills — it names them, it does not restate them. Each phase ends on a checkable
completion criterion; do not advance until it is met.

The spine is the red→green **loop**, entered only *after* a design **gate** the
human owns. Leading words used throughout: **seam** (the interface under change),
**gate** (the human design decision), **red** (the failing test that drives a
cycle), **fold** (collapsing many tests into one).

## Phase 1 — Orient the seam

Read `.claude/rules/domain-architecture.md` and any `CONTEXT.md` for the area, so
your vocabulary matches the project's domain language. Then name, in writing, the
**seam** under change using `/codebase-design` vocabulary: what is the *module*,
what is its *interface* (every fact a caller must know), where does the *seam*
sit, is there a real *adapter* or a hypothetical one.

**Done when:** the seam and its interface are written down and confirmed with the
user.

## Phase 2 — Design gate (mandatory, human-owned)

Run `/design-an-interface` to generate **≥2–3 radically different** designs for the
seam from Phase 1. This gate is never skipped for a non-trivial change, and the
**user makes the final call** — no implementation code is written before the pick.

Surface the designs like this:

1. **Present a comparison table** — one row per design, columns: *design name*,
   *depth* (behaviour hidden behind the interface), *locality* (where change/bugs
   concentrate), *seam placement*, *testability*. Keep each cell to a phrase.
2. **Below the table, one short paragraph per design** — its core idea and the
   single sharpest trade-off (what it buys, what it costs).
3. **Call out a recommended pick first, with one sentence of why** — then present
   the rest neutrally. A recommendation, not a nudge; the reasoning must be visible
   so the user can disagree with it.
4. **Hand the choice over via `AskUserQuestion`** — each design an option, the
   recommended one first labelled `(Recommended)`, each with a `preview` sketching
   its interface. The user may also pick a synthesis or reject all and re-run
   `/design-an-interface` with new constraints.
5. **Hard stop.** Write no implementation code until the user has answered. A clear
   recommendation does not authorize proceeding — the pick is theirs to make.

**Done when:** the user has explicitly picked one design (or a synthesis), and the
chosen seam + interface are restated for the record.

## Phase 3 — Plan (conditional)

Only for **large, multi-surface** features (new context, several LiveViews, a
migration + projection + worker): run `/phx:plan` — it spawns research agents by
feature type, checks Iron Laws, and writes a checkbox plan. For a single-surface
change, **skip this** and go straight to the loop.

**Done when:** either a plan exists, or you've judged the change small enough to
skip and said so.

## Phase 4 — Red→green loop

`/tdd` drives. First agree the **seams under test** with the user (no test at an
unconfirmed seam). Then cycle in vertical slices: one failing test (**red**) →
the minimal code to pass it → repeat, each test a tracer bullet shaped by what the
last cycle taught. Refactoring is **not** part of the loop — it belongs to Phase 6.

**Done when:** the chosen design is implemented and every slice's test is green.

## Phase 5 — Fold the tests

`/exunit-testing`. Keep the suite lean without losing coverage:

- **Fold** near-identical example tests into a single tabular `test` with a
  `for {input, expected} <- @table do` comprehension and a custom failure message.
- Reach for `stream_data` **property tests** on pure functions with invariants
  (Circular / Oracle / Smoke / Invariant patterns) — always paired with 1–3
  example tests pinning known-correct outputs.
- For genuinely per-case named tests, use the `unquote/1` generation variant, or
  Elixir 1.18's native `parameterize:` option on `use ExUnit.Case`.

**Done when:** no cluster of near-duplicate tests remains that a table or property
would express better, and coverage is unchanged.

## Phase 6 — UI branch (only if LiveView/components touched)

The plugin's `liveview-patterns` auto-attaches on `*_live.ex` / `*_component.ex`.
Obey `.claude/rules/liveview.md` (streams for collections, `<.link navigate/patch>`,
`to_form/2` + `<.input>`, no LiveComponents without cause) and
`.claude/rules/frontend.md` (mobile-first, `Theme.typography(:variant)`). Test with
`exunit-testing`'s `liveview-testing.md` conventions (assert on element IDs, never
raw text).

**Done when:** UI tests are green and the LiveView rules are satisfied.

## Phase 7 — Idioms & Iron Laws (adhere, don't restate)

These load automatically — do not copy them into your reasoning, just comply:

- The `inject-iron-laws.sh` hook feeds the Elixir/Phoenix Iron Laws into every
  subagent.
- The plugin's `elixir-idioms`, `ecto-patterns`, `security`, `oban`,
  `phoenix-contexts` auto-attach by context.
- `.claude/rules/elixir-style.md` and `domain-architecture.md` are always loaded
  (generic idioms + the project's DDD modeling idioms live there).

## Phase 8 — Verify

Run `mix precommit` (or `/phx:verify` for a tool-discovering loop). Then a review
pass: `/phx:review` (spawns `iron-law-judge`) for general changes, or
`/review-architecture` for bounded-context / structural changes.

**Done when:** precommit is green and the review pass reports no blockers.

## Rules

- The **gate** (Phase 2) is never skipped for a non-trivial change, and the **user
  picks** the design — never auto-select.
- Never restate the Iron Laws or idioms; name their source and comply.
- Never refactor inside the red→green loop; that is Phase 6/8 work.
- Route to the named skills; do not improvise a manual substitute for `/tdd`,
  `/design-an-interface`, or `exunit-testing` — composing them is the whole point.
