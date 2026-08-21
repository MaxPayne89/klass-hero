defmodule KlassHeroWeb.FlowCase do
  @moduledoc """
  Case template for the flow tests under `test/flows/`.

  A flow test walks a whole user journey across pages — real router, real plug
  pipeline, real controller redirects, real session cookies — using `phoenix_test`,
  with no browser involved. It is the tier for anything assertable from
  server-rendered HTML. Browser-shaped behaviour (JS hooks, duplicated
  `phx-trigger-action` forms, two concurrent live sessions, CSS visibility) stays
  in `test/e2e/` under Wallaby. See ADR-0020 for the full boundary.

  No tag, and no runner to register: `test/flows/` sits under the default
  `mix test` path and is picked up with the rest of the suite.

  ## `async: false` is required, and enforced

  `Journeys.with_real_outbox/1` swaps the `:outbox` adapter with a global
  `Application.put_env`, so an async test running alongside would stage through
  `ObanOutbox` and find `TestOutbox.staged()` empty. `use ... , async: true` cannot
  be caught at compile time here — `ExUnit.CaseTemplate` applies the caller's opts
  before this template's `using` block runs, so a nested `use ConnCase, async: false`
  is inert — so the `setup` below raises on it instead.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      use KlassHeroWeb.ConnCase

      import KlassHero.AccountsFixtures
      import KlassHero.Factory
      import KlassHeroWeb.Journeys
      import PhoenixTest
    end
  end

  setup context do
    if context.async do
      raise """
      #{inspect(context.module)} uses KlassHeroWeb.FlowCase with async: true.

      Flow tests must be async: false — Journeys.with_real_outbox/1 swaps the
      :outbox adapter application-wide, which would corrupt any test staging
      events concurrently.
      """
    end

    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end
end
