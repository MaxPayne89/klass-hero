defmodule KlassHero.Accounts.Domain.Events.AccountsIntegrationEventsStaffTest do
  @moduledoc """
  Tests for staff invitation factory functions in AccountsIntegrationEvents.
  """

  use ExUnit.Case, async: true

  alias KlassHero.Accounts.Domain.Events.AccountsIntegrationEvents
  alias KlassHero.Shared.Domain.Events.IntegrationEvent

  describe "staff_invitation_sent/3" do
    setup do
      %{
        staff_member_id: Ecto.UUID.generate(),
        provider_id: Ecto.UUID.generate()
      }
    end

    test "creates event with correct type, source_context, and entity_type", %{
      staff_member_id: staff_member_id
    } do
      event = AccountsIntegrationEvents.staff_invitation_sent(staff_member_id)

      assert %IntegrationEvent{} = event
      assert event.event_type == :staff_invitation_sent
      assert event.source_context == :accounts
      assert event.entity_type == :staff_member
      assert event.entity_id == staff_member_id
    end

    test "includes staff_member_id in payload alongside caller data", %{
      staff_member_id: staff_member_id,
      provider_id: provider_id
    } do
      event =
        AccountsIntegrationEvents.staff_invitation_sent(staff_member_id, %{
          provider_id: provider_id
        })

      assert event.payload.staff_member_id == staff_member_id
      assert event.payload.provider_id == provider_id
    end

    test "base_payload staff_member_id wins over caller-supplied staff_member_id", %{
      staff_member_id: real_id
    } do
      conflicting_payload = %{staff_member_id: "should-be-overridden", extra: "data"}

      event = AccountsIntegrationEvents.staff_invitation_sent(real_id, conflicting_payload)

      assert event.payload.staff_member_id == real_id
      assert event.payload.extra == "data"
    end

    test "marks event as critical by default", %{staff_member_id: staff_member_id} do
      event = AccountsIntegrationEvents.staff_invitation_sent(staff_member_id)

      assert IntegrationEvent.critical?(event)
    end

    test "allows overriding criticality via opts", %{staff_member_id: staff_member_id} do
      event =
        AccountsIntegrationEvents.staff_invitation_sent(staff_member_id, %{}, criticality: :normal)

      refute IntegrationEvent.critical?(event)
    end

    test "raises for nil staff_member_id" do
      assert_raise ArgumentError,
                   ~r/requires a non-empty staff_member_id string/,
                   fn -> AccountsIntegrationEvents.staff_invitation_sent(nil) end
    end

    test "raises for empty string staff_member_id" do
      assert_raise ArgumentError,
                   ~r/requires a non-empty staff_member_id string/,
                   fn -> AccountsIntegrationEvents.staff_invitation_sent("") end
    end
  end

  describe "staff_invitation_failed/3" do
    setup do
      %{
        staff_member_id: Ecto.UUID.generate(),
        provider_id: Ecto.UUID.generate()
      }
    end

    test "creates event with correct type, source_context, and entity_type", %{
      staff_member_id: staff_member_id
    } do
      event = AccountsIntegrationEvents.staff_invitation_failed(staff_member_id)

      assert %IntegrationEvent{} = event
      assert event.event_type == :staff_invitation_failed
      assert event.source_context == :accounts
      assert event.entity_type == :staff_member
      assert event.entity_id == staff_member_id
    end

    test "includes staff_member_id in payload alongside caller data", %{
      staff_member_id: staff_member_id,
      provider_id: provider_id
    } do
      event =
        AccountsIntegrationEvents.staff_invitation_failed(staff_member_id, %{
          provider_id: provider_id,
          reason: "email_delivery_failed"
        })

      assert event.payload.staff_member_id == staff_member_id
      assert event.payload.provider_id == provider_id
      assert event.payload.reason == "email_delivery_failed"
    end

    test "base_payload staff_member_id wins over caller-supplied staff_member_id", %{
      staff_member_id: real_id
    } do
      conflicting_payload = %{staff_member_id: "should-be-overridden", extra: "data"}

      event = AccountsIntegrationEvents.staff_invitation_failed(real_id, conflicting_payload)

      assert event.payload.staff_member_id == real_id
      assert event.payload.extra == "data"
    end

    test "marks event as critical by default", %{staff_member_id: staff_member_id} do
      event = AccountsIntegrationEvents.staff_invitation_failed(staff_member_id)

      assert IntegrationEvent.critical?(event)
    end

    test "allows overriding criticality via opts", %{staff_member_id: staff_member_id} do
      event =
        AccountsIntegrationEvents.staff_invitation_failed(staff_member_id, %{}, criticality: :normal)

      refute IntegrationEvent.critical?(event)
    end

    test "raises for nil staff_member_id" do
      assert_raise ArgumentError,
                   ~r/requires a non-empty staff_member_id string/,
                   fn -> AccountsIntegrationEvents.staff_invitation_failed(nil) end
    end

    test "raises for empty string staff_member_id" do
      assert_raise ArgumentError,
                   ~r/requires a non-empty staff_member_id string/,
                   fn -> AccountsIntegrationEvents.staff_invitation_failed("") end
    end
  end

  describe "staff_user_registered/3" do
    setup do
      %{
        user_id: Ecto.UUID.generate(),
        staff_member_id: Ecto.UUID.generate(),
        provider_id: Ecto.UUID.generate()
      }
    end

    test "creates event with correct type, source_context, and entity_type", %{
      user_id: user_id
    } do
      event = AccountsIntegrationEvents.staff_user_registered(user_id)

      assert %IntegrationEvent{} = event
      assert event.event_type == :staff_user_registered
      assert event.source_context == :accounts
      assert event.entity_type == :user
      assert event.entity_id == user_id
    end

    test "includes user_id in payload alongside caller data", %{
      user_id: user_id,
      staff_member_id: staff_member_id,
      provider_id: provider_id
    } do
      event =
        AccountsIntegrationEvents.staff_user_registered(user_id, %{
          staff_member_id: staff_member_id,
          provider_id: provider_id
        })

      assert event.payload.user_id == user_id
      assert event.payload.staff_member_id == staff_member_id
      assert event.payload.provider_id == provider_id
    end

    test "base_payload user_id wins over caller-supplied user_id", %{user_id: real_id} do
      conflicting_payload = %{user_id: "should-be-overridden", extra: "data"}

      event = AccountsIntegrationEvents.staff_user_registered(real_id, conflicting_payload)

      assert event.payload.user_id == real_id
      assert event.payload.extra == "data"
    end

    test "marks event as critical by default", %{user_id: user_id} do
      event = AccountsIntegrationEvents.staff_user_registered(user_id)

      assert IntegrationEvent.critical?(event)
    end

    test "allows overriding criticality via opts", %{user_id: user_id} do
      event =
        AccountsIntegrationEvents.staff_user_registered(user_id, %{}, criticality: :normal)

      refute IntegrationEvent.critical?(event)
    end

    test "raises for nil user_id" do
      assert_raise ArgumentError,
                   ~r/requires a non-empty user_id string/,
                   fn -> AccountsIntegrationEvents.staff_user_registered(nil) end
    end

    test "raises for empty string user_id" do
      assert_raise ArgumentError,
                   ~r/requires a non-empty user_id string/,
                   fn -> AccountsIntegrationEvents.staff_user_registered("") end
    end
  end
end
