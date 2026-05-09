# stream_data — Property-Based Testing in Elixir

Deep reference for `stream_data`. Read this when SKILL.md sends you here.

> **Mental model:** A property is an *invariant* about your code that holds for **all valid inputs**. Property-based tests generate random inputs, check the invariant, and on failure **shrink** the failing input to the simplest case that still triggers the bug. This is qualitatively different from example-based testing — you're describing *what's true*, not *what happens*.

## When to Reach for stream_data

| Sign | Use property-based |
|---|---|
| Function takes a wide range of valid inputs (lists, strings, numbers, structs) | ✅ |
| There's an obvious invariant (round-trip, ordering, conservation, partition) | ✅ |
| You'd write 20+ example-based tests just to feel confident | ✅ |
| Encoding / decoding pairs (JSON, base64, custom serializers) | ✅ — circular pattern |
| You're rewriting an existing implementation | ✅ — oracle pattern |
| Function is a black-box pipeline you don't fully understand | ✅ — smoke pattern |

| Sign | Stick with example-based |
|---|---|
| One specific value matters (e.g. `parse_response/1` for weather id 500) | ✅ |
| Behaviour depends on highly-structured input (UI state, complex schemas) | ✅ |
| You want to lock down a specific corner case | ✅ |
| It's hard to express the invariant in a one-liner | ✅ |

**Best practice:** properties + example tests, side by side. Properties cover the invariant space; examples lock down known correct outputs (defending against the "always returns true" trap below).

## Setup

```elixir
# mix.exs
{:stream_data, "~> 1.0", only: [:dev, :test]}

# In a test file:
defmodule MyTest do
  use ExUnit.Case, async: true
  use ExUnitProperties           # adds `property` and `check all` macros

  property "..." do
    check all x <- generator() do
      assert ...
    end
  end
end
```

## Generators

Generators are infinite streams of random data with **shrinking metadata baked in**. That's the critical difference between a `stream_data` generator and a plain `Stream` — when a property fails, stream_data simplifies the failing input.

### Built-in generators

| Generator | Produces |
|---|---|
| `StreamData.integer/0` | Integers, biased toward small values |
| `StreamData.integer/1` (e.g. `integer(1..100)`) | Integers in range |
| `StreamData.positive_integer/0` | Integers `>= 1` |
| `StreamData.boolean/0` | `true` / `false` |
| `StreamData.binary/0`, `binary/1` | Random binaries |
| `StreamData.string/2` (e.g. `string(:alphanumeric)`) | Random strings of a charset |
| `StreamData.atom/1` (`:alphanumeric` / `:alias`) | Random atoms |
| `StreamData.float/0`, `float/1` | Floats |
| `StreamData.term/0` | Any Elixir term — useful for "fails predictably on garbage" |
| `StreamData.constant/1` | Always emits the same value (turns a value into a generator) |

When inside `check all`, all of these are imported via `use ExUnitProperties`, so you can write `integer()` directly.

### Combinators

| Combinator | Purpose |
|---|---|
| `list_of(generator, opts)` | Lists. `opts: [min_length: n, max_length: n, length: n]` |
| `tuple({g1, g2, ...})` | Fixed-arity tuples |
| `member_of([a, b, c])` | Pick one of these literal values |
| `one_of([g1, g2, g3])` | Pick one of these *generators* (different shapes) |
| `frequency([{3, g1}, {1, g2}])` | Weighted choice between generators |
| `map(generator, fn x -> ... end)` | Transform each generated value (preserves shrinking) |
| `bind(generator, fn x -> new_generator end)` | Generate a value, then use it to build the next generator (composition) |
| `filter(generator, fn x -> bool end)` | Reject values that don't pass; use sparingly (slow on tight filters) |

**Critical pitfall:** Use `StreamData.map/2`, NOT `Stream.map/2` (or `Enum.map/2`). They look identical but `Stream.map` strips the shrinking metadata — your generator becomes a useless raw stream that won't shrink on failure.

```elixir
# ✅ GOOD — keeps shrinking
non_negative = StreamData.map(StreamData.integer(), &abs/1)

# ❌ BAD — silently breaks shrinking
non_negative = Stream.map(StreamData.integer(), &abs/1)
```

### `bind/2` — the composition workhorse

When the next generator depends on a previously-generated value, use `bind/2`. It's `flat_map` for generators.

```elixir
# Generate an email: random domain from a list, then alphanumeric username, then concat.
random_email_generator =
  StreamData.bind(StreamData.member_of(["gmail.com", "yahoo.com", "icloud.com"]), fn domain ->
    StreamData.map(StreamData.string(:alphanumeric, min_length: 1), fn user ->
      "#{user}@#{domain}"
    end)
  end)
```

