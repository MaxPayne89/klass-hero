defmodule KlassHero.Family.ChildrenTest do
  @moduledoc """
  Context tests for child CRUD and queries through the `KlassHero.Family`
  public API, exercised against the real sandbox database.
  """

  use KlassHero.DataCase, async: true

  import KlassHero.Factory

  alias KlassHero.Family
  alias KlassHero.Family.Child
  alias KlassHero.Family.ChildGuardian

  @valid_attrs %{
    first_name: "Emma",
    last_name: "Smith",
    date_of_birth: ~D[2015-06-15]
  }

  defp parent, do: insert(:parent_profile_schema)

  describe "create_child/1" do
    test "creates a child and returns the persisted struct" do
      attrs = Map.merge(@valid_attrs, %{emergency_contact: "555-1234", allergies: "Peanuts"})

      assert {:ok, %Child{} = child} = Family.create_child(attrs)
      assert is_binary(child.id)
      assert child.first_name == "Emma"
      assert child.allergies == "Peanuts"
      assert %DateTime{} = child.inserted_at
    end

    test "autogenerates a UUID id" do
      assert {:ok, child} = Family.create_child(@valid_attrs)
      assert byte_size(child.id) == 36
    end

    test "links a guardian when :parent_id is given" do
      parent = parent()

      assert {:ok, %Child{} = child} = Family.create_child(Map.put(@valid_attrs, :parent_id, parent.id))

      link = Repo.get_by!(ChildGuardian, child_id: child.id, guardian_id: parent.id)
      assert link.relationship == "parent"
      assert link.is_primary == true
    end

    test "returns a changeset error for a future date of birth" do
      attrs = %{@valid_attrs | date_of_birth: Date.add(Date.utc_today(), 30)}
      assert {:error, %Ecto.Changeset{}} = Family.create_child(attrs)
    end

    test "returns a changeset error for a blank first name" do
      assert {:error, %Ecto.Changeset{}} = Family.create_child(%{@valid_attrs | first_name: ""})
    end

    test "rolls back the child when the guardian link fails" do
      count_before = Repo.aggregate(Child, :count)

      assert {:error, %Ecto.Changeset{}} =
               Family.create_child(Map.put(@valid_attrs, :parent_id, Ecto.UUID.generate()))

      assert Repo.aggregate(Child, :count) == count_before
    end
  end

  describe "get_child_by_id/1" do
    test "returns an existing child" do
      {:ok, created} = Family.create_child(@valid_attrs)

      assert {:ok, %Child{} = found} = Family.get_child_by_id(created.id)
      assert found.id == created.id
    end

    test "returns :not_found for a missing id" do
      assert {:error, :not_found} = Family.get_child_by_id(Ecto.UUID.generate())
    end

    test "returns :not_found for an invalid UUID" do
      assert {:error, :not_found} = Family.get_child_by_id("invalid-uuid")
    end
  end

  describe "get_children/1" do
    test "lists a guardian's children ordered by name" do
      parent = parent()
      {:ok, _zoe} = Family.create_child(Map.merge(@valid_attrs, %{first_name: "Zoe", parent_id: parent.id}))
      {:ok, _ana} = Family.create_child(Map.merge(@valid_attrs, %{first_name: "Ana", parent_id: parent.id}))

      assert ["Ana", "Zoe"] = Enum.map(Family.get_children(parent.id), & &1.first_name)
    end

    test "returns [] when the guardian has no children" do
      assert Family.get_children(parent().id) == []
    end

    test "scopes to the given guardian only" do
      p1 = parent()
      p2 = parent()
      {:ok, _} = Family.create_child(Map.merge(@valid_attrs, %{first_name: "Mine", parent_id: p1.id}))
      {:ok, _} = Family.create_child(Map.merge(@valid_attrs, %{first_name: "Theirs", parent_id: p2.id}))

      assert ["Mine"] = Enum.map(Family.get_children(p1.id), & &1.first_name)
    end
  end

  describe "child_belongs_to_parent?/2" do
    test "true when the guardian link exists" do
      parent = parent()
      {:ok, child} = Family.create_child(Map.put(@valid_attrs, :parent_id, parent.id))

      assert Family.child_belongs_to_parent?(child.id, parent.id)
    end

    test "false when there is no link" do
      {:ok, child} = Family.create_child(@valid_attrs)
      refute Family.child_belongs_to_parent?(child.id, Ecto.UUID.generate())
    end
  end

  describe "update_child/2" do
    test "updates fields" do
      {:ok, child} = Family.create_child(@valid_attrs)

      assert {:ok, %Child{} = updated} =
               Family.update_child(child.id, %{first_name: "Emily", allergies: "Peanuts"})

      assert updated.first_name == "Emily"
      assert updated.allergies == "Peanuts"
    end

    test "returns :not_found for a missing child" do
      assert {:error, :not_found} = Family.update_child(Ecto.UUID.generate(), %{first_name: "X"})
    end

    test "returns :not_found for an invalid UUID" do
      assert {:error, :not_found} = Family.update_child("invalid-uuid", %{first_name: "X"})
    end

    test "returns a changeset error for invalid data" do
      {:ok, child} = Family.create_child(@valid_attrs)
      assert {:error, %Ecto.Changeset{}} = Family.update_child(child.id, %{first_name: ""})
    end
  end

  describe "delete_child/1" do
    test "deletes an existing child" do
      {:ok, child} = Family.create_child(@valid_attrs)

      assert :ok = Family.delete_child(child.id)
      assert {:error, :not_found} = Family.get_child_by_id(child.id)
    end

    test "returns :not_found for a missing child" do
      assert {:error, :not_found} = Family.delete_child(Ecto.UUID.generate())
    end
  end
end
