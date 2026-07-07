defmodule KlassHero.Family.ParentProfilesTest do
  @moduledoc """
  Context tests for parent-profile CRUD and queries through the `KlassHero.Family`
  public API, exercised against the real sandbox database.
  """

  use KlassHero.DataCase, async: true

  import KlassHero.AccountsFixtures

  alias KlassHero.Family
  alias KlassHero.Family.ParentProfile

  # parents.identity_id has a FK to users, so create paths need a real user id.
  defp identity_id, do: unconfirmed_user_fixture(intended_roles: [:parent]).id

  describe "create_parent_profile/1" do
    test "creates a profile and returns the struct" do
      attrs = %{
        identity_id: identity_id(),
        display_name: "John Doe",
        phone: "+1234567890",
        location: "Berlin",
        notification_preferences: %{email: true, sms: false}
      }

      assert {:ok, %ParentProfile{} = profile} = Family.create_parent_profile(attrs)
      assert profile.identity_id == attrs.identity_id
      assert profile.display_name == "John Doe"
      assert %DateTime{} = profile.inserted_at
    end

    test "creates a profile with minimal fields" do
      assert {:ok, %ParentProfile{} = profile} =
               Family.create_parent_profile(%{identity_id: identity_id()})

      assert is_nil(profile.display_name)
    end

    test "returns :duplicate_resource when a profile already exists" do
      id = identity_id()

      assert {:ok, _} = Family.create_parent_profile(%{identity_id: id})
      assert {:error, :duplicate_resource} = Family.create_parent_profile(%{identity_id: id})
    end

    test "returns a changeset error when identity_id is missing" do
      assert {:error, %Ecto.Changeset{}} = Family.create_parent_profile(%{display_name: "No identity"})
    end
  end

  describe "get_parent_by_identity/1" do
    test "retrieves an existing profile" do
      id = identity_id()
      {:ok, created} = Family.create_parent_profile(%{identity_id: id, display_name: "Jane"})

      assert {:ok, %ParentProfile{} = found} = Family.get_parent_by_identity(id)
      assert found.id == created.id
      assert found.display_name == "Jane"
    end

    test "returns :not_found for an unknown identity" do
      assert {:error, :not_found} = Family.get_parent_by_identity(Ecto.UUID.generate())
    end
  end

  describe "has_parent_profile?/1" do
    test "true when a profile exists" do
      id = identity_id()
      {:ok, _} = Family.create_parent_profile(%{identity_id: id})

      assert Family.has_parent_profile?(id)
    end

    test "false when no profile exists" do
      refute Family.has_parent_profile?(Ecto.UUID.generate())
    end
  end

  describe "get_parents_by_ids/1" do
    test "returns profiles matching the given ids" do
      {:ok, p1} = Family.create_parent_profile(%{identity_id: identity_id()})
      {:ok, p2} = Family.create_parent_profile(%{identity_id: identity_id()})
      {:ok, _other} = Family.create_parent_profile(%{identity_id: identity_id()})

      ids = Family.get_parents_by_ids([p1.id, p2.id]) |> Enum.map(& &1.id) |> Enum.sort()
      assert ids == Enum.sort([p1.id, p2.id])
    end

    test "returns [] for empty input" do
      assert Family.get_parents_by_ids([]) == []
    end

    test "silently excludes non-existent ids" do
      {:ok, p} = Family.create_parent_profile(%{identity_id: identity_id()})

      result = Family.get_parents_by_ids([p.id, Ecto.UUID.generate()])
      assert Enum.map(result, & &1.id) == [p.id]
    end
  end
end
