defmodule KlassHero.Provider.Application.Commands.StaffMembers.CreateSelfStaffMemberTest do
  use KlassHero.DataCase, async: true

  import KlassHero.AccountsFixtures
  import KlassHero.EventTestHelper
  import KlassHero.ProviderFixtures

  alias KlassHero.Provider.Application.Commands.StaffMembers.CreateSelfStaffMember

  setup do
    setup_test_integration_events()

    user = user_fixture(intended_roles: [:provider])
    provider = provider_profile_fixture(identity_id: user.id)
    %{user: user, provider: provider}
  end

  describe "execute/3 (happy path)" do
    test "creates a pre-linked, accepted staff member with no invitation artifacts", %{
      user: user,
      provider: provider
    } do
      attrs = %{first_name: "Max", last_name: "Founder", role: "Head Coach"}

      assert {:ok, staff} = CreateSelfStaffMember.execute(provider.id, user.id, attrs)

      assert staff.provider_id == provider.id
      assert staff.user_id == user.id
      assert staff.invitation_status == :accepted
      assert is_nil(staff.invitation_token_hash)
      assert is_nil(staff.invitation_sent_at)
      assert staff.first_name == "Max"
      assert staff.role == "Head Coach"
      assert staff.active == true
    end

    test "publishes no invitation event", %{user: user, provider: provider} do
      attrs = %{first_name: "Max", last_name: "Founder"}

      assert {:ok, _staff} = CreateSelfStaffMember.execute(provider.id, user.id, attrs)

      types = get_published_integration_events() |> Enum.map(& &1.event_type)
      refute :staff_member_invited in types
    end
  end

  describe "execute/3 (already staffed at this provider)" do
    test "returns :already_staffed and creates no second row", %{user: user, provider: provider} do
      attrs = %{first_name: "Max", last_name: "Founder"}
      assert {:ok, _staff} = CreateSelfStaffMember.execute(provider.id, user.id, attrs)

      assert {:error, :already_staffed} =
               CreateSelfStaffMember.execute(provider.id, user.id, attrs)

      assert {:ok, [_only_one]} = KlassHero.Provider.list_staff_members(provider.id)
    end

    test "an inactive existing row does not block self-staffing", %{
      user: user,
      provider: provider
    } do
      staff_member_fixture(%{
        provider_id: provider.id,
        user_id: user.id,
        active: false,
        invitation_status: :accepted
      })

      assert {:ok, _staff} =
               CreateSelfStaffMember.execute(provider.id, user.id, %{
                 first_name: "Max",
                 last_name: "Founder"
               })
    end
  end
end
