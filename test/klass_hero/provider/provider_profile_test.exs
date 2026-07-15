defmodule KlassHero.Provider.ProviderProfileTest do
  @moduledoc """
  Tests for the ProviderProfile domain entity.
  """

  use KlassHero.DataCase, async: true

  alias KlassHero.Provider.ProviderProfile

  describe "new/1 with valid attributes" do
    test "creates provider profile with all fields" do
      attrs = %{
        id: "550e8400-e29b-41d4-a716-446655440000",
        identity_id: "660e8400-e29b-41d4-a716-446655440001",
        business_name: "Kids Sports Academy",
        description: "Premier youth sports training",
        phone: "+1234567890",
        website: "https://example.com",
        address: "123 Main St",
        logo_url: "https://example.com/logo.png",
        categories: ["sports", "outdoor"]
      }

      assert {:ok, profile} = ProviderProfile.new(attrs)
      assert profile.id == attrs.id
      assert profile.identity_id == attrs.identity_id
      assert profile.business_name == "Kids Sports Academy"
      assert profile.verified == false
      assert profile.categories == ["sports", "outdoor"]
    end

    test "creates provider profile with only required fields" do
      attrs = %{
        id: "550e8400-e29b-41d4-a716-446655440000",
        identity_id: "660e8400-e29b-41d4-a716-446655440001",
        business_name: "My Business"
      }

      assert {:ok, profile} = ProviderProfile.new(attrs)
      assert profile.business_name == "My Business"
      assert profile.verified == false
      assert profile.categories == []
    end
  end

  describe "new/1 validation errors" do
    test "returns error when identity_id is empty" do
      attrs = %{
        id: "550e8400-e29b-41d4-a716-446655440000",
        identity_id: "",
        business_name: "My Business"
      }

      assert {:error, errors} = ProviderProfile.new(attrs)
      assert "Identity ID cannot be empty" in errors
    end

    test "returns error when business_name is empty" do
      attrs = %{
        id: "550e8400-e29b-41d4-a716-446655440000",
        identity_id: "uuid-123",
        business_name: ""
      }

      assert {:error, errors} = ProviderProfile.new(attrs)
      assert "Business name cannot be empty" in errors
    end

    test "returns error when business_name exceeds 200 characters" do
      attrs = %{
        id: "550e8400-e29b-41d4-a716-446655440000",
        identity_id: "uuid-123",
        business_name: String.duplicate("a", 201)
      }

      assert {:error, errors} = ProviderProfile.new(attrs)
      assert "Business name must be 200 characters or less" in errors
    end

    test "returns error when categories is not a list" do
      attrs = %{
        id: "550e8400-e29b-41d4-a716-446655440000",
        identity_id: "uuid-123",
        business_name: "My Business",
        categories: "sports"
      }

      assert {:error, errors} = ProviderProfile.new(attrs)
      assert "Categories must be a list" in errors
    end

    test "returns error when entity_type is not one of the known tracks" do
      attrs = %{
        id: "550e8400-e29b-41d4-a716-446655440000",
        identity_id: "uuid-123",
        business_name: "My Business",
        entity_type: :charity
      }

      assert {:error, errors} = ProviderProfile.new(attrs)
      assert "entity_type must be :individual or :business" in errors
    end
  end

  describe "responsible_person_change/3" do
    # {stored_name, stored_role, submitted_name, submitted_role, expected}
    @change_cases [
      {nil, nil, "Jane Smith", "Owner", :set},
      {"", "", "Jane Smith", "Owner", :set},
      {"Jane Smith", "Owner", "Jane Smith", "Owner", :unchanged},
      {"Jane Smith", "Owner", "Jane Smith ", "Owner", :unchanged},
      {"Jane Smith", "Owner", " Jane  Smith ", "Owner", :unchanged},
      {"Jane Smith", "Owner", "Jane Smtih", "Owner", :changed},
      {"Jane Smith", "Owner", "Jane Smith", "Director", :changed}
    ]

    for {stored_name, stored_role, name, role, expected} <- @change_cases do
      test "#{inspect({stored_name, stored_role})} vs #{inspect({name, role})} -> #{expected}" do
        profile = %ProviderProfile{
          responsible_person_name: unquote(stored_name),
          responsible_person_role: unquote(stored_role)
        }

        assert ProviderProfile.responsible_person_change(profile, unquote(name), unquote(role)) ==
                 unquote(expected)
      end
    end
  end

  describe "responsible_person_captured?/1" do
    # {name, role, expected} — "captured" gates the business identity session (ADR-0010):
    # name capture is mandatory before identity. Whitespace-only normalizes to blank.
    @captured_cases [
      {"Jane Smith", "Owner", true},
      {nil, nil, false},
      {"", "", false},
      {"Jane Smith", nil, false},
      {"Jane Smith", "", false},
      {nil, "Owner", false},
      {"   ", "Owner", false},
      {"Jane Smith", "   ", false}
    ]

    for {name, role, expected} <- @captured_cases do
      test "#{inspect({name, role})} -> #{expected}" do
        profile = %ProviderProfile{
          responsible_person_name: unquote(name),
          responsible_person_role: unquote(role)
        }

        assert ProviderProfile.responsible_person_captured?(profile) == unquote(expected),
               "responsible_person_captured? for #{inspect({unquote(name), unquote(role)})}"
      end
    end
  end

  describe "responsible_person_changeset/2" do
    test "casts only the two responsible-person fields and requires both" do
      changeset =
        ProviderProfile.responsible_person_changeset(%ProviderProfile{}, %{
          responsible_person_name: "Jane Smith",
          responsible_person_role: "Owner",
          business_name: "should be ignored"
        })

      assert changeset.valid?
      assert Ecto.Changeset.get_change(changeset, :responsible_person_name) == "Jane Smith"
      assert Ecto.Changeset.get_change(changeset, :responsible_person_role) == "Owner"
      assert Ecto.Changeset.get_change(changeset, :business_name) == nil
    end

    test "normalizes stored whitespace" do
      changeset =
        ProviderProfile.responsible_person_changeset(%ProviderProfile{}, %{
          responsible_person_name: " Jane  Smith ",
          responsible_person_role: "  Owner "
        })

      assert Ecto.Changeset.get_change(changeset, :responsible_person_name) == "Jane Smith"
      assert Ecto.Changeset.get_change(changeset, :responsible_person_role) == "Owner"
    end

    test "requires both fields" do
      changeset = ProviderProfile.responsible_person_changeset(%ProviderProfile{}, %{})

      refute changeset.valid?
      errors = errors_on(changeset)
      assert "can't be blank" in errors.responsible_person_name
      assert "can't be blank" in errors.responsible_person_role
    end
  end

  describe "business_registration_changeset/2 (B2, sole mutator)" do
    @valid_registration %{
      legal_business_name: "Acme Kids GmbH",
      registration_number: "HRB 12345",
      registration_country: "DE"
    }

    test "casts only the three registration fields, ignoring anything else" do
      changeset =
        ProviderProfile.business_registration_changeset(
          %ProviderProfile{},
          Map.put(@valid_registration, :business_name, "should be ignored")
        )

      assert changeset.valid?
      assert Ecto.Changeset.get_change(changeset, :legal_business_name) == "Acme Kids GmbH"
      assert Ecto.Changeset.get_change(changeset, :registration_number) == "HRB 12345"
      assert Ecto.Changeset.get_change(changeset, :registration_country) == "DE"
      assert Ecto.Changeset.get_change(changeset, :business_name) == nil
    end

    test "trims the legal name (collapsing internal runs) and the registration number" do
      changeset =
        ProviderProfile.business_registration_changeset(%ProviderProfile{}, %{
          legal_business_name: "  Acme   Kids  GmbH ",
          registration_number: "  HRB 12345 ",
          registration_country: "DE"
        })

      assert Ecto.Changeset.get_change(changeset, :legal_business_name) == "Acme Kids GmbH"
      assert Ecto.Changeset.get_change(changeset, :registration_number) == "HRB 12345"
    end

    test "requires all three fields" do
      changeset = ProviderProfile.business_registration_changeset(%ProviderProfile{}, %{})

      refute changeset.valid?
      errors = errors_on(changeset)
      assert "can't be blank" in errors.legal_business_name
      assert "can't be blank" in errors.registration_number
      assert "can't be blank" in errors.registration_country
    end

    # {country, valid?}
    @country_cases [{"DE", true}, {"GB", true}, {"OTHER", true}, {"de", false}, {"US", false}, {"", false}]

    for {country, valid?} <- @country_cases do
      test "registration_country #{inspect(country)} valid?: #{valid?}" do
        changeset =
          ProviderProfile.business_registration_changeset(
            %ProviderProfile{},
            %{@valid_registration | registration_country: unquote(country)}
          )

        assert changeset.valid? == unquote(valid?)

        if !unquote(valid?) do
          assert Keyword.has_key?(changeset.errors, :registration_country)
        end
      end
    end
  end

  describe "valid?/1" do
    test "returns true for valid provider profile" do
      {:ok, profile} =
        ProviderProfile.new(%{
          id: "550e8400-e29b-41d4-a716-446655440000",
          identity_id: "uuid-123",
          business_name: "My Business"
        })

      assert ProviderProfile.valid?(profile)
    end

    test "returns false for provider profile with empty business_name" do
      profile = %ProviderProfile{
        id: "550e8400-e29b-41d4-a716-446655440000",
        identity_id: "uuid-123",
        business_name: ""
      }

      refute ProviderProfile.valid?(profile)
    end
  end

  describe "changeset/2 (persistence gatekeeper)" do
    test "requires identity_id and business_name" do
      changeset = ProviderProfile.changeset(%ProviderProfile{}, %{})

      refute changeset.valid?
      errors = errors_on(changeset)
      assert "can't be blank" in errors.identity_id
      assert "can't be blank" in errors.business_name
    end

    test "rejects a non-https website" do
      changeset =
        ProviderProfile.changeset(%ProviderProfile{}, %{
          identity_id: Ecto.UUID.generate(),
          business_name: "Acme",
          website: "http://insecure.example.com"
        })

      refute changeset.valid?
      assert "must start with https://" in errors_on(changeset).website
    end
  end

  describe "profile_status as Ecto.Enum" do
    test "casts the string form to the atom value" do
      changeset =
        ProviderProfile.changeset(%ProviderProfile{}, %{
          identity_id: Ecto.UUID.generate(),
          business_name: "Acme",
          profile_status: "draft"
        })

      assert changeset.valid?
      assert Ecto.Changeset.get_field(changeset, :profile_status) == :draft
    end

    test "rejects an unknown status value" do
      changeset =
        ProviderProfile.changeset(%ProviderProfile{}, %{
          identity_id: Ecto.UUID.generate(),
          business_name: "Acme",
          profile_status: "archived"
        })

      refute changeset.valid?
      assert "is invalid" in errors_on(changeset).profile_status
    end

    test "defaults to :active on a bare struct" do
      assert %ProviderProfile{}.profile_status == :active
    end
  end
end