### `gen all` — readable composition

`gen all` provides `for`-comprehension syntax for building generators. Same expressive power as nested `bind/2`, but flatter.

```elixir
email_generator =
  gen all username <- string(:alphanumeric, min_length: 1),
          domain   <- member_of(["gmail.com", "yahoo.com", "icloud.com"]) do
    "#{username}@#{domain}"
  end
```

`gen all` supports the same clauses as `check all`: bind clauses (`<-`), assignment (`=`), and filter expressions (`x != []`).

### Generation size

stream_data passes a **generation size** parameter (a non-negative integer, growing over time) into each generator. Bigger size → bigger / more complex output. Three knobs:

```elixir
StreamData.resize(gen, 50)                 # Always use size 50, ignoring growth
StreamData.scale(gen, fn size -> div(size, 2) end)   # Modify size dynamically
StreamData.sized(fn size -> ... end)       # Build a generator that knows its size
```

Use `scale` to slow down growth for deeply-nested generators (e.g. recursive trees).

## Writing Properties

```elixir
property "name describing the invariant" do
  check all x <- generator(),
            y <- another_generator(),
            x != [],                  # filter clause
            scaled = some_pure_op(y)  # binding for clarity
            do
    assert invariant_holds?(x, y, scaled)
  end
end
```

By default, `check all` runs **100 times** per property. Override:

```elixir
check all x <- slow_generator(), max_runs: 10 do
  ...
end
```

## Shrinking — the killer feature

When a property fails, stream_data **shrinks** the failing input toward the simplest case that still triggers the failure. For a sort-correctness property, instead of getting `[42, -17, 9, 3, -8, 1]`, you get `[1, 0]`.

How to leverage shrinking:

- **Always use `StreamData.map/2`, never `Stream.map`.** (See above.)
- **Compose with `bind/2` or `gen all`.** Composition preserves shrinking.
- **Don't filter aggressively.** Heavy filters (`x when rare_condition?(x)`) reduce shrink quality and slow generation. Generate the right shape directly when possible.
- Shrinking is **heuristic**. It doesn't always find the absolute minimum — by default it tries 100 simplifications then stops.

### Reproducing a shrunk failure

When a property fails, the output prints the seed and the shrunk input. Replay with:

```bash
mix test --seed 654321 test/path/foo_test.exs
```

Combine with `IO.inspect` calls inside the `check all` body to trace generation.

## Properties Are NOT Enough

A property like:

```elixir
property "concatenated string contains both halves" do
  check all left <- string(), right <- string() do
    assert String.contains?(left <> right, left)
    assert String.contains?(left <> right, right)
  end
end
```

…holds for the obviously-broken `def contains?(_, _), do: true`. **Always pair properties with example-based tests** that pin known correct outputs:

```elixir
test "String.contains?/2 known inputs" do
  assert String.contains?("foobar", "foo")
  assert String.contains?("foobar", "bar")
  refute String.contains?("foobar", "baz")
end
```

Properties verify *invariants*; examples verify *correctness*. Both are needed.

## Design Patterns for Properties

The four classic patterns. Recognise the shape, write the property.

### 1. Circular Code (round-trip / encode-decode)

When you have an encoder and decoder, the round-trip should return the original. JSON, base64, parsers, serializers all fit.

```elixir
property "encode |> decode is the identity" do
  check all term <- term() do
    assert term == term |> JSON.encode!() |> JSON.decode!()
  end
end
```

If you're writing only one half (decoder), pair it with the inverse and test the round-trip.

### 2. Oracle Model (cross-checking against a known impl)

When rewriting code (in a different language, more performant, simpler), use the existing implementation as the **oracle**.

```elixir
property "MyQuickSort matches :lists.sort/1" do
  check all list <- list_of(term()) do
    assert MyQuickSort.sort(list) == :lists.sort(list)
  end
end
```

The oracle doesn't have to be production code — even a slow but obviously-correct reference implementation works.

### 3. Smoke Testing (broad inputs, weak assertion)

For complex systems where exact behaviour is hard to specify, assert *only that nothing catastrophic happens*. Useful for HTTP APIs, parsers, anything that should "either succeed or fail predictably".

```elixir
property "API returns 200, 400, or 404 for any well-formed request" do
  check all method <- member_of([:get, :post, :put, :delete]),
            path   <- path_generator(),
            body   <- binary() do
    response = send_request(method, path, body)
    assert response.status in [200, 400, 404]
  end
end
```

### 4. Invariant Testing (the most common)

