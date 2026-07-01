defmodule KlassHero.Enrollment.EnrollmentPolicyTest do
  use KlassHero.DataCase, async: true

  import KlassHero.Factory

  alias KlassHero.Enrollment
  alias KlassHero.Enrollment.EnrollmentPolicy

  describe "changeset/2" do
    test "is valid with a program_id and at least one bound" do
      assert EnrollmentPolicy.changeset(%{program_id: Ecto.UUID.generate(), max_enrollment: 10}).valid?
      assert EnrollmentPolicy.changeset(%{program_id: Ecto.UUID.generate(), min_enrollment: 3}).valid?
    end

    test "requires program_id" do
      changeset = EnrollmentPolicy.changeset(%{max_enrollment: 10})
      refute changeset.valid?
      assert %{program_id: ["can't be blank"]} = errors_on(changeset)
    end

    test "rejects non-positive bounds" do
      changeset = EnrollmentPolicy.changeset(%{program_id: Ecto.UUID.generate(), min_enrollment: 0})
      refute changeset.valid?
      assert %{min_enrollment: ["must be greater than or equal to 1"]} = errors_on(changeset)
    end

    test "rejects min greater than max" do
      changeset =
        EnrollmentPolicy.changeset(%{program_id: Ecto.UUID.generate(), min_enrollment: 5, max_enrollment: 2})

      refute changeset.valid?
      assert %{min_enrollment: ["must not exceed maximum enrollment"]} = errors_on(changeset)
    end
  end

  describe "capacity math (pure)" do
    test "has_capacity?/2" do
      assert EnrollmentPolicy.has_capacity?(%EnrollmentPolicy{max_enrollment: nil}, 999)
      assert EnrollmentPolicy.has_capacity?(%EnrollmentPolicy{max_enrollment: 10}, 9)
      refute EnrollmentPolicy.has_capacity?(%EnrollmentPolicy{max_enrollment: 10}, 10)
    end

    test "meets_minimum?/2" do
      assert EnrollmentPolicy.meets_minimum?(%EnrollmentPolicy{min_enrollment: nil}, 0)
      assert EnrollmentPolicy.meets_minimum?(%EnrollmentPolicy{min_enrollment: 5}, 5)
      refute EnrollmentPolicy.meets_minimum?(%EnrollmentPolicy{min_enrollment: 5}, 4)
    end

    test "remaining_capacity/2 floors at 0 and reports :unlimited" do
      assert EnrollmentPolicy.remaining_capacity(%EnrollmentPolicy{max_enrollment: nil}, 3) == :unlimited
      assert EnrollmentPolicy.remaining_capacity(%EnrollmentPolicy{max_enrollment: 10}, 4) == 6
      assert EnrollmentPolicy.remaining_capacity(%EnrollmentPolicy{max_enrollment: 10}, 12) == 0
    end
  end

  describe "set_enrollment_policy/1 (upsert) + get_enrollment_policy/1" do
    test "inserts a new policy and reads it back" do
      program_id = insert(:program_schema).id

      assert {:ok, %EnrollmentPolicy{} = policy} =
               Enrollment.set_enrollment_policy(%{program_id: program_id, min_enrollment: 2, max_enrollment: 20})

      assert policy.program_id == program_id
      assert {:ok, ^policy} = Enrollment.get_enrollment_policy(program_id)
    end

    test "upserts on the same program_id rather than duplicating" do
      program_id = insert(:program_schema).id

      {:ok, _} = Enrollment.set_enrollment_policy(%{program_id: program_id, max_enrollment: 10})
      {:ok, updated} = Enrollment.set_enrollment_policy(%{program_id: program_id, max_enrollment: 25})

      assert updated.max_enrollment == 25
      assert {:ok, %EnrollmentPolicy{max_enrollment: 25}} = Enrollment.get_enrollment_policy(program_id)
    end

    test "returns an error changeset on invalid bounds" do
      assert {:error, %Ecto.Changeset{}} =
               Enrollment.set_enrollment_policy(%{
                 program_id: Ecto.UUID.generate(),
                 min_enrollment: 9,
                 max_enrollment: 1
               })
    end

    test "get_enrollment_policy/1 returns {:error, :not_found} for an unknown program" do
      assert {:error, :not_found} = Enrollment.get_enrollment_policy(Ecto.UUID.generate())
    end
  end
end
