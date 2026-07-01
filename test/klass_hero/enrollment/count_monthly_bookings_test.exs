defmodule KlassHero.Enrollment.CountMonthlyBookingsTest do
  use KlassHero.DataCase, async: true

  import KlassHero.Factory

  describe "execute/2" do
    test "returns count for current month by default" do
      parent = insert(:parent_profile_schema)
      {child, _parent} = insert_child_with_guardian(parent: parent)
      program = insert(:program_schema)

      insert(:enrollment_schema,
        parent_id: parent.id,
        child_id: child.id,
        program_id: program.id,
        status: "pending",
        enrolled_at: DateTime.utc_now()
      )

      assert KlassHero.Enrollment.count_monthly_bookings(parent.id) == 1
    end

    test "returns 0 for parent with no bookings" do
      parent = insert(:parent_profile_schema)

      assert KlassHero.Enrollment.count_monthly_bookings(parent.id) == 0
    end

    test "accepts optional month parameter" do
      parent = insert(:parent_profile_schema)
      {child, _parent} = insert_child_with_guardian(parent: parent)
      program = insert(:program_schema)

      # Enrollment from previous month
      last_month = Date.utc_today() |> Date.add(-35)

      insert(:enrollment_schema,
        parent_id: parent.id,
        child_id: child.id,
        program_id: program.id,
        status: "pending",
        enrolled_at: DateTime.new!(last_month, ~T[12:00:00], "Etc/UTC")
      )

      # Current month should show 0
      assert KlassHero.Enrollment.count_monthly_bookings(parent.id) == 0

      # Last month should show 1
      assert KlassHero.Enrollment.count_monthly_bookings(parent.id, last_month) == 1
    end

    test "only counts active enrollments (pending, confirmed)" do
      parent = insert(:parent_profile_schema)
      {child, _parent} = insert_child_with_guardian(parent: parent)

      program1 = insert(:program_schema)
      program2 = insert(:program_schema)
      program3 = insert(:program_schema)
      program4 = insert(:program_schema)

      insert(:enrollment_schema,
        parent_id: parent.id,
        child_id: child.id,
        program_id: program1.id,
        status: "pending",
        enrolled_at: DateTime.utc_now()
      )

      insert(:enrollment_schema,
        parent_id: parent.id,
        child_id: child.id,
        program_id: program2.id,
        status: "confirmed",
        enrolled_at: DateTime.utc_now()
      )

      insert(:enrollment_schema,
        parent_id: parent.id,
        child_id: child.id,
        program_id: program3.id,
        status: "cancelled",
        enrolled_at: DateTime.utc_now()
      )

      insert(:enrollment_schema,
        parent_id: parent.id,
        child_id: child.id,
        program_id: program4.id,
        status: "completed",
        enrolled_at: DateTime.utc_now()
      )

      # Only pending and confirmed should count
      assert KlassHero.Enrollment.count_monthly_bookings(parent.id) == 2
    end

    test "counts multiple children's enrollments for same parent" do
      parent = insert(:parent_profile_schema)
      {child1, _parent} = insert_child_with_guardian(parent: parent)
      {child2, _parent} = insert_child_with_guardian(parent: parent)

      program1 = insert(:program_schema)
      program2 = insert(:program_schema)

      insert(:enrollment_schema,
        parent_id: parent.id,
        child_id: child1.id,
        program_id: program1.id,
        status: "pending",
        enrolled_at: DateTime.utc_now()
      )

      insert(:enrollment_schema,
        parent_id: parent.id,
        child_id: child2.id,
        program_id: program2.id,
        status: "confirmed",
        enrolled_at: DateTime.utc_now()
      )

      assert KlassHero.Enrollment.count_monthly_bookings(parent.id) == 2
    end

    test "does not count enrollments from other parents" do
      parent1 = insert(:parent_profile_schema)
      parent2 = insert(:parent_profile_schema)

      {child1, _parent1} = insert_child_with_guardian(parent: parent1)
      {child2, _parent2} = insert_child_with_guardian(parent: parent2)

      program = insert(:program_schema)

      insert(:enrollment_schema,
        parent_id: parent1.id,
        child_id: child1.id,
        program_id: program.id,
        status: "pending",
        enrolled_at: DateTime.utc_now()
      )

      insert(:enrollment_schema,
        parent_id: parent2.id,
        child_id: child2.id,
        program_id: program.id,
        status: "pending",
        enrolled_at: DateTime.utc_now()
      )

      assert KlassHero.Enrollment.count_monthly_bookings(parent1.id) == 1
      assert KlassHero.Enrollment.count_monthly_bookings(parent2.id) == 1
    end

    test "correctly handles month boundaries" do
      parent = insert(:parent_profile_schema)
      {child, _parent} = insert_child_with_guardian(parent: parent)
      program1 = insert(:program_schema)
      program2 = insert(:program_schema)

      # First day of current month
      today = Date.utc_today()
      first_of_month = Date.beginning_of_month(today)
      last_of_month = Date.end_of_month(today)

      insert(:enrollment_schema,
        parent_id: parent.id,
        child_id: child.id,
        program_id: program1.id,
        status: "pending",
        enrolled_at: DateTime.new!(first_of_month, ~T[00:00:00], "Etc/UTC")
      )

      insert(:enrollment_schema,
        parent_id: parent.id,
        child_id: child.id,
        program_id: program2.id,
        status: "pending",
        enrolled_at: DateTime.new!(last_of_month, ~T[23:59:59], "Etc/UTC")
      )

      assert KlassHero.Enrollment.count_monthly_bookings(parent.id) == 2
    end
  end
end
