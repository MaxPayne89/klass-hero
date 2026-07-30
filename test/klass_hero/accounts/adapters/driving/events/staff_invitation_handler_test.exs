defmodule KlassHero.Accounts.Adapters.Driving.Events.StaffInvitationHandlerTest do
  @moduledoc """
  Tests for StaffInvitationHandler.

  Calls handle_event/1 directly (no PubSub) and asserts on:
  - Email delivery via Swoosh test adapter
  - Integration event emission via TestIntegrationEventPublisher
  """

  use KlassHero.DataCase, async: true

  import KlassHero.AccountsFixtures
  import KlassHero.EmailTestHelper
  import KlassHero.EventTestHelper
  import Swoosh.TestAssertions

  alias KlassHero.Accounts.Adapters.Driving.Events.StaffInvitationHandler
  alias KlassHero.Provider.Domain.Events.ProviderEvents
  alias KlassHero.Shared.Domain.Events.IntegrationEvent

  setup do
    setup_test_integration_events()
    :ok
  end

  defp build_staff_member_invited_event(attrs) do
    staff_member_id = Map.get(attrs, :staff_member_id, Ecto.UUID.generate())

    ProviderEvents.staff_member_invited(
      staff_member_id,
      Map.delete(attrs, :staff_member_id)
    )
  end

  describe "subscribed_events/0" do
    test "subscribes to :staff_member_invited" do
      assert :staff_member_invited in StaffInvitationHandler.subscribed_events()
    end
  end

  describe "handle_event/1 — new user path" do
    test "sends invitation email when email doesn't belong to an existing user" do
      staff_member_id = Ecto.UUID.generate()
      provider_id = Ecto.UUID.generate()
      email = "new-staff-#{System.unique_integer([:positive])}@example.com"

      event =
        build_staff_member_invited_event(%{
          staff_member_id: staff_member_id,
          provider_id: provider_id,
          email: email,
          first_name: "Jane",
          last_name: "Doe",
          business_name: "Fun Academy",
          raw_token: "test-token-abc"
        })

      assert :ok = StaffInvitationHandler.handle_event(event)

      assert_email_sent(fn email ->
        assert email.subject =~ "Fun Academy"
        assert email.text_body =~ "test-token-abc"
        assert email.text_body =~ "Jane"
        # Registration-style copy for a brand-new account.
        assert email.text_body =~ "Set up your account"
      end)
    end

    test "emits :staff_invitation_sent for new user" do
      staff_member_id = Ecto.UUID.generate()
      provider_id = Ecto.UUID.generate()
      email = "new-staff-#{System.unique_integer([:positive])}@example.com"

      event =
        build_staff_member_invited_event(%{
          staff_member_id: staff_member_id,
          provider_id: provider_id,
          email: email,
          first_name: "Jane",
          last_name: "Doe",
          business_name: "Fun Academy",
          raw_token: "test-token-xyz"
        })

      assert :ok = StaffInvitationHandler.handle_event(event)

      ie = assert_integration_event_published(:staff_invitation_sent)
      assert ie.payload.staff_member_id == staff_member_id
      assert ie.payload.provider_id == provider_id
      assert ie.source_context == :accounts
    end
  end

  describe "handle_event/1 — existing user path (#967: invite, not silent auto-link)" do
    test "sends the log-in-and-link invitation email (not the registration copy)" do
      user = user_fixture()
      # Drain emails sent by user_fixture (confirmation/login instructions)
      flush_emails()

      event =
        build_staff_member_invited_event(%{
          staff_member_id: Ecto.UUID.generate(),
          provider_id: Ecto.UUID.generate(),
          email: user.email,
          first_name: "Jane",
          last_name: "Doe",
          business_name: "Cool Sports",
          raw_token: "the-token"
        })

      assert :ok = StaffInvitationHandler.handle_event(event)

      assert_email_sent(fn email ->
        assert email.subject =~ "Cool Sports"
        assert email.text_body =~ "the-token"
        # Existing-account copy: log in to accept, not register.
        refute email.text_body =~ "Set up your account"
        assert email.text_body =~ "log in"
      end)
    end

    test "emits :staff_invitation_sent and does NOT auto-link via :staff_user_registered" do
      user = user_fixture()
      staff_member_id = Ecto.UUID.generate()
      provider_id = Ecto.UUID.generate()

      event =
        build_staff_member_invited_event(%{
          staff_member_id: staff_member_id,
          provider_id: provider_id,
          email: user.email,
          first_name: "Jane",
          last_name: "Doe",
          business_name: "Cool Sports",
          raw_token: "the-token"
        })

      assert :ok = StaffInvitationHandler.handle_event(event)

      sent = assert_integration_event_published(:staff_invitation_sent)
      assert sent.payload.staff_member_id == staff_member_id

      types = get_published_integration_events() |> Enum.map(& &1.event_type)
      refute :staff_user_registered in types
    end
  end

  describe "handle_event/1 — unknown events" do
    test "ignores unknown events" do
      event = IntegrationEvent.new(:unknown, :some_context, :some_entity, "some-id", %{})
      assert :ignore = StaffInvitationHandler.handle_event(event)
    end
  end

  describe "handle_event/1 — malformed payloads" do
    test "returns error for missing email in payload" do
      event =
        ProviderEvents.staff_member_invited(Ecto.UUID.generate(), %{
          provider_id: Ecto.UUID.generate(),
          first_name: "Jane",
          business_name: "Test Co",
          raw_token: "token"
        })

      event = %{event | payload: Map.delete(event.payload, :email)}

      assert {:error, :invalid_payload} = StaffInvitationHandler.handle_event(event)
    end
  end
end
