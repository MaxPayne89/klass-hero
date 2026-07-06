defmodule KlassHero.Accounts.Domain.Events.AccountsIntegrationEventsTest do
  @moduledoc """
  Tests for AccountsIntegrationEvents factory module.
  """

  use ExUnit.Case, async: true

  alias KlassHero.Accounts.Domain.Events.AccountsIntegrationEvents
  alias KlassHero.Shared.Domain.Events.IntegrationEvent

  describe "user_registered/3" do
    test "creates event with correct type, source_context, and entity_type" do
      user_id = Ecto.UUID.generate()

      event = AccountsIntegrationEvents.user_registered(user_id)

      assert %IntegrationEvent{} = event
      assert event.event_type == :user_registered
      assert event.source_context == :accounts
      assert event.entity_type == :user
      assert event.entity_id == user_id
    end

    test "includes user_id in payload" do
      user_id = Ecto.UUID.generate()

      event = AccountsIntegrationEvents.user_registered(user_id, %{registration_source: "web"})

      assert event.payload.user_id == user_id
      assert event.payload.registration_source == "web"
    end

    test "base_payload user_id wins over caller-supplied user_id" do
      real_id = Ecto.UUID.generate()
      conflicting_payload = %{user_id: "should-be-overridden", extra: "data"}

      event = AccountsIntegrationEvents.user_registered(real_id, conflicting_payload)

      assert event.payload.user_id == real_id
      assert event.payload.extra == "data"
    end

    test "marks event as critical by default" do
      user_id = Ecto.UUID.generate()

      event = AccountsIntegrationEvents.user_registered(user_id)

      assert IntegrationEvent.critical?(event)
    end

    test "allows overriding criticality via opts" do
      user_id = Ecto.UUID.generate()

      event = AccountsIntegrationEvents.user_registered(user_id, %{}, criticality: :normal)

      refute IntegrationEvent.critical?(event)
    end

    test "raises for nil user_id" do
      assert_raise ArgumentError,
                   ~r/requires a non-empty user_id string/,
                   fn -> AccountsIntegrationEvents.user_registered(nil) end
    end

    test "raises for empty string user_id" do
      assert_raise ArgumentError,
                   ~r/requires a non-empty user_id string/,
                   fn -> AccountsIntegrationEvents.user_registered("") end
    end
  end

  describe "user_anonymized/3" do
    test "creates event with correct type, source_context, and entity_type" do
      user_id = Ecto.UUID.generate()

      event = AccountsIntegrationEvents.user_anonymized(user_id)

      assert %IntegrationEvent{} = event
      assert event.event_type == :user_anonymized
      assert event.source_context == :accounts
      assert event.entity_type == :user
      assert event.entity_id == user_id
    end

    test "includes user_id in payload alongside caller data" do
      user_id = Ecto.UUID.generate()

      event =
        AccountsIntegrationEvents.user_anonymized(user_id, %{previous_email: "old@test.com"})

      assert event.payload.user_id == user_id
      assert event.payload.previous_email == "old@test.com"
    end

    test "base_payload user_id wins over caller-supplied user_id" do
      real_id = Ecto.UUID.generate()
      conflicting_payload = %{user_id: "should-be-overridden", extra: "data"}

      event = AccountsIntegrationEvents.user_anonymized(real_id, conflicting_payload)

      assert event.payload.user_id == real_id
      assert event.payload.extra == "data"
    end

    test "marks event as critical by default" do
      user_id = Ecto.UUID.generate()

      event = AccountsIntegrationEvents.user_anonymized(user_id)

      assert IntegrationEvent.critical?(event)
    end

    test "allows overriding criticality via opts" do
      user_id = Ecto.UUID.generate()

      event = AccountsIntegrationEvents.user_anonymized(user_id, %{}, criticality: :normal)

      refute IntegrationEvent.critical?(event)
    end

    test "raises for nil user_id" do
      assert_raise ArgumentError,
                   ~r/requires a non-empty user_id string/,
                   fn -> AccountsIntegrationEvents.user_anonymized(nil) end
    end

    test "raises for empty string user_id" do
      assert_raise ArgumentError,
                   ~r/requires a non-empty user_id string/,
                   fn -> AccountsIntegrationEvents.user_anonymized("") end
    end
  end

  describe "user_confirmed/3" do
    test "creates event with correct type, source_context, and entity_type" do
      user_id = Ecto.UUID.generate()

      event = AccountsIntegrationEvents.user_confirmed(user_id)

      assert %IntegrationEvent{} = event
      assert event.event_type == :user_confirmed
      assert event.source_context == :accounts
      assert event.entity_type == :user
      assert event.entity_id == user_id
    end

    test "includes user_id in payload alongside caller data" do
      user_id = Ecto.UUID.generate()

      event =
        AccountsIntegrationEvents.user_confirmed(user_id, %{
          intended_roles: ["provider"]
        })

      assert event.payload.user_id == user_id
      assert event.payload.intended_roles == ["provider"]
    end

    test "base_payload user_id wins over caller-supplied user_id" do
      real_id = Ecto.UUID.generate()
      conflicting_payload = %{user_id: "should-be-overridden", extra: "data"}

      event = AccountsIntegrationEvents.user_confirmed(real_id, conflicting_payload)

      assert event.payload.user_id == real_id
      assert event.payload.extra == "data"
    end

    test "marks event as critical by default" do
      user_id = Ecto.UUID.generate()

      event = AccountsIntegrationEvents.user_confirmed(user_id)

      assert IntegrationEvent.critical?(event)
    end

    test "raises for nil user_id" do
      assert_raise ArgumentError,
                   ~r/requires a non-empty user_id string/,
                   fn -> AccountsIntegrationEvents.user_confirmed(nil) end
    end

    test "raises for empty string user_id" do
      assert_raise ArgumentError,
                   ~r/requires a non-empty user_id string/,
                   fn -> AccountsIntegrationEvents.user_confirmed("") end
    end
  end
end
