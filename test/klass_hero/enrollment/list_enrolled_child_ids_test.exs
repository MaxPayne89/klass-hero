defmodule KlassHero.Enrollment.ListEnrolledChildIdsTest do
  use KlassHero.DataCase, async: true

  import KlassHero.Factory

  alias KlassHero.Enrollment

  describe "list_enrolled_child_ids/1" do
    test "returns child IDs for children with active enrollments in the program" do
      enrollment = insert(:enrollment_schema, status: "confirmed")

      result = Enrollment.list_enrolled_child_ids(enrollment.program_id)

      assert result == [enrollment.child_id]
    end

    test "returns empty list when no enrollments exist" do
      result = Enrollment.list_enrolled_child_ids(Ecto.UUID.generate())

      assert result == []
    end

    test "excludes children from other programs" do
      enrollment = insert(:enrollment_schema, status: "confirmed")
      _other_enrollment = insert(:enrollment_schema, status: "confirmed")

      result = Enrollment.list_enrolled_child_ids(enrollment.program_id)

      assert result == [enrollment.child_id]
    end

    test "excludes cancelled enrollments" do
      program = insert(:program_schema)
      {child_active, parent_active} = insert_child_with_guardian()
      {child_cancelled, parent_cancelled} = insert_child_with_guardian()

      confirmed_enrollment =
        insert(:enrollment_schema,
          program_id: program.id,
          child_id: child_active.id,
          parent_id: parent_active.id,
          status: "confirmed"
        )

      _cancelled_enrollment =
        insert(:enrollment_schema,
          program_id: program.id,
          child_id: child_cancelled.id,
          parent_id: parent_cancelled.id,
          status: "cancelled"
        )

      result = Enrollment.list_enrolled_child_ids(program.id)

      assert result == [confirmed_enrollment.child_id]
      refute child_cancelled.id in result
    end
  end
end
