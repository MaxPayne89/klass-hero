defmodule KlassHeroWeb.Admin.UndeliveredEventLiveTest do
  use KlassHeroWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias KlassHero.Repo
  alias KlassHero.Shared.Adapters.Driven.Persistence.Schemas.UndeliveredEvent

  describe "admin access control" do
    setup :register_and_log_in_admin

    test "admin can access /admin/undelivered-events", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/admin/undelivered-events")
      assert html =~ "Undelivered Events"
    end

    test "no new button is shown on index", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/undelivered-events")
      refute has_element?(view, "a", "New")
    end
  end

  describe "non-admin access control" do
    setup :register_and_log_in_user

    test "non-admin is redirected from /admin/undelivered-events", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/", flash: flash}}} =
               live(conn, ~p"/admin/undelivered-events")

      assert flash["error"] =~ "access"
    end
  end

  describe "unauthenticated access control" do
    test "unauthenticated user is redirected from /admin/undelivered-events", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/users/log-in"}}} =
               live(conn, ~p"/admin/undelivered-events")
    end
  end

  describe "show view" do
    setup :register_and_log_in_admin

    # The row's identity is `event_id` on a `@primary_key false` schema. Backpex
    # defaults `primary_key` to `:id`, so without the explicit option this route
    # resolves against a column that does not exist.
    test "resolves a record by its event_id", %{conn: conn} do
      event_id = record(topic: "integration:accounts:user_registered")

      {:ok, _view, html} = live(conn, ~p"/admin/undelivered-events/#{event_id}/show")

      assert html =~ "integration:accounts:user_registered"
    end

    # Backpex casts the URL segment against the primary key's declared type. Only its
    # `:id` and `:binary_id` clauses raise `NoResultsError` (a 404); anything else falls
    # to a catch-all that compares raw and blows up as a 500 on a typo'd link.
    test "treats an unparseable id as not found rather than a server error", %{conn: conn} do
      assert_raise Ecto.NoResultsError, fn ->
        live(conn, ~p"/admin/undelivered-events/not-a-uuid/show")
      end
    end

    test "offers replay", %{conn: conn} do
      event_id = record(topic: "integration:accounts:user_registered")

      {:ok, view, _html} = live(conn, ~p"/admin/undelivered-events/#{event_id}/show")

      assert has_element?(view, "#item-action-replay")
    end

    test "renders the full serialized envelope", %{conn: conn} do
      event_id =
        record(
          topic: "integration:enrollment:invite_claimed",
          payload: %{"event_type" => "invite_claimed", "payload" => %{"invite_id" => "inv-4711"}}
        )

      {:ok, view, html} = live(conn, ~p"/admin/undelivered-events/#{event_id}/show")

      assert has_element?(view, "pre")
      assert html =~ "inv-4711"
    end
  end

  describe "index view" do
    setup :register_and_log_in_admin

    # The stored refs are fully qualified. Only the context and the handler name are
    # worth a table cell — the fixed `Adapters.Driving.Events` path in between is
    # boilerplate wide enough to squeeze every other column off the page.
    #
    # Both fixtures are load-bearing and neither is redundant, because the contexts
    # are mid-migration to the flat layout (ADR 0018) and produce two ref shapes:
    # Family is still nested, so it is the case that actually exercises the strip;
    # Provider is flattened, so it proves a ref with no boilerplate passes through
    # unharmed. Deleting either one silently drops a shape from coverage — and
    # because these are string literals, no compiler will tell you.
    test "shortens nested consumer refs and leaves already-flat ones alone",
         %{conn: conn} do
      record(
        topic: "integration:accounts:user_registered",
        missed_consumers: [
          "Elixir.KlassHero.Family.Adapters.Driving.Events.FamilyEventHandler:handle_event",
          "Elixir.KlassHero.Provider.ProviderEventHandler:handle_event"
        ]
      )

      {:ok, _view, html} = live(conn, ~p"/admin/undelivered-events")

      assert html =~ "Family.FamilyEventHandler:handle_event"
      assert html =~ "Provider.ProviderEventHandler:handle_event"
      refute html =~ "Adapters.Driving.Events"
      refute html =~ "Elixir.KlassHero"
    end

    # Ages are offset well clear of the 1h/24h boundaries: the column is rendered
    # against `utc_now/0`, so a value sitting exactly on one would flip on the
    # milliseconds between seeding and rendering.
    @age_cases [
      {300, "5m ago"},
      {3_540, "59m ago"},
      {10_800, "3h ago"},
      {345_600, "4d ago"}
    ]

    test "renders each discard's age beside its timestamp", %{conn: conn} do
      now = DateTime.utc_now()

      for {seconds_ago, _expected} <- @age_cases do
        record(topic: "topic:#{seconds_ago}", discarded_at: DateTime.add(now, -seconds_ago))
      end

      {:ok, _view, html} = live(conn, ~p"/admin/undelivered-events")

      for {seconds_ago, expected} <- @age_cases do
        assert html =~ expected,
               "expected a discard #{seconds_ago}s old to render as #{expected}"
      end
    end

    # Backpex ids a row action `item-action-<key>-<primary_value>`, and the primary
    # value here is `event_id` — the same `primary_key:` option the show route needs.
    test "offers replay on each row", %{conn: conn} do
      event_id = record(topic: "integration:accounts:user_registered")

      {:ok, view, _html} = live(conn, ~p"/admin/undelivered-events")

      assert has_element?(view, "#item-action-replay-#{event_id}")
    end

    test "renders the replay stamp, and says so when there is none", %{conn: conn} do
      record(topic: "topic:untouched")
      record(topic: "topic:replayed", replayed_at: DateTime.utc_now())

      {:ok, _view, html} = live(conn, ~p"/admin/undelivered-events")

      assert html =~ "never"
    end

    test "orders the newest discard first", %{conn: conn} do
      now = DateTime.utc_now()

      record(topic: "topic:older", discarded_at: DateTime.add(now, -2, :day))
      record(topic: "topic:newer", discarded_at: now)

      {:ok, _view, html} = live(conn, ~p"/admin/undelivered-events")

      assert index_of(html, "topic:newer") < index_of(html, "topic:older")
    end
  end

  defp index_of(html, needle) do
    [{position, _length}] = :binary.matches(html, needle)
    position
  end

  # Written straight to the table: producing one by its real route means discarding an
  # Oban job through the compensation sweep, which this view knows nothing about.
  defp record(attrs) do
    event_id = Ecto.UUID.generate()
    discarded_at = Keyword.get(attrs, :discarded_at, DateTime.utc_now())

    Repo.insert_all(UndeliveredEvent, [
      %{
        event_id: event_id,
        topic: Keyword.fetch!(attrs, :topic),
        payload: Keyword.get(attrs, :payload, %{}),
        missed_consumers: Keyword.get(attrs, :missed_consumers, ["Elixir.KlassHero.Whoever:handle_event"]),
        job_id: 1,
        discarded_at: discarded_at,
        inserted_at: discarded_at,
        replayed_at: Keyword.get(attrs, :replayed_at)
      }
    ])

    event_id
  end
end
