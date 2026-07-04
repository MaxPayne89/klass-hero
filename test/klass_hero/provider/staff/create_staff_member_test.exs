defmodule KlassHero.Provider.Staff.CreateStaffMemberTest do
  use KlassHero.DataCase, async: true

  alias KlassHero.Provider
  alias KlassHero.Provider.PayRate
  alias KlassHero.ProviderFixtures

  setup do
    provider = ProviderFixtures.provider_profile_fixture()
    %{provider_id: provider.id}
  end

  describe "execute/1" do
    test "creates a staff member with required fields only", %{provider_id: provider_id} do
      attrs = %{provider_id: provider_id, first_name: "Alice", last_name: "Smith"}

      assert {:ok, staff} = Provider.create_staff_member(attrs)
      assert staff.provider_id == provider_id
      assert staff.first_name == "Alice"
      assert staff.last_name == "Smith"
      assert staff.active == true
      assert staff.tags == []
      assert staff.qualifications == []
      assert is_binary(staff.id)
    end

    test "creates a staff member with all optional fields", %{provider_id: provider_id} do
      attrs = %{
        provider_id: provider_id,
        first_name: "Bob",
        last_name: "Jones",
        role: "Head Coach",
        email: "bob@example.com",
        bio: "Experienced coach",
        headshot_url: "https://example.com/bob.jpg",
        tags: ["sports"],
        qualifications: ["First Aid", "UEFA B License"],
        active: false
      }

      assert {:ok, staff, _raw_token} = Provider.create_staff_member(attrs)
      assert staff.role == "Head Coach"
      assert staff.email == "bob@example.com"
      assert staff.bio == "Experienced coach"
      assert staff.headshot_url == "https://example.com/bob.jpg"
      assert staff.tags == ["sports"]
      assert staff.qualifications == ["First Aid", "UEFA B License"]
      assert staff.active == false
    end

    test "ignores smuggled linkage fields — generic create is never born linked", %{
      provider_id: provider_id
    } do
      attrs = %{
        :provider_id => provider_id,
        :first_name => "Mallory",
        :last_name => "Attacker",
        :user_id => Ecto.UUID.generate(),
        "user_id" => Ecto.UUID.generate(),
        :invitation_status => :accepted
      }

      assert {:ok, staff} = Provider.create_staff_member(attrs)
      assert is_nil(staff.user_id)
      refute staff.invitation_status == :accepted
    end

    test "returns validation error when first_name is empty", %{provider_id: provider_id} do
      attrs = %{provider_id: provider_id, first_name: "", last_name: "Smith"}

      assert {:error, {:validation_error, errors}} = Provider.create_staff_member(attrs)
      assert is_list(errors)
      assert Enum.any?(errors, &String.contains?(&1, "First name"))
    end

    test "returns validation error when last_name is empty", %{provider_id: provider_id} do
      attrs = %{provider_id: provider_id, first_name: "Alice", last_name: ""}

      assert {:error, {:validation_error, errors}} = Provider.create_staff_member(attrs)
      assert Enum.any?(errors, &String.contains?(&1, "Last name"))
    end

    test "returns validation error for invalid tag", %{provider_id: provider_id} do
      attrs = %{
        provider_id: provider_id,
        first_name: "Alice",
        last_name: "Smith",
        tags: ["invalid-category"]
      }

      assert {:error, {:validation_error, errors}} = Provider.create_staff_member(attrs)
      assert Enum.any?(errors, &String.contains?(&1, "Invalid tags"))
    end

    test "returns validation error when email format is invalid", %{provider_id: provider_id} do
      attrs = %{
        provider_id: provider_id,
        first_name: "Alice",
        last_name: "Smith",
        email: "not-an-email"
      }

      assert {:error, {:validation_error, errors}} = Provider.create_staff_member(attrs)
      assert Enum.any?(errors, &String.contains?(&1, "Email"))
    end

    test "persists the staff member to the database", %{provider_id: provider_id} do
      attrs = %{provider_id: provider_id, first_name: "Dave", last_name: "Brown"}

      assert {:ok, staff} = Provider.create_staff_member(attrs)

      assert {:ok, fetched} = Provider.get_staff_member(staff.id)
      assert fetched.id == staff.id
      assert fetched.first_name == "Dave"
    end

    test "creates a staff member with an hourly pay_rate", %{provider_id: provider_id} do
      {:ok, pay_rate} = PayRate.hourly(Decimal.new("25.00"))

      attrs = %{
        provider_id: provider_id,
        first_name: "Ivy",
        last_name: "Pay",
        pay_rate: pay_rate
      }

      assert {:ok, staff} = Provider.create_staff_member(attrs)
      assert staff.pay_rate.type == :hourly
      assert Decimal.equal?(staff.pay_rate.money.amount, Decimal.new("25.00"))
      assert staff.pay_rate.money.currency == :EUR
    end

    test "defaults pay_rate to nil when not provided", %{provider_id: provider_id} do
      attrs = %{provider_id: provider_id, first_name: "Ken", last_name: "Norate"}

      assert {:ok, staff} = Provider.create_staff_member(attrs)
      assert is_nil(staff.pay_rate)
    end
  end
end
