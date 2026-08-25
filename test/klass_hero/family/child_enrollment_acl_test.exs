defmodule KlassHero.Family.ChildEnrollmentACLTest do
  use KlassHero.DataCase, async: true

  import Ecto.Query
  import KlassHero.Factory

  alias KlassHero.Family.ChildEnrollmentACL
  alias KlassHero.Repo

  describe "list_active_with_program_titles/1" do
    test "returns active enrollments with program titles" do
      program = insert(:program_schema, title: "Soccer Camp")
      {child, parent} = insert_child_with_guardian()

      insert(:enrollment_schema,
        program_id: program.id,
        child_id: child.id,
        parent_id: parent.id,
        status: "confirmed"
      )

      result = ChildEnrollmentACL.list_active_with_program_titles(child.id)

      assert [%{program_title: "Soccer Camp", status: "confirmed"}] = result
    end

    test "excludes cancelled and completed enrollments" do
      program1 = insert(:program_schema)
      program2 = insert(:program_schema)
      {child, parent} = insert_child_with_guardian()

      insert(:enrollment_schema,
        program_id: program1.id,
        child_id: child.id,
        parent_id: parent.id,
        status: "cancelled"
      )

      insert(:enrollment_schema,
        program_id: program2.id,
        child_id: child.id,
        parent_id: parent.id,
        status: "completed"
      )

      assert [] = ChildEnrollmentACL.list_active_with_program_titles(child.id)
    end

    test "returns empty list when no enrollments exist" do
      {child, _parent} = insert_child_with_guardian()

      assert [] = ChildEnrollmentACL.list_active_with_program_titles(child.id)
    end
  end

  describe "cancel_active_for_child/1" do
    test "cancels all active enrollments and returns count" do
      program1 = insert(:program_schema)
      program2 = insert(:program_schema)
      {child, parent} = insert_child_with_guardian()

      insert(:enrollment_schema,
        program_id: program1.id,
        child_id: child.id,
        parent_id: parent.id,
        status: "pending"
      )

      insert(:enrollment_schema,
        program_id: program2.id,
        child_id: child.id,
        parent_id: parent.id,
        status: "confirmed"
      )

      assert {:ok, 2} = ChildEnrollmentACL.cancel_active_for_child(child.id)

      # Verify they're cancelled with audit trail
      assert [] = ChildEnrollmentACL.list_active_with_program_titles(child.id)

      cancelled =
        Repo.all(
          from(e in "enrollments",
            where: e.child_id == type(^child.id, :binary_id),
            select: %{
              status: e.status,
              cancellation_reason: e.cancellation_reason,
              cancelled_at: e.cancelled_at
            }
          )
        )

      assert length(cancelled) == 2

      for enrollment <- cancelled do
        assert enrollment.status == "cancelled"
        assert enrollment.cancellation_reason == "child_deleted"
        # The ACL reads the row directly, so this side of the boundary is naive, not UTC.
        assert %NaiveDateTime{} = enrollment.cancelled_at
      end
    end

    test "does not cancel already cancelled enrollments" do
      program = insert(:program_schema)
      {child, parent} = insert_child_with_guardian()

      insert(:enrollment_schema,
        program_id: program.id,
        child_id: child.id,
        parent_id: parent.id,
        status: "cancelled"
      )

      assert {:ok, 0} = ChildEnrollmentACL.cancel_active_for_child(child.id)
    end

    test "returns zero count when no enrollments exist" do
      {child, _parent} = insert_child_with_guardian()

      assert {:ok, 0} = ChildEnrollmentACL.cancel_active_for_child(child.id)
    end
  end
end
