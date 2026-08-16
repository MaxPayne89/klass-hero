defmodule KlassHero.Provider.StaffMemberIntegrationTest do
  use KlassHero.DataCase

  alias KlassHero.Provider
  alias KlassHero.ProviderFixtures

  describe "create_staff_member/1" do
    test "creates with valid attrs" do
      provider = ProviderFixtures.provider_profile_fixture()

      assert {:ok, staff} =
               Provider.create_staff_member(%{
                 provider_id: provider.id,
                 first_name: "Mike",
                 last_name: "Johnson",
                 role: "Head Coach",
                 tags: ["sports"],
                 qualifications: ["First Aid"]
               })

      assert staff.first_name == "Mike"
      assert staff.tags == ["sports"]
    end

    test "rejects invalid tags" do
      provider = ProviderFixtures.provider_profile_fixture()

      assert {:error, {:validation_error, errors}} =
               Provider.create_staff_member(%{
                 provider_id: provider.id,
                 first_name: "Mike",
                 last_name: "Johnson",
                 tags: ["invalid_category"]
               })

      assert Enum.any?(errors, &String.contains?(&1, "invalid_category"))
    end
  end

  describe "list_staff_members/1" do
    test "returns staff for provider" do
      provider = ProviderFixtures.provider_profile_fixture()

      _staff =
        ProviderFixtures.staff_member_fixture(provider_id: provider.id, first_name: "Alice")

      assert {:ok, [member]} = Provider.list_staff_members(provider.id)
      assert member.first_name == "Alice"
    end

    test "returns empty list for provider with no staff" do
      provider = ProviderFixtures.provider_profile_fixture()
      assert {:ok, []} = Provider.list_staff_members(provider.id)
    end
  end

  describe "list_active_staff_members/1" do
    test "returns only active staff members" do
      provider = ProviderFixtures.provider_profile_fixture()

      _active =
        ProviderFixtures.staff_member_fixture(
          provider_id: provider.id,
          first_name: "Active",
          active: true
        )

      inactive =
        ProviderFixtures.staff_member_fixture(
          provider_id: provider.id,
          first_name: "Inactive"
        )

      # Deactivate the second staff member
      {:ok, _} = Provider.deactivate_staff_member(inactive)

      assert {:ok, members} = Provider.list_active_staff_members(provider.id)
      assert length(members) == 1
      assert hd(members).first_name == "Active"
    end

    test "returns empty list when no active staff" do
      provider = ProviderFixtures.provider_profile_fixture()

      staff =
        ProviderFixtures.staff_member_fixture(
          provider_id: provider.id,
          first_name: "Inactive"
        )

      {:ok, _} = Provider.deactivate_staff_member(staff)

      assert {:ok, []} = Provider.list_active_staff_members(provider.id)
    end
  end

  # Reading *past* attribution, not present authorization: a message sent by someone
  # who has since left must keep rendering as it did (#1348), so employment ever —
  # not employment now — is the question. Unclaimed invitations have no user_id and
  # can never have sent anything.
  describe "list_staff_user_ids_for_provider/1" do
    test "includes deactivated staff and excludes unclaimed invitations" do
      provider = ProviderFixtures.provider_profile_fixture()
      other_provider = ProviderFixtures.provider_profile_fixture()
      active_user = KlassHero.AccountsFixtures.user_fixture()
      departed_user = KlassHero.AccountsFixtures.user_fixture()
      other_user = KlassHero.AccountsFixtures.user_fixture()

      ProviderFixtures.staff_member_fixture(provider_id: provider.id, user_id: active_user.id)
      ProviderFixtures.staff_member_fixture(provider_id: provider.id, first_name: "Unclaimed")
      ProviderFixtures.staff_member_fixture(provider_id: other_provider.id, user_id: other_user.id)

      departed =
        ProviderFixtures.staff_member_fixture(provider_id: provider.id, user_id: departed_user.id)

      {:ok, _} = Provider.deactivate_staff_member(departed)

      ids = Provider.list_staff_user_ids_for_provider(provider.id)

      assert Enum.sort(ids) == Enum.sort([active_user.id, departed_user.id])
    end
  end

  describe "update_staff_member/3" do
    test "updates allowed fields" do
      staff = ProviderFixtures.staff_member_fixture(first_name: "Old", role: "Assistant")

      assert {:ok, updated} = Provider.update_staff_member(staff.provider_id, staff.id, %{role: "Head Coach"})
      assert updated.role == "Head Coach"
      assert updated.first_name == "Old"
    end

    test "rejects update with invalid data (empty first_name)" do
      staff = ProviderFixtures.staff_member_fixture(first_name: "Valid")

      assert {:error, {:validation_error, errors}} =
               Provider.update_staff_member(staff.provider_id, staff.id, %{first_name: ""})

      assert "First name cannot be empty" in errors
    end

    test "returns not_found for non-existent staff member" do
      assert {:error, :not_found} =
               Provider.update_staff_member(Ecto.UUID.generate(), Ecto.UUID.generate(), %{
                 role: "Coach"
               })
    end

    test "cannot change provider_id through update" do
      staff = ProviderFixtures.staff_member_fixture()
      other_provider = ProviderFixtures.provider_profile_fixture()

      # Trigger: update with a different provider_id
      # Why: edit_changeset excludes provider_id from cast, so it should be ignored
      # Outcome: provider_id remains unchanged after update
      assert {:ok, updated} =
               Provider.update_staff_member(staff.provider_id, staff.id, %{
                 provider_id: other_provider.id,
                 role: "New Role"
               })

      assert updated.provider_id == staff.provider_id
      assert updated.role == "New Role"
    end

    test "updates headshot_url" do
      staff = ProviderFixtures.staff_member_fixture(first_name: "Photo")

      assert {:ok, updated} =
               Provider.update_staff_member(staff.provider_id, staff.id, %{
                 headshot_url: "headshots/providers/abc/new_photo.jpg"
               })

      assert updated.headshot_url == "headshots/providers/abc/new_photo.jpg"
      assert updated.first_name == "Photo"
    end

    test "clears headshot_url with nil" do
      staff =
        ProviderFixtures.staff_member_fixture(headshot_url: "headshots/providers/abc/old_photo.jpg")

      assert {:ok, updated} = Provider.update_staff_member(staff.provider_id, staff.id, %{headshot_url: nil})
      assert updated.headshot_url == nil
    end
  end

  describe "delete_staff_member/2" do
    test "deletes existing staff member" do
      staff = ProviderFixtures.staff_member_fixture()
      assert :ok = Provider.delete_staff_member(staff.id, staff.provider_id)
      assert {:error, :not_found} = Provider.get_staff_member(staff.id)
    end

    test "returns not_found for missing id" do
      staff = ProviderFixtures.staff_member_fixture()

      assert {:error, :not_found} =
               Provider.delete_staff_member(Ecto.UUID.generate(), staff.provider_id)
    end
  end

  describe "change_staff_member/2" do
    test "returns a changeset for an existing staff member" do
      staff = ProviderFixtures.staff_member_fixture(first_name: "Original")
      changeset = Provider.change_staff_member(staff)

      assert %Ecto.Changeset{} = changeset
    end

    test "returns a changeset with applied changes" do
      staff = ProviderFixtures.staff_member_fixture(first_name: "Original")
      changeset = Provider.change_staff_member(staff, %{first_name: "Updated"})

      assert %Ecto.Changeset{} = changeset
      assert Ecto.Changeset.get_field(changeset, :first_name) == "Updated"
    end
  end

  describe "new_staff_member_changeset/1" do
    test "returns an empty changeset with defaults" do
      changeset = Provider.new_staff_member_changeset()
      assert %Ecto.Changeset{} = changeset
    end

    test "returns a changeset with given attrs" do
      changeset = Provider.new_staff_member_changeset(%{first_name: "New"})
      assert %Ecto.Changeset{} = changeset
      assert Ecto.Changeset.get_field(changeset, :first_name) == "New"
    end
  end

  describe "expire_staff_invitation/1" do
    test "transitions :sent staff member to :expired with struct" do
      staff =
        ProviderFixtures.staff_member_fixture(
          email: "expiry@example.com",
          invitation_status: :sent,
          invitation_token_hash: :crypto.hash(:sha256, "token"),
          invitation_sent_at: DateTime.utc_now()
        )

      assert {:ok, expired} = Provider.expire_staff_invitation(staff)
      assert expired.invitation_status == :expired
    end

    test "transitions :sent staff member to :expired with string ID" do
      staff =
        ProviderFixtures.staff_member_fixture(
          email: "expiry2@example.com",
          invitation_status: :sent,
          invitation_token_hash: :crypto.hash(:sha256, "token2"),
          invitation_sent_at: DateTime.utc_now()
        )

      assert {:ok, expired} = Provider.expire_staff_invitation(staff.id)
      assert expired.invitation_status == :expired
    end

    test "returns error for non-existent ID" do
      assert {:error, :not_found} = Provider.expire_staff_invitation(Ecto.UUID.generate())
    end

    test "returns error for invalid transition from :accepted" do
      staff =
        ProviderFixtures.staff_member_fixture(
          email: "accepted@example.com",
          invitation_status: :accepted
        )

      assert {:error, :invalid_invitation_transition} = Provider.expire_staff_invitation(staff)
    end
  end
end
