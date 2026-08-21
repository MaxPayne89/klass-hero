defmodule KlassHeroWeb.E2E.Helpers do
  @moduledoc """
  Helpers for the browser tier.

  The tier is small on purpose: every test here must fail for a reason a browser
  is required to observe — real JavaScript, duplicated `phx-trigger-action` forms,
  two concurrent live sessions, or a real file input. Anything assertable from
  server-rendered HTML belongs in `test/flows/` (ADR-0020).

  Three things this module does *not* do any more, all deleted with the messaging
  migration: start a projection GenServer, rebuild a read model, and sleep. They
  existed because no event was ever delivered in this tier — which is precisely
  why the assertions that needed them moved to `test/flows/`, where the real
  outbox runs. What is left here reads the write model or the DOM, so it needs
  none of it.
  """

  use Wallaby.DSL

  import KlassHero.AccountsFixtures

  @poll_interval_ms 100
  @default_timeout_ms 5_000

  @doc """
  Starts a browser session carrying the Ecto sandbox metadata.

  The metadata is what lets the browser's HTTP requests join the test process's
  database transaction, via `Phoenix.Ecto.SQL.Sandbox`.
  """
  def new_session(metadata) do
    {:ok, session} = Wallaby.start_session(metadata: metadata)
    session
  end

  @doc """
  Logs in through the real login form.

  Kept in the browser tier deliberately: the page renders a mobile and a desktop
  copy of the same `phx-trigger-action` form, which `phoenix_test` refuses
  outright ("Found multiple forms with phx-trigger-action"). Only a browser
  decides which copy is clickable and follows the client-side POST the trigger
  fires.

  The user must have had `AccountsFixtures.set_password/1` called on them.
  """
  def log_in(session, %{email: email}) do
    session = visit(session, "/users/log-in")

    assert_has(session, Query.css("#login_form_password"))

    session
    |> fill_in(Query.css("#login_form_password_email"), with: email)
    |> fill_in(Query.css("#login_form_password_password"), with: valid_user_password())
    |> click(Query.css("#login_form_password button[name='user[remember_me]']"))
    |> await(fn s -> not String.contains?(Wallaby.Browser.current_url(s), "/users/log-in") end,
      message: "login redirect did not complete"
    )
  end

  @doc """
  Polls `check` until it returns true, or fails after `:timeout` milliseconds.

  Replaces the fixed `Process.sleep/1` the messaging helpers used to carry: a
  fixed sleep is both slower than it needs to be and still too short on a loaded
  runner.
  """
  def await(session, check, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, @default_timeout_ms)
    message = Keyword.get(opts, :message, "condition was not met")

    do_await(session, check, message, div(timeout, @poll_interval_ms))
  end

  defp do_await(_session, _check, message, 0) do
    raise "#{message} within the timeout"
  end

  defp do_await(session, check, message, attempts) do
    if check.(session) do
      session
    else
      :timer.sleep(@poll_interval_ms)
      do_await(session, check, message, attempts - 1)
    end
  end
end
