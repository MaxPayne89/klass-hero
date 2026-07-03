---
name: exunit-testing
description: Use when writing, modifying, or reviewing tests for Elixir/Phoenix code in this project — ExUnit unit/integration tests, property-based tests with stream_data, or Phoenix LiveView tests. Triggers on `.exs` test files, `mix test` failures, modules ending in `Test`, `use ExUnit.Case`, `use ExUnitProperties`, `Phoenix.LiveViewTest`, `live/3`, `render_submit`, `assert_patch`, ConnCase, DataCase, Mox, factories, sandbox setup, or when adding tests for new entities, schemas, context functions, or LiveViews. Distilled from "Testing Elixir" by Leopardi & Matthias.
---

# ExUnit Testing

> **TL;DR:** Define a clear black box. Group by behavioural axis with `describe`. Move shared data to module attributes / `setup`. Use list comprehensions for tabular cases. Reach for `stream_data` properties when invariants exist; combine with example tests for known corners. Drive LiveView tests from explicit DOM IDs, not raw HTML or text matches. Never write a flaky test — controlled time, controlled doubles, controlled state.

## When to Use

Apply this skill any time you write or change Elixir test code in this repo. It covers three pillars; pick the one(s) that fit:

| Situation | Pillar | Reference file |
|---|---|---|
| Pure function, schema validator, value object, domain service | **ExUnit core** | `exunit-core.md` |
| Function with clear invariants (encode/decode, sort, partition, math, parsers) | **stream_data** | `stream-data.md` |
| Phoenix LiveView page or component | **LiveView** | `liveview-testing.md` |
| Cross-context call, external service, time-dependent code | **ExUnit core** (Mox section) | `exunit-core.md` |
| Phoenix controller / JSON API endpoint | **ExUnit core** (Phoenix section) | `exunit-core.md` |

**Most real tests use multiple pillars together** — e.g. a domain service test uses ExUnit core plus a stream_data property; a LiveView test uses LiveView patterns plus Mox stubs.

## Decision Tree: Which Test Style?

```
Is the function pure (same input → same output, no side effects)?
├── Yes ──▶ Are there invariants that hold for ALL valid inputs?
│           ├── Yes ──▶ stream_data property + 1-3 example tests for corners
│           └── No  ──▶ Tabular ExUnit (list comprehension over fixtures)
└── No  ──▶ Does it call cross-context / external code?
            ├── Yes ──▶ Mox-backed double on the port behaviour + assertions on observable effects
            └── No  ──▶ ExUnit with setup block; controlled time, sandbox state
```

## Core Principles

These are the non-obvious craft moves the book emphasises. Agents miss them by default.

1. **Define the black box explicitly.** A unit test draws a box around the code under test. Pure, well-tested dependencies can live *inside* the box (no isolation needed). Anything stateful / cross-context lives *outside* (use a double).

2. **Group by behavioural axis.** One `describe` per behaviour facet ("error cases", "tier surcharges", "boundary values"). ExUnit only allows one nesting level — that's intentional. Don't fight it.

3. **Tabular data → list comprehensions.** When you'd write 5 nearly-identical tests, use `for {input, expected} <- @table` inside a single `test`, with a custom failure message that interpolates the iteration's variable. See `exunit-core.md#parametric-tests`.

4. **Module attributes for shared fixture data, `setup` for shared values.** Don't repeat `10_000` fifteen times. Don't DRY between test code and code-under-test — copy the tier list / weather IDs into a module attribute at the top of the test file.

5. **Boundary testing has a name.** When code does comparisons (`<`, `>=`, time windows, off-by-one), test exactly one unit on either side of the boundary. Name the test "exactly at the boundary" / "one before" / "one after".

6. **Essential vs incidental data.** Incidental data (a city name passed through to a stub) → randomize freely; signals to the reader "this value doesn't matter". Essential data (the weather IDs that change branch behaviour) → enumerate explicitly. See `exunit-core.md#randomization`.

7. **Properties are not enough.** A property like "`String.contains?(a <> b, a)`" passes if `contains?` always returns `true`. Pair properties with example tests that pin known correct outputs.

8. **Test the side effects, not just the return value.** Controller / use-case tests assert on the DB row, the email sent, the event published, AND the return shape. In error cases, assert the side effect did NOT happen.

9. **Drive LiveView tests off DOM IDs.** Every form, button, and key region in a LiveView should have an explicit `id=`. Tests use `has_element?(view, "#my-id")` — never raw HTML matching, never text-content matching for structural assertions.

10. **No flaky tests.** Inject system time as a function param defaulting to `&DateTime.utc_now/0`. Use Mox for unowned externals. Use Ecto sandbox properly (shared mode iff `async: false`). When a test fails intermittently, the cause is uncontrolled state — fix the test, don't retry.

