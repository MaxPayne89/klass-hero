defmodule KlassHero.FamilyTest do
  @moduledoc """
  Integration tests for the Family context public API.

  Tests the complete flow from context facade through use cases to repositories.
  """

  use KlassHero.DataCase, async: true

  alias KlassHero.Family
  alias KlassHero.Family.Child
  alias KlassHero.Family.ParentProfile

  # Parent Profile Functions

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

    test "returns a changeset error for invalid attrs" do
      assert {:error, %Ecto.Changeset{}} = Family.create_parent_profile(%{identity_id: ""})
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

  # Children Functions

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

  # The batch lookups below were only exercised through Enrollment's ChildInfoACL and
  # ParentInfoACL until those folded into direct facade calls (#1269). Family owns them,
  # so the coverage lives here.

  describe "get_children_by_ids/1" do
    test "returns the children for the given ids" do
      parent = create_parent_for_children()

      emma =
        create_child_linked_to_parent(parent, %{first_name: "Emma", last_name: "Smith", date_of_birth: ~D[2015-06-15]})

      liam =
        create_child_linked_to_parent(parent, %{first_name: "Liam", last_name: "Jones", date_of_birth: ~D[2016-01-20]})

      result = Family.get_children_by_ids([emma.id, liam.id])

      assert result |> Enum.map(& &1.first_name) |> Enum.sort() == ["Emma", "Liam"]
    end

    test "returns an empty list for empty input" do
      assert Family.get_children_by_ids([]) == []
    end

    test "silently excludes ids with no matching child" do
      parent = create_parent_for_children()

      child =
        create_child_linked_to_parent(parent, %{first_name: "Emma", last_name: "Smith", date_of_birth: ~D[2015-06-15]})

      assert [%Child{} = only] = Family.get_children_by_ids([child.id, Ecto.UUID.generate()])
      assert only.id == child.id
    end

    # Callers pass ids straight through from client input, so a malformed one must not
    # blow up the query — Ecto.UUID.dump/1 filters it out before the `in` clause.
    test "drops ids that are not valid UUIDs" do
      assert Family.get_children_by_ids(["not-a-uuid"]) == []
    end
  end

  describe "get_parents_by_ids/1" do
    test "returns the parent profiles for the given ids" do
      parent = create_parent_for_children()

      assert [%ParentProfile{} = result] = Family.get_parents_by_ids([parent.id])
      assert result.id == parent.id
      assert result.identity_id == parent.identity_id
    end

    test "returns an empty list for empty input" do
      assert Family.get_parents_by_ids([]) == []
    end

    test "silently excludes ids with no matching parent" do
      parent = create_parent_for_children()

      assert [%ParentProfile{} = only] = Family.get_parents_by_ids([parent.id, Ecto.UUID.generate()])
      assert only.id == parent.id
    end

    test "drops ids that are not valid UUIDs" do
      assert Family.get_parents_by_ids(["not-a-uuid"]) == []
    end
  end
end
