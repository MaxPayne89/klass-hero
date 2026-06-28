defmodule KlassHero.Family.ChildGuardianTest do
  use KlassHero.DataCase, async: true

  import KlassHero.Factory

  alias KlassHero.Family.ChildGuardian

  describe "changeset/2" do
    test "valid with all required fields" do
      attrs = %{
        child_id: Ecto.UUID.generate(),
        guardian_id: Ecto.UUID.generate(),
        relationship: "parent",
        is_primary: true
      }

      changeset = ChildGuardian.changeset(%ChildGuardian{}, attrs)
      assert changeset.valid?
    end

    test "requires child_id and guardian_id" do
      changeset =
        %ChildGuardian{}
        |> ChildGuardian.changeset(%{})
        |> Map.put(:action, :validate)

      refute changeset.valid?
      assert errors_on(changeset).child_id
      assert errors_on(changeset).guardian_id
    end

    test "validates relationship inclusion" do
      attrs = %{
        child_id: Ecto.UUID.generate(),
        guardian_id: Ecto.UUID.generate(),
        relationship: "invalid_value"
      }

      changeset =
        %ChildGuardian{}
        |> ChildGuardian.changeset(attrs)
        |> Map.put(:action, :validate)

      refute changeset.valid?
      assert errors_on(changeset).relationship
    end

    test "defaults relationship to parent and is_primary to false" do
      attrs = %{
        child_id: Ecto.UUID.generate(),
        guardian_id: Ecto.UUID.generate()
      }

      changeset = ChildGuardian.changeset(%ChildGuardian{}, attrs)
      assert Ecto.Changeset.get_field(changeset, :relationship) == "parent"
      assert Ecto.Changeset.get_field(changeset, :is_primary) == false
    end
  end

  describe "database constraints" do
    test "enforces one primary guardian per child at database level" do
      parent1 = insert(:parent_profile_schema)
      parent2 = insert(:parent_profile_schema)
      child = insert(:child_schema)

      {:ok, _} =
        Repo.insert(
          ChildGuardian.changeset(%ChildGuardian{}, %{
            child_id: child.id,
            guardian_id: parent1.id,
            relationship: "parent",
            is_primary: true
          })
        )

      {:error, changeset} =
        Repo.insert(
          ChildGuardian.changeset(%ChildGuardian{}, %{
            child_id: child.id,
            guardian_id: parent2.id,
            relationship: "guardian",
            is_primary: true
          })
        )

      assert "child already has a primary guardian" in errors_on(changeset).child_id
    end

    test "allows multiple non-primary guardians per child" do
      parent1 = insert(:parent_profile_schema)
      parent2 = insert(:parent_profile_schema)
      child = insert(:child_schema)

      {:ok, _} =
        Repo.insert(
          ChildGuardian.changeset(%ChildGuardian{}, %{
            child_id: child.id,
            guardian_id: parent1.id,
            relationship: "parent",
            is_primary: false
          })
        )

      {:ok, _} =
        Repo.insert(
          ChildGuardian.changeset(%ChildGuardian{}, %{
            child_id: child.id,
            guardian_id: parent2.id,
            relationship: "guardian",
            is_primary: false
          })
        )
    end
  end
end
