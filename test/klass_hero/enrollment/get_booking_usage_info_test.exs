defmodule KlassHero.Enrollment.GetBookingUsageInfoTest do
  use KlassHero.DataCase, async: true

  import KlassHero.Factory

  describe "execute/1" do
    test "returns booking info for explorer tier parent with no bookings" do
      parent = insert(:parent_profile_schema, subscription_tier: "explorer")

      assert {:ok, info} = KlassHero.Enrollment.get_booking_usage_info(parent.identity_id)

      assert info.parent_id == parent.id
      assert info.tier == :explorer
      assert info.cap == 2
      assert info.used == 0
      assert info.remaining == 2
    end

    test "returns booking info for active tier parent (unlimited)" do
      parent = insert(:parent_profile_schema, subscription_tier: "active")

      assert {:ok, info} = KlassHero.Enrollment.get_booking_usage_info(parent.identity_id)

      assert info.parent_id == parent.id
      assert info.tier == :active
      assert info.cap == :unlimited
      assert info.used == 0
      assert info.remaining == :unlimited
    end

    test "returns :no_parent_profile when parent doesn't exist" do
      non_existent_identity_id = Ecto.UUID.generate()

      assert {:error, :no_parent_profile} = KlassHero.Enrollment.get_booking_usage_info(non_existent_identity_id)
    end

    test "correctly calculates remaining bookings for explorer tier" do
      parent = insert(:parent_profile_schema, subscription_tier: "explorer")
      {child, _parent} = insert_child_with_guardian(parent: parent)
      program = insert(:program_schema)

      insert(:enrollment_schema,
        parent_id: parent.id,
        child_id: child.id,
        program_id: program.id,
        status: "pending",
        enrolled_at: DateTime.utc_now()
      )

      assert {:ok, info} = KlassHero.Enrollment.get_booking_usage_info(parent.identity_id)

      assert info.cap == 2
      assert info.used == 1
      assert info.remaining == 1
    end

    test "handles edge case when explorer tier is at booking limit" do
      parent = insert(:parent_profile_schema, subscription_tier: "explorer")
      {child, _parent} = insert_child_with_guardian(parent: parent)
      program1 = insert(:program_schema)
      program2 = insert(:program_schema)

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

      assert {:ok, info} = KlassHero.Enrollment.get_booking_usage_info(parent.identity_id)

      assert info.cap == 2
      assert info.used == 2
      assert info.remaining == 0
    end

    test "active tier always shows unlimited remaining regardless of bookings" do
      parent = insert(:parent_profile_schema, subscription_tier: "active")
      {child, _parent} = insert_child_with_guardian(parent: parent)

      for _ <- 1..5 do
        program = insert(:program_schema)

        insert(:enrollment_schema,
          parent_id: parent.id,
          child_id: child.id,
          program_id: program.id,
          status: "confirmed",
          enrolled_at: DateTime.utc_now()
        )
      end

      assert {:ok, info} = KlassHero.Enrollment.get_booking_usage_info(parent.identity_id)

      assert info.tier == :active
      assert info.cap == :unlimited
      assert info.used == 5
      assert info.remaining == :unlimited
    end

    test "only counts active enrollments (pending, confirmed) not cancelled" do
      parent = insert(:parent_profile_schema, subscription_tier: "explorer")
      {child, _parent} = insert_child_with_guardian(parent: parent)
      program1 = insert(:program_schema)
      program2 = insert(:program_schema)

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
        status: "cancelled",
        enrolled_at: DateTime.utc_now()
      )

      assert {:ok, info} = KlassHero.Enrollment.get_booking_usage_info(parent.identity_id)

      assert info.used == 1
      assert info.remaining == 1
    end

    test "defaults to explorer tier when parent has default subscription tier" do
      # The schema defaults subscription_tier to "explorer", so we use the factory default
      parent = insert(:parent_profile_schema)

      assert {:ok, info} = KlassHero.Enrollment.get_booking_usage_info(parent.identity_id)

      assert info.tier == :explorer
      assert info.cap == 2
      assert info.remaining == 2
    end
  end
end