## Quick Reference

### File / module conventions
- Test file mirrors the module path: `lib/x/y.ex` → `test/x/y_test.exs`
- Module name ends in `Test`: `defmodule X.YTest do`
- `use ExUnit.Case, async: true` by default; drop `async: true` only if you need shared sandbox / global Mox
- One `describe` per function-and-arity (`describe "calculate/3 - tier surcharges"`)

### ExUnit life cycle (Appendix 2)
- `setup_all` — once per file, in its own process. State here lives across all tests.
- `setup` — per test, in the test process. Returns a map merged into the test context.
- Test body — runs in its own spawned process.
- `on_exit` — runs in a *separate* process after the test exits, even on failure. Use for cleanup that must happen.

### Setup composition
```elixir
setup [:create_organization, :with_admin, :with_authenticated_user]
# Each helper takes context, returns updated context.
```

### Common assertions
| Want to assert | Use |
|---|---|
| Exact equality | `assert x == y` |
| Pattern shape | `assert {:ok, %User{name: name}} = result` (binds `name`) |
| Pattern shape, no bind | `assert match?({:ok, _}, result)` |
| Negation of pattern | `refute match?({:error, _}, result)` *(NOT `refute {:error, _} = result`)* |
| Empty list | `assert Enum.empty?(list)` *(NOT `refute list`)* |
| Process received message | `assert_received {:event, _}` (already in mailbox) / `assert_receive` (waits) |
| Custom failure message | `assert x == y, "context: #{inspect(ctx)}"` |
| Raises | `assert_raise ArgumentError, fn -> ... end` |
| Logged output | `import ExUnit.CaptureLog`; `log = capture_log(fn -> ... end); assert log =~ "..."` |

### Reproducing failures
- Test order is randomized. The seed is printed: `Randomized with seed 654321`.
- Replay with `mix test --seed 654321`.
- Re-run only failures: `mix test --failed`.
- Run a specific line: `mix test test/foo_test.exs:42`.

## Companion files (read on demand)

- `exunit-core.md` — anatomy, organization, test doubles & Mox, Phoenix controller tests, randomization rules, sandbox setup
- `stream-data.md` — generators, `gen all` / `bind/2`, properties, shrinking, design patterns (oracle / circular / smoke), known pitfalls
- `liveview-testing.md` — `Phoenix.LiveViewTest` patterns, flash & navigation assertions, form testing, mocking cross-context calls, common mistakes

## Common Mistakes (from baseline observations)

| Mistake | Fix |
|---|---|
| Repeating literal fixture values across tests | Hoist to `@module_attribute` at top of file |
| 5 near-identical tests for tabular data | Single `test` with `for {input, expected} <- @table do` and custom failure message |
| Skipping property-based testing on pure math/parsing functions | Add `property` for invariants; combine with example tests |
| Using `Enum.map`/`Stream.map` to build a generator | Use `StreamData.map/2` — preserves shrinking |
| `result =~ "Invite sent!" or render(view) =~ ...` | Use `Phoenix.Flash.get(view.flash || conn.flash, :info)` (LV 1.1) |
| Asserting on raw HTML strings in LiveView tests | Use `has_element?(view, "#dom-id")` against IDs you set explicitly in the template |
| Calling real cross-context functions in a LiveView test | Stub the port via Mox; assert the use case was invoked correctly |
| Adding `async: false` "to be safe" | Default to `async: true`. Drop async only if you need `Sandbox.mode :shared` or global Mox |
| Pinning args inside `Mox.expect` anonymous fn | Pin throws `FunctionClauseError` on mismatch — assert each arg individually for clearer failures |
| Manual sleeps to wait for async work | Use `Task.await/2`, `assert_receive`, or LV's `assert_patch` — never `Process.sleep` in tests |

## Red Flags — STOP and Reconsider

- A test that occasionally fails (timing, ordering, network) → uncontrolled dependency
- Test sets up data the code-under-test will then fetch (race condition risk) → set up inside the use case / `Multi`
- Test mocks the same module it imports directly (no port boundary) → introduce a port behaviour first
- Helper function that conditionally branches based on test inputs → split into multiple helpers, one per case
- Test body longer than 30 lines → either the code-under-test does too much, or the test combines unrelated assertions
- "Just retry" / `Process.sleep(100)` → root-cause the timing instead

## See also

- Project conventions: `.claude/rules/testing.md`, `.claude/rules/liveview.md`, `.claude/rules/database.md`
- Tidewave MCP for live REPL exploration during test design (`.claude/rules/mcp-integration.md`)
- The book itself: `testing-elixir_P1.0.pdf` (Leopardi & Matthias, Pragmatic Bookshelf, 2021)
