defmodule KlassHero.Family.PrepareChildDeletionTest do
  use KlassHero.DataCase, async: true

  import KlassHero.Factory

  alias KlassHero.Family

  describe "prepare_child_deletion/1" do
    test "returns :no_enrollments when child has no active enrollments" do
      {child, _parent} = insert_child_with_guardian()

      assert {:ok, :no_enrollments} = Family.prepare_child_deletion(child.id)
    end

    test "returns :has_enrollments with program titles when child has active enrollments" do
      program = insert(:program_schema, title: "Art Class")
      {child, parent} = insert_child_with_guardian()

      insert(:enrollment_schema,
        program_id: program.id,
        child_id: child.id,
        parent_id: parent.id,
        status: "confirmed"
      )

      assert {:ok, :has_enrollments, program_titles} = Family.prepare_child_deletion(child.id)
      assert "Art Class" in program_titles
    end

    test "returns multiple program titles for multiple enrollments" do
      program1 = insert(:program_schema, title: "Soccer Camp")
      program2 = insert(:program_schema, title: "Art Class")
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

      assert {:ok, :has_enrollments, program_titles} = Family.prepare_child_deletion(child.id)
      assert length(program_titles) == 2
      assert "Soccer Camp" in program_titles
      assert "Art Class" in program_titles
    end

    test "excludes cancelled enrollments" do
      program = insert(:program_schema, title: "Cancelled Program")
      {child, parent} = insert_child_with_guardian()

      insert(:enrollment_schema,
        program_id: program.id,
        child_id: child.id,
        parent_id: parent.id,
        status: "cancelled"
      )

      assert {:ok, :no_enrollments} = Family.prepare_child_deletion(child.id)
    end
  end
end
