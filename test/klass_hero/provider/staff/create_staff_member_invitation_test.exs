defmodule KlassHero.Provider.Staff.CreateStaffMemberInvitationTest do
  use KlassHero.DataCase, async: true

  import KlassHero.EventTestHelper

  alias KlassHero.Provider
  alias KlassHero.Provider.StaffMember
  alias KlassHero.ProviderFixtures

  setup do
    provider = ProviderFixtures.provider_profile_fixture()
    # Set up after fixture creation so events emitted during setup are not collected
    setup_test_integration_events()
    %{provider: provider}
  end

  describe "execute/1 — invitation token generation" do
    test "staff member with email gets invitation_status :pending and token hash", %{
      provider: provider
    } do
      {:ok, staff, _raw_token} =
        Provider.create_staff_member(%{
          provider_id: provider.id,
          first_name: "Jane",
          last_name: "Doe",
          email: "jane@example.com"
        })

      assert staff.invitation_status == :pending
      assert staff.invitation_token_hash != nil
    end

    test "staff member without email has nil invitation_status and no token", %{
      provider: provider
    } do
      {:ok, staff} =
        Provider.create_staff_member(%{
          provider_id: provider.id,
          first_name: "Bob",
          last_name: "Smith"
        })

      assert staff.invitation_status == nil
      assert staff.invitation_token_hash == nil
    end

    test "returns raw_token when email is present", %{provider: provider} do
      {:ok, staff, raw_token} =
        Provider.create_staff_member(%{
          provider_id: provider.id,
          first_name: "Jane",
          last_name: "Doe",
          email: "jane@example.com"
        })

      assert is_binary(raw_token)
      assert byte_size(raw_token) > 0

      # Verify the token hashes to the stored hash
      assert :crypto.hash(:sha256, Base.url_decode64!(raw_token, padding: false)) ==
               staff.invitation_token_hash
    end

    test "emits :staff_member_invited integration event when email is present", %{
      provider: provider
    } do
      {:ok, staff, _raw_token} =
        Provider.create_staff_member(%{
          provider_id: provider.id,
          first_name: "Jane",
          last_name: "Doe",
          email: "jane@example.com"
        })

      event = assert_integration_event_published(:staff_member_invited)
      assert event.entity_id == staff.id
      assert event.source_context == :provider
      assert event.entity_type == :staff_member
      assert event.payload.staff_member_id == staff.id
      assert event.payload.provider_id == provider.id
      assert event.payload.email == "jane@example.com"
      assert event.payload.first_name == "Jane"
      assert event.payload.last_name == "Doe"
      assert event.payload.business_name == provider.business_name
      assert is_binary(event.payload.raw_token)
    end

    test "whitespace-only email is rejected by domain validation", %{
      provider: provider
    } do
      assert {:error, {:validation_error, errors}} =
               Provider.create_staff_member(%{
                 provider_id: provider.id,
                 first_name: "Blank",
                 last_name: "Email",
                 email: "   "
               })

      assert "Email cannot be empty if provided" in errors
      assert_no_integration_events_published()
    end

    test "does not emit integration event when email is absent", %{provider: provider} do
      {:ok, _staff} =
        Provider.create_staff_member(%{
          provider_id: provider.id,
          first_name: "Bob",
          last_name: "Smith"
        })

      assert_no_integration_events_published()
    end
  end

  # The old contract here was a compensation: publishing happened after the staff
  # member was committed, so a publish failure left a :pending row that nothing would
  # ever invite, and the code wrote :failed over it to make that visible.
  #
  # Staging inside the write removes the state being compensated for. The event
  # cannot fail separately from the row, so there is no half-invited staff member to
  # repair — and the :failed status keeps its real cause, the staff_invitation_failed
  # event Accounts emits when the email itself does not send.
  describe "execute/1 — a staff member and its invitation event are one write" do
    test "creates no staff member when the provider it belongs to is missing" do
      assert {:error, :not_found} =
               Provider.create_staff_member(%{
                 provider_id: Ecto.UUID.generate(),
                 first_name: "Jane",
                 last_name: "Doe",
                 email: "jane@example.com"
               })

      assert [] = Repo.all(from(s in StaffMember, where: s.email == "jane@example.com"))
    end

    test "a created staff member always has its invitation event staged", %{provider: provider} do
      assert {:ok, _staff, _token} =
               Provider.create_staff_member(%{
                 provider_id: provider.id,
                 first_name: "Jane",
                 last_name: "Doe",
                 email: "jane@example.com"
               })

      assert %{invitation_status: :pending} =
               Repo.one!(from(s in StaffMember, where: s.email == "jane@example.com"))

      assert_integration_event_published(:staff_member_invited)
    end
  end
end
