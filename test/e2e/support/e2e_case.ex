defmodule KlassHeroWeb.E2ECase do
  @moduledoc """
  ExUnit.CaseTemplate for browser-driven tests using Wallaby.

  ## What belongs here

  Only what a browser is required to observe: real JavaScript (the hooks in
  `assets/js/hooks/`), duplicated `phx-trigger-action` forms, two concurrent live
  sessions watching each other, a real `<input type=file>`, and CSS-driven
  visibility. Everything assertable from server-rendered HTML is a flow test under
  `test/flows/` — faster, no chromedriver, and (since it drives the real outbox)
  more faithful about event delivery. See ADR-0019.

  Handles:
  - Starting Wallaby (once per test module, lazily)
  - Ecto sandbox ownership with metadata for the sandbox plug
  - Common imports (Wallaby.DSL, factories, fixtures, helpers)

  All tests using this case are tagged `@moduletag :e2e` and excluded from regular
  `mix test` runs. Run with `mix test.e2e`, which needs a chromedriver matching the
  installed Chrome — `bin/worktree-up` installs one when the two have drifted.
  """

  use ExUnit.CaseTemplate

  alias Phoenix.Ecto.SQL.Sandbox

  using do
    quote do
      use Wallaby.DSL

      import KlassHero.AccountsFixtures
      import KlassHero.Factory
      import KlassHeroWeb.E2E.Helpers

      @moduletag :e2e
    end
  end

  setup_all _context do
    {:ok, _} = Application.ensure_all_started(:wallaby)
    :ok
  end

  setup tags do
    pid =
      Ecto.Adapters.SQL.Sandbox.start_owner!(KlassHero.Repo, shared: not tags[:async])

    metadata = Sandbox.metadata_for(KlassHero.Repo, pid)

    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(pid) end)

    {:ok, sandbox_metadata: metadata}
  end
end
