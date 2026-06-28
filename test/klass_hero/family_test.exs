defmodule KlassHero.FamilyTest do
  @moduledoc """
  Integration tests for the Family context public API.

  Tests the complete flow from context facade through use cases to repositories.
  """

  use KlassHero.DataCase, async: true

  alias KlassHero.Family
  alias KlassHero.Family.Child
  alias KlassHero.Family.Domain.Models.ParentProfile

  # ============================================================================
  # Parent Profile Functions
  # ============================================================================

  describe "create_parent_profile/1" do
    test "creates parent profile through public API" do
      user = KlassHero.AccountsFixtures.unconfirmed_user_fixture(intended_roles: [:parent])

      attrs = %{
        identity_id: user.id,
        display_name: "John Doe"
      }

      assert {:ok, %ParentProfile{} = profile} = Family.create_parent_profile(attrs)
      assert profile.identity_id == attrs.identity_id
      assert profile.display_name == "John Doe"
    end

    test "returns validation error for invalid attrs" do
      attrs = %{identity_id: ""}

      assert {:error, {:validation_error, errors}} = Family.create_parent_profile(attrs)
      assert "Identity ID cannot be empty" in errors
    end

    test "returns duplicate error when profile exists" do
      user = KlassHero.AccountsFixtures.unconfirmed_user_fixture(intended_roles: [:parent])
      attrs = %{identity_id: user.id}

      assert {:ok, _} = Family.create_parent_profile(attrs)
      assert {:error, :duplicate_resource} = Family.create_parent_profile(attrs)
    end
  end

  describe "get_parent_by_identity/1" do
    test "retrieves existing parent profile" do
      user = KlassHero.AccountsFixtures.unconfirmed_user_fixture(intended_roles: [:parent])
      {:ok, created} = Family.create_parent_profile(%{identity_id: user.id})

      assert {:ok, %ParentProfile{} = retrieved} = Family.get_parent_by_identity(user.id)
      assert retrieved.id == created.id
    end

    test "returns not_found for non-existent profile" do
      assert {:error, :not_found} = Family.get_parent_by_identity(Ecto.UUID.generate())
    end
  end

  describe "has_parent_profile?/1" do
    test "returns true when profile exists" do
      user = KlassHero.AccountsFixtures.unconfirmed_user_fixture(intended_roles: [:parent])
      {:ok, _} = Family.create_parent_profile(%{identity_id: user.id})

      assert Family.has_parent_profile?(user.id) == true
    end

    test "returns false when profile does not exist" do
      assert Family.has_parent_profile?(Ecto.UUID.generate()) == false
    end
  end

  # ============================================================================
  # Children Functions
  # ============================================================================

  defp create_parent_for_children do
    user = KlassHero.AccountsFixtures.unconfirmed_user_fixture(intended_roles: [:parent])
    {:ok, parent} = Family.create_parent_profile(%{identity_id: user.id})
    parent
  end

  defp create_child_linked_to_parent(parent, child_attrs) do
    {:ok, child} = Family.create_child(Map.put(child_attrs, :parent_id, parent.id))
    child
  end

  describe "get_children/1" do
    test "returns children for parent" do
      parent = create_parent_for_children()

      create_child_linked_to_parent(parent, %{
        first_name: "Emma",
        last_name: "Smith",
        date_of_birth: ~D[2015-06-15]
      })

      children = Family.get_children(parent.id)

      assert length(children) == 1
      assert Enum.at(children, 0).first_name == "Emma"
    end

    test "returns empty list when no children" do
      parent = create_parent_for_children()
      children = Family.get_children(parent.id)

      assert children == []
    end
  end

  describe "change_child/0" do
    test "returns a valid changeset for empty attrs" do
      changeset = Family.change_child()
      assert %Ecto.Changeset{} = changeset
    end
  end

  describe "change_child/1 with attrs" do
    test "returns changeset with provided values" do
      changeset = Family.change_child(%{"first_name" => "Emma", "last_name" => "Smith"})
      assert %Ecto.Changeset{} = changeset
      assert Ecto.Changeset.get_field(changeset, :first_name) == "Emma"
      assert Ecto.Changeset.get_field(changeset, :last_name) == "Smith"
    end
  end

  describe "change_child/2 with Child struct" do
    test "returns changeset pre-filled from domain struct" do
      child = %Child{
        id: Ecto.UUID.generate(),
        first_name: "Emma",
        last_name: "Smith",
        date_of_birth: ~D[2015-06-15],
        emergency_contact: nil,
        support_needs: nil,
        allergies: nil
      }

      changeset = Family.change_child(child, %{})
      assert %Ecto.Changeset{} = changeset
      assert Ecto.Changeset.get_field(changeset, :first_name) == "Emma"
      assert Ecto.Changeset.get_field(changeset, :last_name) == "Smith"
      assert Ecto.Changeset.get_field(changeset, :date_of_birth) == ~D[2015-06-15]
    end

    test "returns changeset with updated attrs from domain struct" do
      child = %Child{
        id: Ecto.UUID.generate(),
        first_name: "Emma",
        last_name: "Smith",
        date_of_birth: ~D[2015-06-15],
        emergency_contact: nil,
        support_needs: nil,
        allergies: nil
      }

      changeset = Family.change_child(child, %{"first_name" => "Updated"})
      assert %Ecto.Changeset{} = changeset
      assert Ecto.Changeset.get_field(changeset, :first_name) == "Updated"
      assert Ecto.Changeset.get_field(changeset, :last_name) == "Smith"
    end
  end

  describe "get_child_by_id/1" do
    test "retrieves existing child" do
      parent = create_parent_for_children()

      child =
        create_child_linked_to_parent(parent, %{
          first_name: "Emma",
          last_name: "Smith",
          date_of_birth: ~D[2015-06-15]
        })

      assert {:ok, %Child{} = retrieved} = Family.get_child_by_id(child.id)
      assert retrieved.id == child.id
      assert retrieved.first_name == "Emma"
    end

    test "returns not_found for non-existent child" do
      assert {:error, :not_found} = Family.get_child_by_id(Ecto.UUID.generate())
    end
  end
end
