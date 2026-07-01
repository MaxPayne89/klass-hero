defmodule KlassHero.Enrollment.ListEnrolledIdentityIdsTest do
  use KlassHero.DataCase, async: true

  import KlassHero.Factory

  describe "execute/1" do
    test "returns identity_ids of actively enrolled parents" do
      {child, parent} = insert_child_with_guardian()
      program = insert(:program_schema)

      insert(:enrollment_schema,
        program_id: program.id,
        child_id: child.id,
        parent_id: parent.id,
        status: "confirmed"
      )

      ids = KlassHero.Enrollment.list_enrolled_identity_ids(program.id)

      assert parent.identity_id in ids
      assert length(ids) == 1
    end

    test "includes pending enrollments" do
      {child, parent} = insert_child_with_guardian()
      program = insert(:program_schema)

      insert(:enrollment_schema,
        program_id: program.id,
        child_id: child.id,
        parent_id: parent.id,
        status: "pending"
      )

      ids = KlassHero.Enrollment.list_enrolled_identity_ids(program.id)

      assert parent.identity_id in ids
      assert length(ids) == 1
    end

    test "returns empty list when no active enrollments exist" do
      program = insert(:program_schema)

      assert KlassHero.Enrollment.list_enrolled_identity_ids(program.id) == []
    end

    test "excludes cancelled enrollments" do
      {child, parent} = insert_child_with_guardian()
      program = insert(:program_schema)

      insert(:enrollment_schema,
        program_id: program.id,
        child_id: child.id,
        parent_id: parent.id,
        status: "cancelled"
      )

      ids = KlassHero.Enrollment.list_enrolled_identity_ids(program.id)

      refute parent.identity_id in ids
    end

    test "excludes completed enrollments" do
      {child, parent} = insert_child_with_guardian()
      program = insert(:program_schema)

      insert(:enrollment_schema,
        program_id: program.id,
        child_id: child.id,
        parent_id: parent.id,
        status: "completed"
      )

      ids = KlassHero.Enrollment.list_enrolled_identity_ids(program.id)

      refute parent.identity_id in ids
    end

    test "returns distinct identity_id when the same parent has multiple active enrollments" do
      {child1, parent} = insert_child_with_guardian()
      {child2, _} = insert_child_with_guardian(parent: parent)
      program = insert(:program_schema)

      insert(:enrollment_schema,
        program_id: program.id,
        child_id: child1.id,
        parent_id: parent.id,
        status: "confirmed"
      )

      insert(:enrollment_schema,
        program_id: program.id,
        child_id: child2.id,
        parent_id: parent.id,
        status: "confirmed"
      )

      ids = KlassHero.Enrollment.list_enrolled_identity_ids(program.id)

      assert parent.identity_id in ids
      assert length(ids) == 1
    end

    test "does not include identity_ids from other programs" do
      {child, parent} = insert_child_with_guardian()
      program_a = insert(:program_schema)
      program_b = insert(:program_schema)

      insert(:enrollment_schema,
        program_id: program_a.id,
        child_id: child.id,
        parent_id: parent.id,
        status: "confirmed"
      )

      ids = KlassHero.Enrollment.list_enrolled_identity_ids(program_b.id)

      refute parent.identity_id in ids
    end
  end
end
