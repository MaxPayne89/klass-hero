defmodule KlassHero.Enrollment.CreateEnrollmentTest do
  use KlassHero.DataCase, async: true

  import KlassHero.Factory

  alias KlassHero.Enrollment.Enrollment

  describe "execute/1" do
    test "creates enrollment with valid params" do
      program = insert(:program_schema)
      {child, parent} = insert_child_with_guardian()

      params = %{
        program_id: program.id,
        child_id: child.id,
        parent_id: parent.id
      }

      assert {:ok, enrollment} = KlassHero.Enrollment.create_enrollment(params)
      assert %Enrollment{} = enrollment
      assert enrollment.program_id == program.id
      assert enrollment.child_id == child.id
      assert enrollment.parent_id == parent.id
      assert enrollment.status == :pending
    end

    test "defaults status to pending" do
      program = insert(:program_schema)
      {child, parent} = insert_child_with_guardian()

      params = %{
        program_id: program.id,
        child_id: child.id,
        parent_id: parent.id
      }

      {:ok, enrollment} = KlassHero.Enrollment.create_enrollment(params)

      assert enrollment.status == :pending
    end

    test "defaults enrolled_at to current time" do
      program = insert(:program_schema)
      {child, parent} = insert_child_with_guardian()

      params = %{
        program_id: program.id,
        child_id: child.id,
        parent_id: parent.id
      }

      before = DateTime.utc_now() |> DateTime.truncate(:second)
      {:ok, enrollment} = KlassHero.Enrollment.create_enrollment(params)
      after_time = DateTime.utc_now() |> DateTime.add(1, :second)

      assert DateTime.compare(enrollment.enrolled_at, before) in [:gt, :eq]
      assert DateTime.compare(enrollment.enrolled_at, after_time) in [:lt, :eq]
    end

    test "accepts optional fee amounts" do
      program = insert(:program_schema)
      {child, parent} = insert_child_with_guardian()

      params = %{
        program_id: program.id,
        child_id: child.id,
        parent_id: parent.id,
        subtotal: Decimal.new("100.00"),
        vat_amount: Decimal.new("19.00"),
        card_fee_amount: Decimal.new("2.00"),
        total_amount: Decimal.new("121.00")
      }

      {:ok, enrollment} = KlassHero.Enrollment.create_enrollment(params)

      assert enrollment.subtotal == Decimal.new("100.00")
      assert enrollment.vat_amount == Decimal.new("19.00")
      assert enrollment.card_fee_amount == Decimal.new("2.00")
      assert enrollment.total_amount == Decimal.new("121.00")
    end

    test "accepts payment_method" do
      program = insert(:program_schema)
      {child, parent} = insert_child_with_guardian()

      params = %{
        program_id: program.id,
        child_id: child.id,
        parent_id: parent.id,
        payment_method: "transfer"
      }

      {:ok, enrollment} = KlassHero.Enrollment.create_enrollment(params)

      assert enrollment.payment_method == "transfer"
    end

    test "accepts special_requirements" do
      program = insert(:program_schema)
      {child, parent} = insert_child_with_guardian()

      params = %{
        program_id: program.id,
        child_id: child.id,
        parent_id: parent.id,
        special_requirements: "Allergic to peanuts"
      }

      {:ok, enrollment} = KlassHero.Enrollment.create_enrollment(params)

      assert enrollment.special_requirements == "Allergic to peanuts"
    end

    test "returns duplicate_resource error for duplicate active enrollment" do
      existing = insert(:enrollment_schema, status: "pending")

      params = %{
        program_id: existing.program_id,
        child_id: existing.child_id,
        parent_id: existing.parent_id
      }

      assert {:error, :duplicate_resource} = KlassHero.Enrollment.create_enrollment(params)
    end

    test "allows new enrollment after previous one cancelled" do
      cancelled = insert(:enrollment_schema, status: "cancelled")

      params = %{
        program_id: cancelled.program_id,
        child_id: cancelled.child_id,
        parent_id: cancelled.parent_id
      }

      assert {:ok, enrollment} = KlassHero.Enrollment.create_enrollment(params)
      assert enrollment.status == :pending
    end

    test "returns changeset error for missing required fields" do
      params = %{}

      assert {:error, %Ecto.Changeset{}} = KlassHero.Enrollment.create_enrollment(params)
    end

    test "accepts custom enrolled_at" do
      program = insert(:program_schema)
      {child, parent} = insert_child_with_guardian()
      enrolled_at = ~U[2025-01-15 10:00:00Z]

      params = %{
        program_id: program.id,
        child_id: child.id,
        parent_id: parent.id,
        enrolled_at: enrolled_at
      }

      {:ok, enrollment} = KlassHero.Enrollment.create_enrollment(params)

      assert enrollment.enrolled_at == enrolled_at
    end

    test "accepts custom status" do
      program = insert(:program_schema)
      {child, parent} = insert_child_with_guardian()

      params = %{
        program_id: program.id,
        child_id: child.id,
        parent_id: parent.id,
        status: "confirmed"
      }

      {:ok, enrollment} = KlassHero.Enrollment.create_enrollment(params)

      assert enrollment.status == :confirmed
    end
  end

  describe "participant eligibility enforcement" do
    test "rejects enrollment when child is ineligible (too young)" do
      program = insert(:program_schema)
      parent = insert(:parent_profile_schema, subscription_tier: "active")

      # Born 30 days ago — far too young for min_age 60 months
      {child, _parent} =
        insert_child_with_guardian(
          parent: parent,
          date_of_birth: Date.add(Date.utc_today(), -30),
          gender: "male"
        )

      {:ok, _policy} =
        KlassHero.Enrollment.set_participant_policy(%{
          program_id: program.id,
          min_age_months: 60,
          eligibility_at: "registration"
        })

      result =
        KlassHero.Enrollment.create_enrollment(%{
          identity_id: parent.identity_id,
          program_id: program.id,
          child_id: child.id,
          payment_method: "card"
        })

      assert {:error, :ineligible, reasons} = result
      refute Enum.empty?(reasons)
      assert Enum.any?(reasons, &String.contains?(&1, "too young"))
    end

    test "allows enrollment when child meets all restrictions" do
      program = insert(:program_schema)
      parent = insert(:parent_profile_schema, subscription_tier: "active")

      {child, _parent} =
        insert_child_with_guardian(
          parent: parent,
          date_of_birth: ~D[2018-06-15],
          gender: "female"
        )

      {:ok, _policy} =
        KlassHero.Enrollment.set_participant_policy(%{
          program_id: program.id,
          min_age_months: 60,
          max_age_months: 180,
          allowed_genders: ["female", "male"],
          eligibility_at: "registration"
        })

      assert {:ok, enrollment} =
               KlassHero.Enrollment.create_enrollment(%{
                 identity_id: parent.identity_id,
                 program_id: program.id,
                 child_id: child.id,
                 payment_method: "card"
               })

      assert enrollment.program_id == program.id
      assert enrollment.child_id == child.id
    end

    test "allows enrollment when no participant policy exists" do
      program = insert(:program_schema)
      parent = insert(:parent_profile_schema, subscription_tier: "active")
      {child, _parent} = insert_child_with_guardian(parent: parent)

      assert {:ok, _enrollment} =
               KlassHero.Enrollment.create_enrollment(%{
                 identity_id: parent.identity_id,
                 program_id: program.id,
                 child_id: child.id,
                 payment_method: "card"
               })
    end

    test "returns processing_failed when child does not exist" do
      program = insert(:program_schema)
      parent = insert(:parent_profile_schema, subscription_tier: "active")

      {:ok, _policy} =
        KlassHero.Enrollment.set_participant_policy(%{
          program_id: program.id,
          min_age_months: 60,
          eligibility_at: "registration"
        })

      result =
        KlassHero.Enrollment.create_enrollment(%{
          identity_id: parent.identity_id,
          program_id: program.id,
          child_id: Ecto.UUID.generate(),
          payment_method: "card"
        })

      assert {:error, :processing_failed} = result
    end
  end

  describe "capacity enforcement" do
    test "rejects enrollment when program is at max capacity" do
      program = insert(:program_schema)
      {child1, parent1} = insert_child_with_guardian()
      {child2, parent2} = insert_child_with_guardian()

      KlassHero.Enrollment.set_enrollment_policy(%{program_id: program.id, max_enrollment: 1})

      {:ok, _} =
        KlassHero.Enrollment.create_enrollment(%{
          program_id: program.id,
          child_id: child1.id,
          parent_id: parent1.id
        })

      assert {:error, :program_full} =
               KlassHero.Enrollment.create_enrollment(%{
                 program_id: program.id,
                 child_id: child2.id,
                 parent_id: parent2.id
               })
    end

    test "allows enrollment when no policy exists (unlimited)" do
      program = insert(:program_schema)
      {child, parent} = insert_child_with_guardian()

      assert {:ok, _} =
               KlassHero.Enrollment.create_enrollment(%{
                 program_id: program.id,
                 child_id: child.id,
                 parent_id: parent.id
               })
    end

    test "allows enrollment when under max capacity" do
      program = insert(:program_schema)
      {child, parent} = insert_child_with_guardian()

      KlassHero.Enrollment.set_enrollment_policy(%{program_id: program.id, max_enrollment: 10})

      assert {:ok, _} =
               KlassHero.Enrollment.create_enrollment(%{
                 program_id: program.id,
                 child_id: child.id,
                 parent_id: parent.id
               })
    end
  end
end
