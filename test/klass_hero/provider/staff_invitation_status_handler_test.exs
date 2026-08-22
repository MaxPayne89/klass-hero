defmodule KlassHero.Provider.StaffInvitationStatusHandlerTest do
  use KlassHero.DataCase, async: true

  alias KlassHero.Accounts
  alias KlassHero.AccountsFixtures
  alias KlassHero.Provider
  alias KlassHero.Provider.StaffInvitationStatusHandler
  alias KlassHero.ProviderFixtures

  describe "subscribed_events/0" do
    test "subscribes to all three staff invitation events" do
      events = StaffInvitationStatusHandler.subscribed_events()

      assert :staff_invitation_sent in events
      assert :staff_invitation_failed in events
      assert :staff_user_registered in events
    end
  end

  describe "handle_event/1 for :staff_invitation_sent" do
    test "transitions pending staff member to :sent and sets invitation_sent_at" do
      staff = ProviderFixtures.staff_member_fixture(invitation_status: :pending)

      event = Accounts.Events.staff_invitation_sent(staff.id)

      assert :ok = StaffInvitationStatusHandler.handle_event(event)

      assert {:ok, updated} = Provider.get_staff_member(staff.id)
      assert updated.invitation_status == :sent
      assert updated.invitation_sent_at != nil
    end

    test "is idempotent when staff already in :sent status" do
      staff =
        ProviderFixtures.staff_member_fixture(
          invitation_status: :sent,
          invitation_sent_at: ~U[2025-01-01 10:00:00Z]
        )

      event = Accounts.Events.staff_invitation_sent(staff.id)

      assert :ok = StaffInvitationStatusHandler.handle_event(event)

      # Status unchanged, already :sent
      assert {:ok, updated} = Provider.get_staff_member(staff.id)
      assert updated.invitation_status == :sent
    end

    test "returns :ok (idempotent) when staff is already past :pending" do
      # Staff already in :sent — the :pending -> :sent transition is invalid
      staff = ProviderFixtures.staff_member_fixture(invitation_status: :sent)

      event = Accounts.Events.staff_invitation_sent(staff.id)

      # Returns :ok instead of {:error, _} — idempotent by design
      assert :ok = StaffInvitationStatusHandler.handle_event(event)

      # Status unchanged
      assert {:ok, unchanged} = Provider.get_staff_member(staff.id)
      assert unchanged.invitation_status == :sent
    end
  end

  describe "handle_event/1 for :staff_invitation_failed" do
    test "transitions pending staff member to :failed" do
      staff = ProviderFixtures.staff_member_fixture(invitation_status: :pending)

      event = Accounts.Events.staff_invitation_failed(staff.id)

      assert :ok = StaffInvitationStatusHandler.handle_event(event)

      assert {:ok, updated} = Provider.get_staff_member(staff.id)
      assert updated.invitation_status == :failed
    end

    test "is idempotent when staff already in :failed status (was re-enqueued)" do
      staff = ProviderFixtures.staff_member_fixture(invitation_status: :failed)

      event = Accounts.Events.staff_invitation_failed(staff.id)

      assert :ok = StaffInvitationStatusHandler.handle_event(event)

      assert {:ok, updated} = Provider.get_staff_member(staff.id)
      assert updated.invitation_status == :failed
    end
  end

  describe "handle_event/1 for :staff_user_registered" do
    test "transitions sent staff member to :accepted and links user_id" do
      user = AccountsFixtures.unconfirmed_user_fixture()

      staff =
        ProviderFixtures.staff_member_fixture(
          invitation_status: :sent,
          invitation_token_hash: "somehash"
        )

      event =
        Accounts.Events.staff_user_registered(user.id, %{
          staff_member_id: staff.id
        })

      assert :ok = StaffInvitationStatusHandler.handle_event(event)

      assert {:ok, updated} = Provider.get_staff_member(staff.id)
      assert updated.invitation_status == :accepted
      assert updated.user_id == user.id
    end

    test "transitions pending staff member to :accepted (existing user fast path)" do
      user = AccountsFixtures.unconfirmed_user_fixture()

      # Staff still in :pending because existing user skips the :sent step
      staff = ProviderFixtures.staff_member_fixture(invitation_status: :pending)

      event =
        Accounts.Events.staff_user_registered(user.id, %{
          staff_member_id: staff.id
        })

      assert :ok = StaffInvitationStatusHandler.handle_event(event)

      assert {:ok, updated} = Provider.get_staff_member(staff.id)
      assert updated.invitation_status == :accepted
      assert updated.user_id == user.id
    end

    test "is idempotent when processing staff_user_registered twice" do
      user = AccountsFixtures.unconfirmed_user_fixture()

      staff =
        ProviderFixtures.staff_member_fixture(
          invitation_status: :sent,
          invitation_token_hash: "somehash"
        )

      event =
        Accounts.Events.staff_user_registered(user.id, %{
          staff_member_id: staff.id
        })

      assert :ok = StaffInvitationStatusHandler.handle_event(event)

      # Second processing is idempotent (already :accepted)
      assert :ok = StaffInvitationStatusHandler.handle_event(event)

      assert {:ok, updated} = Provider.get_staff_member(staff.id)
      assert updated.invitation_status == :accepted
      assert updated.user_id == user.id
    end
  end

  describe "handle_event/1 with non-existent staff member" do
    test "returns error for :staff_invitation_sent with unknown staff_member_id" do
      event = Accounts.Events.staff_invitation_sent(Ecto.UUID.generate())
      assert {:error, :not_found} = StaffInvitationStatusHandler.handle_event(event)
    end

    test "returns error for :staff_invitation_failed with unknown staff_member_id" do
      event = Accounts.Events.staff_invitation_failed(Ecto.UUID.generate())
      assert {:error, :not_found} = StaffInvitationStatusHandler.handle_event(event)
    end

    test "returns error for :staff_user_registered with unknown staff_member_id" do
      user = AccountsFixtures.unconfirmed_user_fixture()

      event =
        Accounts.Events.staff_user_registered(user.id, %{
          staff_member_id: Ecto.UUID.generate()
        })

      assert {:error, :not_found} = StaffInvitationStatusHandler.handle_event(event)
    end
  end

  describe "handle_event/1 staff_user_registered links the user (ADR-0005: no provider profile)" do
    test "links user_id, accepts the invitation, and creates no provider profile" do
      user = KlassHero.AccountsFixtures.user_fixture(intended_roles: [:staff])
      provider = KlassHero.ProviderFixtures.provider_profile_fixture()

      staff =
        KlassHero.ProviderFixtures.staff_member_fixture(
          provider_id: provider.id,
          email: "staff@test.com",
          first_name: "Test",
          last_name: "Staff",
          invitation_status: :sent,
          invitation_token_hash: :crypto.hash(:sha256, "test-token"),
          invitation_sent_at: DateTime.utc_now()
        )

      event =
        Accounts.Events.staff_user_registered(
          user.id,
          %{staff_member_id: staff.id, provider_id: provider.id}
        )

      assert :ok = StaffInvitationStatusHandler.handle_event(event)

      # Staff member is linked and accepted...
      assert {:ok, linked} = KlassHero.Provider.get_staff_member(staff.id)
      assert linked.user_id == user.id
      assert linked.invitation_status == :accepted

      # ...but being hired created NO provider profile.
      assert {:error, :not_found} = KlassHero.Provider.get_provider_by_identity(user.id)
    end
  end

  describe "handle_event/1 for unknown events" do
    test "returns :ignore for unrecognized event types" do
      event = %{
        event_type: :some_unknown_event,
        entity_id: Ecto.UUID.generate(),
        payload: %{}
      }

      assert :ignore = StaffInvitationStatusHandler.handle_event(event)
    end
  end

  describe "handle_event/1 for malformed payloads" do
    test "returns error for missing staff_member_id" do
      event =
        Accounts.Events.staff_invitation_sent(Ecto.UUID.generate(), %{
          provider_id: Ecto.UUID.generate()
        })

      # Remove staff_member_id from payload to simulate malformed event
      event = %{event | payload: Map.delete(event.payload, :staff_member_id)}

      assert {:error, :invalid_payload} = StaffInvitationStatusHandler.handle_event(event)
    end

    test "returns error for missing user_id in staff_user_registered" do
      event =
        Accounts.Events.staff_user_registered(Ecto.UUID.generate(), %{
          staff_member_id: Ecto.UUID.generate(),
          provider_id: Ecto.UUID.generate()
        })

      # Remove user_id from payload to simulate malformed event
      event = %{event | payload: Map.delete(event.payload, :user_id)}

      assert {:error, :invalid_payload} = StaffInvitationStatusHandler.handle_event(event)
    end
  end
end
