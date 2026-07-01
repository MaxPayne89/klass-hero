defmodule KlassHero.Enrollment.CheckEnrollmentTest do
  use KlassHero.DataCase, async: true

  import KlassHero.Factory

  describe "execute/2" do
    test "returns true for a pending enrollment" do
      {child, parent} = insert_child_with_guardian()
      program = insert(:program_schema)

      insert(:enrollment_schema,
        program_id: program.id,
        child_id: child.id,
        parent_id: parent.id,
        status: "pending"
      )

      assert KlassHero.Enrollment.enrolled?(program.id, parent.identity_id) == true
    end

    test "returns true for a confirmed enrollment" do
      {child, parent} = insert_child_with_guardian()
      program = insert(:program_schema)

      insert(:enrollment_schema,
        program_id: program.id,
        child_id: child.id,
        parent_id: parent.id,
        status: "confirmed"
      )

      assert KlassHero.Enrollment.enrolled?(program.id, parent.identity_id) == true
    end

    test "returns false for a cancelled enrollment" do
      {child, parent} = insert_child_with_guardian()
      program = insert(:program_schema)

      insert(:enrollment_schema,
        program_id: program.id,
        child_id: child.id,
        parent_id: parent.id,
        status: "cancelled"
      )

      assert KlassHero.Enrollment.enrolled?(program.id, parent.identity_id) == false
    end

    test "returns false for a completed enrollment" do
      {child, parent} = insert_child_with_guardian()
      program = insert(:program_schema)

      insert(:enrollment_schema,
        program_id: program.id,
        child_id: child.id,
        parent_id: parent.id,
        status: "completed"
      )

      assert KlassHero.Enrollment.enrolled?(program.id, parent.identity_id) == false
    end

    test "returns false when no enrollment exists for the identity" do
      program = insert(:program_schema)
      unknown_identity_id = Ecto.UUID.generate()

      assert KlassHero.Enrollment.enrolled?(program.id, unknown_identity_id) == false
    end

    test "returns false when enrollment exists for a different program" do
      {child, parent} = insert_child_with_guardian()
      program_a = insert(:program_schema)
      program_b = insert(:program_schema)

      insert(:enrollment_schema,
        program_id: program_a.id,
        child_id: child.id,
        parent_id: parent.id,
        status: "confirmed"
      )

      assert KlassHero.Enrollment.enrolled?(program_b.id, parent.identity_id) == false
    end
  end
end
