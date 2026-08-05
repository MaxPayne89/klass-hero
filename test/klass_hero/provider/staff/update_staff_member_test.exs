defmodule KlassHero.Provider.Staff.UpdateStaffMemberTest do
  use KlassHero.DataCase, async: true

  alias KlassHero.Provider
  alias KlassHero.Provider.PayRate
  alias KlassHero.ProviderFixtures

  setup do
    provider = ProviderFixtures.provider_profile_fixture()

    staff =
      ProviderFixtures.staff_member_fixture(
        provider_id: provider.id,
        first_name: "Alice",
        last_name: "Smith"
      )

    %{staff: staff}
  end

  describe "update_staff_member/3" do
    test "updates first_name", %{staff: staff} do
      assert {:ok, updated} = Provider.update_staff_member(staff.provider_id, staff.id, %{first_name: "Alicia"})
      assert updated.first_name == "Alicia"
      assert updated.last_name == "Smith"
      assert updated.id == staff.id
    end

    test "updates role, email, and bio", %{staff: staff} do
      attrs = %{role: "Head Coach", email: "alice@example.com", bio: "10 years experience"}
      assert {:ok, updated} = Provider.update_staff_member(staff.provider_id, staff.id, attrs)
      assert updated.role == "Head Coach"
      assert updated.email == "alice@example.com"
      assert updated.bio == "10 years experience"
    end

    test "updates tags with valid category", %{staff: staff} do
      assert {:ok, updated} = Provider.update_staff_member(staff.provider_id, staff.id, %{tags: ["sports", "arts"]})
      assert updated.tags == ["sports", "arts"]
    end

    test "updates qualifications", %{staff: staff} do
      assert {:ok, updated} =
               Provider.update_staff_member(staff.provider_id, staff.id, %{qualifications: ["First Aid"]})

      assert updated.qualifications == ["First Aid"]
    end

    test "ignores :active — ending an employment link is its own operation", %{staff: staff} do
      # The profile-edit path must not be a back door into deactivation: it stages
      # no event and clears no lead-instructor flag, so a staff member deactivated
      # this way would leave every consequence unapplied (#1237).
      assert {:ok, updated} = Provider.update_staff_member(staff.provider_id, staff.id, %{active: false})

      assert updated.active, "update_staff_member/3 must not flip :active"
    end

    test "preserves unmodified fields", %{staff: staff} do
      original_provider_id = staff.provider_id

      assert {:ok, updated} = Provider.update_staff_member(staff.provider_id, staff.id, %{role: "Assistant"})
      assert updated.provider_id == original_provider_id
      assert updated.first_name == staff.first_name
      assert updated.last_name == staff.last_name
    end

    test "returns :not_found for non-existent staff member" do
      fake_id = Ecto.UUID.generate()

      assert {:error, :not_found} =
               Provider.update_staff_member(Ecto.UUID.generate(), fake_id, %{first_name: "Bob"})
    end

    test "returns :not_found and leaves the row unchanged when another provider owns it", %{
      staff: staff
    } do
      other = ProviderFixtures.provider_profile_fixture()

      # IDOR guard: a foreign provider_id must not update, and is indistinguishable
      # from a genuine miss (no existence leak).
      assert {:error, :not_found} =
               Provider.update_staff_member(other.id, staff.id, %{first_name: "Hijacked"})

      assert {:ok, unchanged} = Provider.get_staff_member(staff.id)
      assert unchanged.first_name == "Alice"
    end

    test "returns validation error when first_name is set to empty string", %{staff: staff} do
      assert {:error, {:validation_error, errors}} =
               Provider.update_staff_member(staff.provider_id, staff.id, %{first_name: ""})

      assert Enum.any?(errors, &String.contains?(&1, "First name"))
    end

    test "returns validation error for invalid tag", %{staff: staff} do
      assert {:error, {:validation_error, errors}} =
               Provider.update_staff_member(staff.provider_id, staff.id, %{tags: ["not-a-real-category"]})

      assert Enum.any?(errors, &String.contains?(&1, "Invalid tags"))
    end

    test "persists changes to the database", %{staff: staff} do
      assert {:ok, _updated} = Provider.update_staff_member(staff.provider_id, staff.id, %{role: "Director"})

      assert {:ok, fetched} = Provider.get_staff_member(staff.id)
      assert fetched.role == "Director"
    end

    test "ignores fields not in the allowed list", %{staff: staff} do
      attrs = %{first_name: "Bob", provider_id: Ecto.UUID.generate()}
      assert {:ok, updated} = Provider.update_staff_member(staff.provider_id, staff.id, attrs)
      assert updated.first_name == "Bob"
      assert updated.provider_id == staff.provider_id
    end

    test "sets an hourly pay_rate", %{staff: staff} do
      {:ok, pay_rate} = PayRate.hourly(Decimal.new("30.00"))

      assert {:ok, updated} = Provider.update_staff_member(staff.provider_id, staff.id, %{pay_rate: pay_rate})
      assert updated.pay_rate.type == :hourly
      assert Decimal.equal?(updated.pay_rate.money.amount, Decimal.new("30.00"))
    end

    test "sets a per_session pay_rate", %{staff: staff} do
      {:ok, pay_rate} = PayRate.per_session(Decimal.new("80.00"))

      assert {:ok, updated} = Provider.update_staff_member(staff.provider_id, staff.id, %{pay_rate: pay_rate})
      assert updated.pay_rate.type == :per_session
    end

    test "clears pay_rate when set to nil", %{staff: staff} do
      {:ok, pay_rate} = PayRate.hourly(Decimal.new("25.00"))
      {:ok, staff_with_rate} = Provider.update_staff_member(staff.provider_id, staff.id, %{pay_rate: pay_rate})
      assert staff_with_rate.pay_rate

      assert {:ok, cleared} = Provider.update_staff_member(staff.provider_id, staff.id, %{pay_rate: nil})
      assert is_nil(cleared.pay_rate)
    end

    test "sets an hourly pay_rate from flat rate_* params", %{staff: staff} do
      attrs = %{rate_type: "hourly", rate_amount: "30.00", rate_currency: "EUR"}

      assert {:ok, updated} = Provider.update_staff_member(staff.provider_id, staff.id, attrs)
      assert updated.pay_rate.type == :hourly
      assert Decimal.equal?(updated.pay_rate.money.amount, Decimal.new("30.00"))
      assert updated.pay_rate.money.currency == :EUR
    end

    test "clears pay_rate from empty flat params", %{staff: staff} do
      {:ok, pay_rate} = PayRate.hourly(Decimal.new("25.00"))
      {:ok, seeded} = Provider.update_staff_member(staff.provider_id, staff.id, %{pay_rate: pay_rate})
      assert seeded.pay_rate

      attrs = %{rate_type: nil, rate_amount: nil, rate_currency: nil}
      assert {:ok, cleared} = Provider.update_staff_member(staff.provider_id, staff.id, attrs)
      assert is_nil(cleared.pay_rate)
    end
  end
end
