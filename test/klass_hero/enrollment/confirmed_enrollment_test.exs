defmodule KlassHero.Enrollment.ConfirmedEnrollmentTest do
  use KlassHero.DataCase, async: true

  import KlassHero.Factory

  alias KlassHero.Enrollment

  describe "confirmed_enrollment?/2" do
    test "true when the user's child holds a confirmed enrollment on the program" do
      program = insert(:program_schema)
      {child, parent} = insert_child_with_guardian()

      insert(:enrollment_schema,
        program_id: program.id,
        child_id: child.id,
        parent_id: parent.id,
        status: "confirmed"
      )

      assert Enrollment.confirmed_enrollment?(program.id, parent.identity_id)
    end

    test "false for every non-confirmed status" do
      for status <- ~w(pending completed cancelled) do
        program = insert(:program_schema)
        {child, parent} = insert_child_with_guardian()

        insert(:enrollment_schema,
          program_id: program.id,
          child_id: child.id,
          parent_id: parent.id,
          status: status
        )

        refute Enrollment.confirmed_enrollment?(program.id, parent.identity_id),
               "expected #{status} not to count as a confirmed enrollment"
      end
    end

    test "false when the confirmed enrollment is on a different program" do
      other_program = insert(:program_schema)
      program = insert(:program_schema)
      {child, parent} = insert_child_with_guardian()

      insert(:enrollment_schema,
        program_id: other_program.id,
        child_id: child.id,
        parent_id: parent.id,
        status: "confirmed"
      )

      refute Enrollment.confirmed_enrollment?(program.id, parent.identity_id)
    end

    test "false when the user has no parent profile" do
      program = insert(:program_schema)
      user = KlassHero.AccountsFixtures.user_fixture()

      refute Enrollment.confirmed_enrollment?(program.id, user.id)
    end
  end
end