State an invariant the function maintains, regardless of input.

```elixir
# Sort: output length == input length.
# Sort: output is sorted.
# Sort: output is a permutation of input.
property "Enum.sort/1 invariants" do
  check all list <- list_of(integer()) do
    sorted = Enum.sort(list)
    assert length(sorted) == length(list)
    assert sorted == Enum.sort(sorted)             # idempotent
    assert Enum.sort(sorted) == Enum.sort(list)    # canonical form
  end
end
```

Combine multiple invariants in a single `property` when they share generators — fewer test runs, more coverage per generation.

## Avoiding Reimplementation

A common trap: to verify the property, you implement most of the logic again inside the test. The test then validates "my reimplementation matches my implementation" — adds little.

Two escape hatches:

1. **Find a different invariant.** Instead of "the sorted output equals the manually-sorted version", use "the output is sorted AND has the same length AND is a permutation of input". None of those reimplements `sort`.
2. **Write an oracle that's correct but slow.** A naive `O(n²)` selection sort is trivially correct; use it as the oracle for your fast `O(n log n)` version.

If you can't find either, property-based testing may not be the right tool for that function — fall back to careful example-based tests.

## Stateful Property-Based Testing

`stream_data` does **not** natively support stateful PBT (yet). For stateful systems (databases, caches, GenServers), you need either:

- **PropEr** (`propcheck` Elixir wrapper) — the established stateful PBT library
- A handwritten state-machine test (acceptable for small systems)

The general pattern when you do reach for it:

1. Generate a random sequence of commands (`{:set, key, value}`, `{:get, key}`, `{:delete, key}`).
2. Apply each command both to the real system and to a simple model.
3. After each step, assert the model and the system agree.

Stateful PBT excels at finding race conditions, ordering bugs, and integration corner cases that no example test would think to write.

## Common Mistakes

| Mistake | Why it bites | Fix |
|---|---|---|
| `Stream.map(gen, fn)` instead of `StreamData.map/2` | Strips shrinking — failure shows the raw random input, not the minimal one | Use `StreamData.map/2` |
| Property only — no example tests | An always-true implementation passes vacuous properties | Pair every property with 2-3 example tests for known outputs |
| Heavy `filter` on a tight predicate | Slow generation, bad shrinking | Generate the right shape via `bind/2` or `gen all` |
| Property reimplements the code-under-test | Test verifies your reimplementation matches the impl, not correctness | Find a different invariant or use a slow oracle |
| `max_runs: 1000` for slow properties | Tests take too long, devs disable them | Drop `max_runs` for slow ones, run them in a nightly job |
| Generators inside the property body | Defeats the point — re-generates every iteration | Define generators as named module functions or at the top of the file |
| Forgetting to pair with `use ExUnit.Case` | `property` macro errors on undefined `test` | Always have BOTH `use ExUnit.Case` AND `use ExUnitProperties` |

## Quick Reference

### Anatomy

```elixir
property "human-readable invariant" do
  check all input  <- generator(),
            other  <- another_generator(),
            input != [],                # filter
            shape  = transform(input),  # binding
            max_runs: 50                # opts (only at end of clauses)
            do
    assert invariant(input, other, shape)
  end
end
```

### gen all (build a generator)

```elixir
my_generator =
  gen all a <- integer(),
          b <- list_of(integer()),
          length(b) > 0 do
    {a, b}
  end
```

### Common generator recipes

```elixir
# Non-negative integer
non_negative = StreamData.map(StreamData.integer(), &abs/1)

# Email (alphanumeric @ fixed-domain)
email = gen all u <- string(:alphanumeric, min_length: 1),
                d <- member_of(["gmail.com", "yahoo.com"]),
              do: "#{u}@#{d}"

# Map with fixed keys, generated values
person = gen all name <- string(:printable, min_length: 1),
                 age  <- integer(0..120),
              do: %{name: name, age: age}

# One of N shapes (ok / error tuples)
result = StreamData.one_of([
  StreamData.bind(integer(), &StreamData.constant({:ok, &1})),
  StreamData.constant({:error, :bad_input})
])

# Existing struct, randomized fields
weather = gen all dt   <- integer(1_000_000_000..2_000_000_000),
                  rain <- boolean(),
              do: %Weather{datetime: DateTime.from_unix!(dt), rain?: rain}
```

## See also

- `exunit-core.md` — life cycle, organization, doubles
- `liveview-testing.md` — LiveView-specific patterns
- Hex docs: <https://hexdocs.pm/stream_data>
- Book chapter: 7 (Property-Based Testing) + Appendix 1 (When To Randomize)
