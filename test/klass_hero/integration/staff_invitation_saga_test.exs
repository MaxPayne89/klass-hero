defmodule KlassHero.Integration.StaffInvitationSagaTest do
  @moduledoc """
  End-to-end integration tests for the staff invitation saga.

  These tests exercise the full saga across bounded context boundaries by calling
  handlers directly (synchronously) rather than through PubSub. Each step
  verifies state before proceeding to the next, ensuring the composed flow is
  correct.

  Three saga paths are covered:

  1. Happy path — new user: invite → email sent → status :sent → user registers
     → staff linked, status :accepted
  2. Existing user — fast path: invite → notification sent → :staff_user_registered
     emitted immediately → staff linked, status :accepted
  3. Compensation — email failure and resend: invite → email fails → status :failed
     → resend → status :pending → email sent → status :sent
  """

  use KlassHero.DataCase, async: true

  import KlassHero.AccountsFixtures
  import KlassHero.EmailTestHelper
  import KlassHero.EventTestHelper
  import KlassHero.ProviderFixtures
  import Swoosh.TestAssertions

  alias KlassHero.Accounts
  alias KlassHero.Accounts.Scope
  alias KlassHero.Accounts.StaffInvitationHandler
  alias KlassHero.Provider
  alias KlassHero.Provider.StaffInvitationStatusHandler

  defp build_invited_event(staff, provider, raw_token) do
    Provider.Events.staff_member_invited(
      staff.id,
      %{
        provider_id: staff.provider_id,
        email: staff.email,
        first_name: staff.first_name,
        last_name: staff.last_name,
        business_name: provider.business_name,
        raw_token: raw_token
      }
    )
  end

  defp build_sent_event(staff) do
    Accounts.Events.staff_invitation_sent(
      staff.id,
      %{provider_id: staff.provider_id}
    )
  end

  defp build_failed_event(staff, reason \\ "delivery_error") do
    Accounts.Events.staff_invitation_failed(
      staff.id,
      %{provider_id: staff.provider_id, reason: reason}
    )
  end

  defp build_registered_event(user_id, staff, opts) do
    Accounts.Events.staff_user_registered(
      user_id,
      Map.merge(%{staff_member_id: staff.id, provider_id: staff.provider_id}, opts)
    )
  end

  # Path 1: Happy path — new user

  describe "full saga — new user" do
    setup do
      setup_test_integration_events()
      :ok
    end

    # A saga test asserts each hop of the chain, so the count is the point rather
    # than a sign of conflated concerns; splitting it would re-run the whole saga
    # per assertion.
    # credo:disable-for-next-line Jump.CredoChecks.TooManyAssertions
    test "staff member creation through invitation, registration, and account linking" do
      provider = provider_profile_fixture()
      email = "new-staff-#{System.unique_integer([:positive])}@example.com"

      # Step 1: Create staff member — returns {:ok, staff, raw_token} when email present
      assert {:ok, staff, raw_token} =
               Provider.create_staff_member(%{
                 provider_id: provider.id,
                 first_name: "Jane",
                 last_name: "Doe",
                 email: email
               })

      assert staff.invitation_status == :pending
      assert staff.invitation_token_hash != nil
      assert is_binary(raw_token)

      # Reset integration events so StaffInvitationHandler can emit cleanly
      clear_integration_events()

      # Step 2: StaffInvitationHandler handles :staff_member_invited
      # → sends invitation email, emits :staff_invitation_sent
      invited_event = build_invited_event(staff, provider, raw_token)
      assert :ok = StaffInvitationHandler.handle_event(invited_event)

      assert_email_sent(fn email_msg ->
        assert email_msg.subject =~ provider.business_name
        assert email_msg.text_body =~ raw_token
        assert email_msg.text_body =~ "Jane"
      end)

      sent_ie = assert_integration_event_published(:staff_invitation_sent)
      assert sent_ie.payload.staff_member_id == staff.id

      # Step 3: StaffInvitationStatusHandler handles :staff_invitation_sent
      # → status transitions :pending → :sent
      sent_event = build_sent_event(staff)
      assert :ok = StaffInvitationStatusHandler.handle_event(sent_event)

      assert {:ok, staff_after_sent} = Provider.get_staff_member(staff.id)
      assert staff_after_sent.invitation_status == :sent
      assert staff_after_sent.invitation_sent_at != nil

      # Step 4: New user registers via staff registration path
      # Flush any emails from the fixture setup above
      flush_emails()

      assert {:ok, user} =
               Accounts.register_staff_user(%{
                 email: email,
                 name: "Jane Doe",
                 password: "hello world!"
               })

      assert user.intended_roles == [:staff]

      # Step 5: StaffInvitationStatusHandler handles :staff_user_registered
      # → status :sent → :accepted, user_id linked. No provider profile (ADR-0005).
      # Empty opts exercise the no-flag path; the legacy-flag path (an in-flight event
      # still carrying create_provider_profile) is covered by the handler unit test.
      registered_event = build_registered_event(to_string(user.id), staff, %{})

      assert :ok = StaffInvitationStatusHandler.handle_event(registered_event)

      assert {:ok, staff_accepted} = Provider.get_staff_member(staff.id)
      assert staff_accepted.invitation_status == :accepted
      assert staff_accepted.user_id == user.id

      # Step 6: being hired creates NO provider profile — provider-hood is deliberate
      refute Provider.has_provider_profile?(to_string(user.id))

      # Step 7: Scope resolution gives the user :staff only, never :provider
      scope = Scope.for_user(user) |> Scope.resolve_roles()
      assert :staff in scope.roles
      refute :provider in scope.roles
    end
  end

  # Path 2: Existing user — fast path

  describe "full saga — existing user" do
    setup do
      setup_test_integration_events()
      :ok
    end

    test "existing user is invited (not auto-linked), then links on the accept screen" do
      # Step 1: existing parent account, created before the staff invite
      existing_user = user_fixture(intended_roles: [:parent])
      flush_emails()

      provider = provider_profile_fixture()

      # Step 2: staff member created with the existing user's email
      assert {:ok, staff, raw_token} =
               Provider.create_staff_member(%{
                 provider_id: provider.id,
                 first_name: "Bob",
                 last_name: "Smith",
                 email: existing_user.email
               })

      assert staff.invitation_status == :pending
      clear_integration_events()

      # Step 3: existing users now receive the SAME invitation link as new users —
      # no silent auto-link. :staff_invitation_sent is emitted; :staff_user_registered is NOT.
      invited_event = build_invited_event(staff, provider, raw_token)
      assert :ok = StaffInvitationHandler.handle_event(invited_event)

      assert_email_sent(fn email_msg ->
        assert email_msg.text_body =~ raw_token
      end)

      assert_integration_event_published(:staff_invitation_sent)
      types = get_published_integration_events() |> Enum.map(& &1.event_type)
      refute :staff_user_registered in types

      # Step 4: invitation transitions :pending → :sent
      assert :ok = StaffInvitationStatusHandler.handle_event(build_sent_event(staff))
      assert {:ok, staff_sent} = Provider.get_staff_member(staff.id)
      assert staff_sent.invitation_status == :sent

      # Step 5: the logged-in existing user accepts via the accept screen (one-click link).
      assert {:ok, linked_user} = Accounts.link_staff_invitation(existing_user, staff_sent)

      assert {:ok, staff_accepted} = Provider.get_staff_member(staff.id)
      assert staff_accepted.invitation_status == :accepted
      assert staff_accepted.user_id == existing_user.id

      # No provider profile (ADR-0005); multi-persona — :staff appended, :parent kept.
      refute Provider.has_provider_profile?(to_string(existing_user.id))
      assert linked_user.intended_roles == [:parent, :staff]

      # Scope resolves :staff via the now-linked active StaffMember (race-free).
      scope = Scope.for_user(linked_user) |> Scope.resolve_roles()
      assert :staff in scope.roles
    end
  end

  # Path 3: Compensation — email failure and resend

  describe "compensation — email failure and resend" do
    setup do
      setup_test_integration_events()
      :ok
    end

    test "failed invitation can be resent and completes successfully" do
      provider = provider_profile_fixture()
      email = "resend-staff-#{System.unique_integer([:positive])}@example.com"

      # Step 1: Create staff member → status :pending
      assert {:ok, staff, _raw_token} =
               Provider.create_staff_member(%{
                 provider_id: provider.id,
                 first_name: "Carol",
                 last_name: "White",
                 email: email
               })

      assert staff.invitation_status == :pending
      clear_integration_events()

      # Step 2: Email delivery fails → :staff_invitation_failed emitted
      # Simulate this by calling the status handler with the failure event directly
      failed_event = build_failed_event(staff)
      assert :ok = StaffInvitationStatusHandler.handle_event(failed_event)

      assert {:ok, staff_failed} = Provider.get_staff_member(staff.id)
      assert staff_failed.invitation_status == :failed

      # Step 3: Provider resends the invitation → status back to :pending, new token
      assert {:ok, staff_resent, new_raw_token} =
               Provider.resend_staff_invitation(provider.id, staff.id)

      assert staff_resent.invitation_status == :pending
      assert is_binary(new_raw_token)
      # New token should differ from original
      assert staff_resent.invitation_token_hash != staff.invitation_token_hash

      # A new :staff_member_invited event was emitted by resend
      resent_ie = assert_integration_event_published(:staff_member_invited)
      assert resent_ie.payload.staff_member_id == staff.id
      assert resent_ie.payload.raw_token == new_raw_token

      clear_integration_events()

      # Step 4: StaffInvitationHandler handles the resent :staff_member_invited
      # → sends invitation email again, emits :staff_invitation_sent
      resent_invited_event = build_invited_event(staff_resent, provider, new_raw_token)
      assert :ok = StaffInvitationHandler.handle_event(resent_invited_event)

      assert_email_sent(fn email_msg ->
        assert email_msg.subject =~ provider.business_name
        assert email_msg.text_body =~ new_raw_token
      end)

      assert_integration_event_published(:staff_invitation_sent)

      # Step 5: StaffInvitationStatusHandler handles :staff_invitation_sent
      # → saga recovered, status :sent
      sent_event = build_sent_event(staff_resent)
      assert :ok = StaffInvitationStatusHandler.handle_event(sent_event)

      assert {:ok, staff_recovered} = Provider.get_staff_member(staff.id)
      assert staff_recovered.invitation_status == :sent
      assert staff_recovered.invitation_sent_at != nil
    end
  end
end
