# ExUnit Core — Patterns and Reference

Deep reference for ExUnit testing in this project. Read this when SKILL.md points you here.

## Anatomy of a Test (4 Stages)

Every test, no matter how complex, is comprised of **setup, exercise, verify, teardown**. Naming the stage helps you spot when a test does too much.

| Stage | When | Notes |
|---|---|---|
| **Setup** | Prepare data, fixtures, processes, sandbox | Often empty for pure-function tests. Use `setup` block if shared. |
| **Exercise** | Call the code under test | Always present. One call per test ideally. |
| **Verify** | Assert behaviour | Always present. Multiple assertions OK if they describe one outcome. |
| **Teardown** | Restore state | Often automatic (Ecto sandbox, on_exit). Use `on_exit` if you change global state. |

A unit test that needs to repeat the exercise+verify pair is testing too much — split it.

## Defining the Black Box

A unit test draws a **black box** around the code under test. Two valid widths:

1. **Narrow box** (single function, isolate everything else)
   - Pros: failure points to one line.
   - Cons: more setup; more doubles.
2. **Wide box** (function + its purely-functional, well-tested dependencies)
   - Pros: less setup, more realistic data flow.
   - Cons: when something breaks, locate the failure across modules.

**Heuristic:** include a dependency in the box if it is *purely functional* and *separately well-tested*. Exclude anything stateful, time-dependent, or cross-context.

```elixir
# WIDE BOX: parse_response/1 (under test) calls Weather.imminent_rain?/2 (pure, well-tested).
# Both inside the box. Test only stubs the API HTTP call.
```

## Organising Tests

### Module structure

```elixir
defmodule KlassHero.X.YTest do
  use ExUnit.Case, async: true     # async unless you need shared sandbox / global Mox

  alias KlassHero.X.Y                 # alias the module under test
  alias KlassHero.X.Z                 # alias struct types you assert against

  # Module attributes for shared FIXTURE data — never DRY between test and code-under-test
  @rain_ids [500, 501, 502, 503, 504, 511, 520, 521, 522, 531]
  @drizzle_ids [300, 301, 302, 310, 311, 312, 313, 314, 321]

  describe "function_name/arity" do
    setup do
      # Per-test setup. Returns a map; merged into context.
      %{base_value: 10_000}
    end

    test "describes one observable behaviour", %{base_value: base} do
      assert {:ok, _} = Y.function_name(base)
    end
  end
end
```

### `describe` rules

- **One level only.** ExUnit forbids nested `describe` blocks intentionally — it forces you to choose one logical grouping.
- **Group by function-and-arity** for unit tests: `describe "calculate/3 - tier surcharges"`.
- **Group by HTTP action+path** for controller tests: `describe "PUT /api/users/:id"`.
- Add a sub-grouping suffix if a function has many behavioural facets: `"calculate/3 - error cases"`, `"calculate/3 - boundary values"`.

### Setup composition

Setup helpers are functions taking and returning a context map. They can be piped via the list form:

```elixir
setup [:create_organization, :with_admin, :with_authenticated_user]

# Each helper:
defp with_authenticated_user(context) do
  user = User.create!(%{name: "Test User"})
  authed = TestHelper.authenticate(user)
  Map.put(context, :authenticated_user, authed)
end
```

This eliminates the need for nested `describe` blocks and keeps setup logic close to the test file.

### `setup_all` vs `setup` vs `on_exit`

| Macro | Runs | Process | Use for |
|---|---|---|---|
| `setup_all` | Once per test case (file) | Dedicated `setup_all` process | Read fixture file from disk, compile expensive data once |
| `setup` | Before each test | The test's own process | Create per-test fixtures, request connection, pin Mox stubs |
| `on_exit` | After each test exits | A fresh teardown process | Cleanup that MUST happen even if the test crashes |

**Watch out:** `on_exit` runs in a different process than the test, so it can't reference test-process state directly. Capture what you need in a closure when registering.

## Parametric Tests (List Comprehensions)

When you'd write 5 nearly-identical tests with different inputs, fold them into a single `test` with a `for` loop. ExUnit treats each iteration as a separate assertion; failures report the iteration's variables.

### Tabular case (preferred for fixed input/output pairs)

