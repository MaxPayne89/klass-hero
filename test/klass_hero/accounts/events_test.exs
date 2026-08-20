defmodule KlassHero.Accounts.EventsTest do
  use ExUnit.Case, async: true

  alias KlassHero.Accounts.Events
  alias KlassHero.Shared.Domain.Events.Event

  # The staff factories take an id, because their producers hold one and not a
  # user. They share one contract: build an event with stable identity fields,
  # let the id argument win over any caller-supplied id (while preserving
  # extras), and raise on a blank id. Rows vary only by the id field name and
  # entity_type.
  @staff_factories [
    %{fun: :staff_invitation_sent, id: :staff_member_id, entity: :staff_member},
    %{fun: :staff_invitation_failed, id: :staff_member_id, entity: :staff_member},
    %{fun: :staff_user_registered, id: :user_id, entity: :user}
  ]

  for %{fun: fun, id: id, entity: entity} <- @staff_factories do
    describe "#{fun}/3" do
      @fun fun
      @id id
      @entity entity

      test "builds an event with stable identity fields" do
        event = apply(Events, @fun, ["id-1"])

        assert %Event{} = event
        assert event.event_type == @fun
        assert event.source_context == :accounts
        assert event.entity_type == @entity
        assert event.entity_id == "id-1"
        assert Map.get(event.payload, @id) == "id-1"
      end

      test "the id argument wins over a caller-supplied one and preserves extras" do
        payload = %{@id => "overridden", :extra => "data"}
        event = apply(Events, @fun, ["real-id", payload])

        assert Map.get(event.payload, @id) == "real-id"
        assert event.payload.extra == "data"
      end

      test "raises for a nil or blank id" do
        for bad_id <- [nil, ""] do
          assert_raise ArgumentError, ~r/requires a non-empty #{@id} string/, fn ->
            apply(Events, @fun, [bad_id])
          end
        end
      end
    end
  end

  # The user factories take the user, so they can validate it and derive the
  # payload from it. Each rejects a different set of missing fields.
  describe "user_registered/3 validation" do
    @invalid [
      {%{id: nil, email: "test@example.com", name: "Test User"}, "User.id cannot be nil for user_registered event"},
      {%{id: 1, email: nil, name: "Test User"}, "User.email cannot be nil or empty for user_registered event"},
      {%{id: 1, email: "", name: "Test User"}, "User.email cannot be nil or empty for user_registered event"},
      {%{id: 1, email: "test@example.com", name: nil}, "User.name cannot be nil or empty for user_registered event"},
      {%{id: 1, email: "test@example.com", name: ""}, "User.name cannot be nil or empty for user_registered event"}
    ]

    test "raises for a user missing a required field" do
      for {user, message} <- @invalid do
        assert_raise ArgumentError, message, fn -> Events.user_registered(user) end
      end
    end

    test "raises when intended_roles is not a list" do
      user = %{id: 1, email: "test@example.com", name: "Test User", intended_roles: "parent"}

      assert_raise ArgumentError,
                   ~r/User.intended_roles must be a list/,
                   fn -> Events.user_registered(user) end
    end

    test "succeeds with valid user" do
      user = %{id: 1, email: "test@example.com", name: "Test User"}

      event = Events.user_registered(user)

      assert %Event{} = event
      assert event.event_type == :user_registered
      assert event.source_context == :accounts
      assert event.entity_type == :user
      assert event.entity_id == 1
      assert event.payload.user_id == 1
      assert event.payload.email == "test@example.com"
      assert event.payload.name == "Test User"
    end

    test "succeeds with valid user and custom payload" do
      user = %{id: 1, email: "test@example.com", name: "Test User"}

      event = Events.user_registered(user, %{source: "web"})

      assert event.payload.source == "web"
    end

    test "carries intended_roles as strings, defaulting to an empty list" do
      for {roles, expected} <- [
            {[:parent], ["parent"]},
            {nil, []},
            {[], []},
            {[:parent, :provider], ["parent", "provider"]}
          ] do
        user = %{id: 1, email: "test@example.com", name: "Test User", intended_roles: roles}

        assert Events.user_registered(user).payload.intended_roles == expected
      end
    end

    test "carries no provider_subscription_tier in payload" do
      # Provider tiers removed (ADR-0004)
      user = %{id: 1, email: "test@example.com", name: "Test User", intended_roles: [:provider]}

      event = Events.user_registered(user)

      refute Map.has_key?(event.payload, :provider_subscription_tier)
    end
  end

  describe "user_confirmed/3 validation" do
    @confirmed_at ~U[2024-01-01 12:00:00Z]
    @invalid_confirmed [
      {%{id: nil, email: "test@example.com", confirmed_at: @confirmed_at},
       "User.id cannot be nil for user_confirmed event"},
      {%{id: 1, email: nil, confirmed_at: @confirmed_at}, "User.email cannot be nil or empty for user_confirmed event"},
      {%{id: 1, email: "", confirmed_at: @confirmed_at}, "User.email cannot be nil or empty for user_confirmed event"},
      {%{id: 1, email: "test@example.com", confirmed_at: nil},
       "User.confirmed_at cannot be nil for user_confirmed event"}
    ]

    test "raises for a user missing a required field" do
      for {user, message} <- @invalid_confirmed do
        assert_raise ArgumentError, message, fn -> Events.user_confirmed(user) end
      end
    end

    test "succeeds with valid user" do
      user = %{id: 1, email: "test@example.com", confirmed_at: @confirmed_at}

      event = Events.user_confirmed(user)

      assert %Event{} = event
      assert event.event_type == :user_confirmed
      assert event.source_context == :accounts
      assert event.entity_type == :user
      assert event.entity_id == 1
      assert event.payload.user_id == 1
      assert event.payload.email == "test@example.com"
      # Critical payloads carry timestamps as ISO8601 strings (see #1010).
      assert event.payload.confirmed_at == DateTime.to_iso8601(@confirmed_at)
      # Absent on the user, so the payload carries the empty default.
      assert event.payload.intended_roles == []
    end

    test "succeeds with valid user and custom payload" do
      user = %{id: 1, email: "test@example.com", confirmed_at: @confirmed_at}

      event = Events.user_confirmed(user, %{confirmation_token: "abc123"})

      assert event.payload.confirmation_token == "abc123"
    end

    test "includes name and intended_roles in payload" do
      user = %{
        id: 1,
        email: "test@example.com",
        name: "Test Provider",
        confirmed_at: @confirmed_at,
        intended_roles: [:provider]
      }

      event = Events.user_confirmed(user)

      assert event.payload.name == "Test Provider"
      assert event.payload.intended_roles == ["provider"]
      refute Map.has_key?(event.payload, :provider_subscription_tier)
    end
  end

  describe "user_anonymized/3 validation" do
    test "raises when previous_email is missing, nil or blank" do
      user = %{id: 1, email: "deleted_1@anonymized.local"}

      for payload <- [%{}, %{previous_email: nil}, %{previous_email: ""}] do
        assert_raise ArgumentError, ~r/requires :previous_email in payload/, fn ->
          Events.user_anonymized(user, payload)
        end
      end
    end

    test "raises when user.id is nil" do
      user = %{id: nil, email: "deleted_nil@anonymized.local"}

      assert_raise ArgumentError,
                   "User.id cannot be nil for user_anonymized event",
                   fn ->
                     Events.user_anonymized(user, %{previous_email: "old@example.com"})
                   end
    end

    test "succeeds with valid user and previous_email" do
      user = %{id: 1, email: "deleted_1@anonymized.local"}

      event = Events.user_anonymized(user, %{previous_email: "old@example.com"})

      assert %Event{} = event
      assert event.event_type == :user_anonymized
      assert event.source_context == :accounts
      assert event.entity_type == :user
      assert event.entity_id == 1
      assert event.payload.user_id == 1
      assert event.payload.anonymized_email == "deleted_1@anonymized.local"
      assert event.payload.previous_email == "old@example.com"
      assert event.payload.anonymized_at
    end

    test "succeeds with valid user and additional payload fields" do
      user = %{id: 1, email: "deleted_1@anonymized.local"}

      event =
        Events.user_anonymized(user, %{
          previous_email: "old@example.com",
          deletion_reason: "user_requested"
        })

      assert event.payload.deletion_reason == "user_requested"
    end
  end
end
