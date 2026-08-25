defmodule KlassHero.Enrollment.ListParentEnrollmentsTest do
  use KlassHero.DataCase, async: true

  import KlassHero.Factory

  alias KlassHero.Enrollment.Enrollment

  describe "execute/1" do
    test "returns all enrollments for parent" do
      parent = insert(:parent_profile_schema)
      {child1, _parent} = insert_child_with_guardian(parent: parent)
      {child2, _parent} = insert_child_with_guardian(parent: parent)

      enrollment1 = insert(:enrollment_schema, parent_id: parent.id, child_id: child1.id)

      enrollment2 =
        insert(:enrollment_schema, parent_id: parent.id, child_id: child2.id, status: "confirmed")

      _other = insert(:enrollment_schema)

      enrollments = KlassHero.Enrollment.list_parent_enrollments(parent.id)

      assert length(enrollments) == 2
      ids = Enum.map(enrollments, & &1.id)
      assert to_string(enrollment1.id) in ids
      assert to_string(enrollment2.id) in ids
    end

    test "returns domain entities" do
      enrollment_schema = insert(:enrollment_schema)

      [enrollment] = KlassHero.Enrollment.list_parent_enrollments(enrollment_schema.parent_id)

      assert %Enrollment{} = enrollment
      assert enrollment.status == enrollment_schema.status
      assert enrollment.id == enrollment_schema.id
    end

    test "returns enrollments ordered by enrolled_at descending" do
      parent = insert(:parent_profile_schema)
      {child, _parent} = insert_child_with_guardian(parent: parent)

      old =
        insert(:enrollment_schema,
          parent_id: parent.id,
          child_id: child.id,
          enrolled_at: ~U[2025-01-10 10:00:00Z]
        )

      recent =
        insert(:enrollment_schema,
          parent_id: parent.id,
          child_id: child.id,
          enrolled_at: ~U[2025-01-20 10:00:00Z],
          status: "confirmed"
        )

      middle =
        insert(:enrollment_schema,
          parent_id: parent.id,
          child_id: child.id,
          enrolled_at: ~U[2025-01-15 10:00:00Z],
          status: "completed"
        )

      enrollments = KlassHero.Enrollment.list_parent_enrollments(parent.id)

      ids = Enum.map(enrollments, & &1.id)
      assert ids == [to_string(recent.id), to_string(middle.id), to_string(old.id)]
    end

    test "returns empty list when no enrollments" do
      parent = insert(:parent_profile_schema)

      assert KlassHero.Enrollment.list_parent_enrollments(parent.id) == []
    end

    test "returns empty list for non-existent parent" do
      assert KlassHero.Enrollment.list_parent_enrollments(Ecto.UUID.generate()) == []
    end

    test "includes all enrollment statuses" do
      parent = insert(:parent_profile_schema)
      {child, _parent} = insert_child_with_guardian(parent: parent)

      insert(:enrollment_schema, parent_id: parent.id, child_id: child.id, status: "pending")
      insert(:enrollment_schema, parent_id: parent.id, child_id: child.id, status: "confirmed")
      insert(:enrollment_schema, parent_id: parent.id, child_id: child.id, status: "completed")
      insert(:enrollment_schema, parent_id: parent.id, child_id: child.id, status: "cancelled")

      enrollments = KlassHero.Enrollment.list_parent_enrollments(parent.id)

      assert length(enrollments) == 4
      statuses = Enum.map(enrollments, & &1.status)
      assert :pending in statuses
      assert :confirmed in statuses
      assert :completed in statuses
      assert :cancelled in statuses
    end
  end
end