```elixir
@tier_table [
  {:starter,       10_000, 10_000},   # {tier, base, expected}
  {:professional,  10_000, 11_000},
  {:business_plus, 10_000, 12_500}
]

test "applies the right surcharge per tier" do
  for {tier, base, expected} <- @tier_table do
    assert {:ok, ^expected} = FeeCalculator.calculate(base, tier, 0),
           "tier #{tier} (base=#{base}) should produce #{expected}"
  end
end
```

The custom failure message is critical — without it, you can't tell *which* iteration failed.

### Generated case (test name per iteration)

When you want each iteration to be its own named test (better in CI output), generate the tests at compile time with `unquote/1`:

```elixir
for {condition, ids} <- [{"thunderstorm", @thunderstorm_ids},
                         {"drizzle",      @drizzle_ids},
                         {"rain",         @rain_ids}] do
  test "recognises #{condition} as a rainy condition" do
    for id <- unquote(ids) do
      assert {:ok, [%Weather{rain?: true}]} =
               ResponseParser.parse_response(%{"list" => [%{"dt" => 0, "weather" => [%{"id" => id}]}]}),
             "Expected weather id #{unquote(id)} (#{unquote(condition)}) to be a rain condition"
    end
  end
end
```

`unquote/1` is the only metaprogramming you'll typically need in test code.

## Pure Functions and Refactoring Toward Them

The simplest code to test is a pure function — same input, same output, no side effects. When a function both calls a dependency AND manipulates the result, **extract the manipulation into a pure helper**, then test the helper exhaustively. The original function shrinks to coordination logic with one or two integration tests.

```elixir
# BEFORE: hard to test — couples HTTP call with parsing logic.
def rain?(city) do
  with {:ok, response} <- WeatherAPI.get_forecast(city) do
    parse_response(response)        # private — locked away
    |> imminent_rain?()
  end
end

# AFTER: parse_response/1 is now public and tested with stream_data + examples.
# rain?/1 has one happy + one error integration test.
```

## Test Doubles

Three flavours, in increasing power:

| Type | What | Use when |
|---|---|---|
| **Fake** | Hand-written module that mimics interface | One-off, simple stand-in (e.g. `FakeWeatherAPI`) |
| **Stub** | Replaces a function on demand, no assertions | You want predictable values; don't care how often called |
| **Mock** | Stub + assertion that it was called N times with X args | The interaction itself is part of the contract |

In Elixir, all three are best built with **Mox** against a **behaviour**. Define the contract once; all doubles conform.

### Defining a port behaviour

```elixir
defmodule KlassHero.WeatherAPI.Behaviour do
  @callback get_forecast(city :: String.t()) :: {:ok, term()} | {:error, term()}
end

defmodule KlassHero.WeatherAPI do
  @behaviour KlassHero.WeatherAPI.Behaviour
  def get_forecast(city), do: # ... real impl
end
```

The `@behaviour` annotation triggers a compile-time warning if the module is missing a callback — your safety net when the contract evolves.

### Wiring Mox

```elixir
# test/test_helper.exs (or test/support/mocks.ex compiled via elixirc_paths)
Mox.defmock(KlassHero.WeatherAPIMock, for: KlassHero.WeatherAPI.Behaviour)

# config/test.exs
config :klass_hero, :weather_api_module, KlassHero.WeatherAPIMock

# config/config.exs (default to real)
config :klass_hero, :weather_api_module, KlassHero.WeatherAPI
```

Code under test reads the module from app env:

```elixir
defp weather_api, do: Application.get_env(:klass_hero, :weather_api_module, WeatherAPI)
```

### `stub/3` vs `expect/4`

```elixir
# Stub — predictable return, no call assertions, any number of calls.
Mox.stub(WeatherAPIMock, :get_forecast, fn _city -> {:ok, fake_response()} end)

# Expect — asserts exactly N calls (default 1) with optional arg assertions.
Mox.expect(WeatherAPIMock, :get_forecast, 1, fn city ->
  assert city == "Berlin"           # individual assertions, NOT pinned in fn head
  {:ok, fake_response()}
end)

# verify_on_exit! in setup hooks ensures expectations are checked at test end.
setup :verify_on_exit!
```

**Don't pin args in the function head.** A pinned mismatch raises `FunctionClauseError` with no detail. Use individual `assert` calls inside the body — they print the actual value.

### Wrapping Mox in named helpers

When a test needs the same Mox setup repeatedly, wrap it:

```elixir
defp expect_email_to(expected_email) do
  Mox.expect(HttpClientMock, :request, fn :post, url, _headers, body, _opts ->
    assert url == "https://api.sendgrid.com/v3/mail/send"
    decoded = Jason.decode!(body)
    assert get_in(decoded, ["personalizations", Access.at(0), "to", Access.at(0), "email"]) ==
             expected_email
    {:ok, %HTTPoison.Response{status_code: 200, body: "{}"}}
  end)
end
```

The named helper makes the test read at the right level of abstraction.

### `stub_with/2` for "no-op default, override per test"

```elixir
# Default: pretend everything works.
defmodule NoOpWeatherAPI do
  @behaviour WeatherAPI.Behaviour
  def get_forecast(_), do: {:ok, %{"list" => []}}
end

# In ConnCase setup:
setup :verify_on_exit!
setup do
  Mox.stub_with(WeatherAPIMock, NoOpWeatherAPI)
  :ok
end

# In the one test that cares about how the API is used:
test "uses real interaction" do
  Mox.expect(WeatherAPIMock, :get_forecast, fn city -> ... end)
  ...
end
```

### Cross-process Mox: `set_mox_global`

If the code under test calls the mock from a Task / GenServer / Oban worker (a different process), Mox refuses by default. Two options:

```elixir
# OPTION A (per-test): allow a specific PID
Mox.allow(WeatherAPIMock, self(), other_pid)

# OPTION B (per-test-case): global mode — any process can call. FORCES async: false.
setup :set_mox_global
setup :verify_on_exit!
```

Use global only when needed; you lose async parallelism.

## Dependency Injection Without a Mock

For a single time-related parameter, inject a default value directly:

```elixir
@spec imminent_rain?([Weather.t()], DateTime.t()) :: boolean()
def imminent_rain?(weather_data, now \\ DateTime.utc_now()) do
  # tests pass an explicit `now`; production code calls without argument.
end
```

This avoids Mox overhead for trivially-controlled state. Same pattern works for `&Function.module/0` injections.

## Boundary Testing

When code does comparisons (`<`, `>=`, time windows, off-by-one rules), test exactly one unit on either side of each boundary.

```elixir
describe "imminent_rain?/2 - 4-hour window" do
  test "weather one second in the future is imminent" do
    now = DateTime.from_naive!(~N[2026-01-01 12:00:00], "Etc/UTC")
    one_sec_later = DateTime.from_naive!(~N[2026-01-01 12:00:01], "Etc/UTC")
    assert Weather.imminent_rain?([%Weather{datetime: one_sec_later, rain?: true}], now) == true
  end

  test "weather right at 4 hours is imminent (boundary inclusive)" do
    now = DateTime.from_naive!(~N[2026-01-01 12:00:00], "Etc/UTC")
    four_h = DateTime.from_naive!(~N[2026-01-01 16:00:00], "Etc/UTC")
    assert Weather.imminent_rain?([%Weather{datetime: four_h, rain?: true}], now) == true
  end

  test "weather one second past 4 hours is NOT imminent (boundary exclusive)" do
    now = DateTime.from_naive!(~N[2026-01-01 12:00:00], "Etc/UTC")
    past_4h = DateTime.from_naive!(~N[2026-01-01 16:00:01], "Etc/UTC")
    assert Weather.imminent_rain?([%Weather{datetime: past_4h, rain?: true}], now) == false
  end
end
```

Pick a granularity (second, day, byte) finer than your code can observe — this proves the boundary line is exactly where you intended.

## Randomization {#randomization}

Distinguish **essential** from **incidental** test data:

- **Essential** data changes the code's behaviour. Enumerate it explicitly. Example: weather IDs that determine the rain branch.
- **Incidental** data flows through unchanged. Randomize it. Example: a `city` string passed straight to a stub. Randomization signals to readers "this value doesn't matter".

```elixir
# Incidental — randomize.
expected_city = Enum.random(["Denver", "Los Angeles", "New York", "Berlin"])

# Essential — enumerate.
@rain_ids [500, 501, 502, 503, 504, 511, 520, 521, 522, 531]
for id <- @rain_ids do
  test "id #{id} is rain" do ... end
end
```

**When you don't know all valid values but can describe rules** → reach for property-based testing (see `stream-data.md`).

**Reproducing failures from randomized tests:** ExUnit prints `Randomized with seed 654321`. Replay with `mix test --seed 654321`.

## Phoenix Controller Tests (JSON / HTML)

Pattern from the book (Chapter 6). LiveView is covered in `liveview-testing.md`.

```elixir
defmodule KlassHeroWeb.JsonApi.UserControllerTest do
  use KlassHeroWeb.ConnCase, async: false   # async: false → sandbox shared mode

  alias KlassHero.Accounts.User

  describe "PUT /api/users/:id" do
    setup context do
      {:ok, user} = Factory.insert(:user)
      conn_with_token =
        context.conn
        |> put_req_header("authorization", "Bearer " <> sign_jwt(user.id))

      Map.merge(context, %{user: user, conn_with_token: conn_with_token})
    end

    test "happy path: 200 + DB updated", %{conn_with_token: conn, user: user} do
      conn = put(conn, ~p"/api/users/#{user.id}", user: %{name: "New Name"})

      assert response = json_response(conn, 200)
      assert response["name"] == "New Name"

      reloaded = Repo.get(User, user.id)
      assert reloaded.name == "New Name"
      assert reloaded.updated_at != user.updated_at
    end

    test "error path: invalid params return 422 + DB unchanged",
         %{conn_with_token: conn, user: user} do
      conn = put(conn, ~p"/api/users/#{user.id}", user: %{name: ""})

      assert body = json_response(conn, 422)
      refute Enum.empty?(body["errors"])

      assert Repo.get(User, user.id) == user      # side-effect assertion
    end
  end
end
```

### Helpers from ConnCase

| Helper | What it does |
|---|---|
| `json_response(conn, 200)` | Asserts status + parses body as JSON map |
| `html_response(conn, 200)` | Asserts status + returns raw HTML string |
| `redirected_to(conn)` | Returns the path the response redirects to |
| `redirected_params(conn)` | Returns params the redirect URL was built from |
| `get_session(conn, :key)` | Reads a session value the controller set |
| `get_flash(conn, :info)` | Reads a flash message (legacy controller). For LiveView use `Phoenix.Flash.get/2`. |

### HTML assertions

Use the fuzzy match operator `=~` for short text checks: `assert html_response(conn, 200) =~ "Create a new account"`.

For structured assertions (specific tags, attributes, error messages on inputs), parse with **Floki**:

```elixir
parsed = html |> Floki.parse_document!() |> Floki.find("#email-error")
assert Floki.text(parsed) == "can't be blank"
```

### Sandbox mode

Default mode is `:manual` — only the test process can use checked-out connections.

`async: false` test cases use `:shared` mode (any process can use the same connection). Required when:
- Multiple processes (Task, GenServer, Oban) touch the DB during the test.
- Mox is in `set_mox_global` mode.

ConnCase scaffolds this:

```elixir
setup tags do
  :ok = Ecto.Adapters.SQL.Sandbox.checkout(KlassHero.Repo)
  unless tags[:async] do
    Ecto.Adapters.SQL.Sandbox.mode(KlassHero.Repo, {:shared, self()})
  end
  {:ok, conn: Phoenix.ConnTest.build_conn()}
end
```

## Common Mistakes

| Mistake | Why it bites | Fix |
|---|---|---|
| `refute {:error, _} = result` | Pattern match raises `MatchError` if it fails — never reaches refute | `refute match?({:error, _}, result)` |
| `refute []` | `[]` is truthy in Elixir | `assert Enum.empty?(list)` |
| Reading data outside `Multi`, using inside | Race condition under concurrent writes | Read inside `Multi.run/3` |
| `Multi.run` for side effects | `Multi.run` is for transactional ops, not side effects | Use a separate post-commit handler |
| `Process.sleep/1` in tests | Slow + flaky | Use `assert_receive`, `Task.await`, `assert_patch` |
| Hard-coded `DateTime.utc_now/0` in code-under-test | Tests can't control time | Inject `now \\ DateTime.utc_now()` as default param |
| Test reads private function via macro tricks | Brittle, hides design smell | Make it public OR test via the public surface that uses it |

## See also

- `stream-data.md` for property-based testing
- `liveview-testing.md` for LiveView-specific patterns
- `.claude/rules/database.md` for sandbox + Ecto rules
- Book chapters: 1 (Unit Tests), 2 (Integration & Mox), 6 (Phoenix), Appendix 2 (Life Cycle)
