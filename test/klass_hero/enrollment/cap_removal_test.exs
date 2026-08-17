defmodule KlassHero.Enrollment.CapRemovalTest do
  use KlassHero.DataCase, async: true

  import KlassHero.Factory

  alias KlassHero.Enrollment
  alias KlassHero.Enrollment.EnrollmentPolicy

  defp capped_program(max_enrollment) do
    program = insert(:program_schema)

    {:ok, _policy} =
      Enrollment.set_enrollment_policy(%{program_id: program.id, max_enrollment: max_enrollment})

    program
  end

  defp stored_policy(program_id), do: Repo.get_by(EnrollmentPolicy, program_id: program_id)

  describe "EnrollmentPolicy.cap_removal?/2" do
    @truth_table [
      {12, nil, true, "blanking a stored maximum"},
      {12, 30, false, "raising it"},
      {12, 5, false, "lowering it"},
      {nil, nil, false, "leaving an already-uncapped program uncapped"},
      {nil, 12, false, "adding a maximum where there was none"}
    ]

    test "is true only when a stored maximum is being blanked" do
      for {previous, new_max, expected, label} <- @truth_table do
        policy = %EnrollmentPolicy{max_enrollment: previous}

        assert EnrollmentPolicy.cap_removal?(policy, new_max) == expected,
               "#{label}: expected cap_removal?(#{inspect(previous)}, #{inspect(new_max)}) " <>
                 "to be #{expected}"
      end
    end

    test "is false with no policy at all, which is the create path" do
      refute EnrollmentPolicy.cap_removal?(nil, nil)
    end
  end

  describe "set_enrollment_policy/1 — clearing capacity (#1370)" do
    test "clears both limits on a program with no active enrollments" do
      program = capped_program(12)

      assert {:ok, _policy} =
               Enrollment.set_enrollment_policy(%{
                 program_id: program.id,
                 min_enrollment: nil,
                 max_enrollment: nil
               })

      assert %EnrollmentPolicy{min_enrollment: nil, max_enrollment: nil} = stored_policy(program.id)
    end

    test "keeps exactly one policy row rather than deleting it" do
      program = capped_program(12)

      {:ok, _} =
        Enrollment.set_enrollment_policy(%{
          program_id: program.id,
          min_enrollment: nil,
          max_enrollment: nil
        })

      assert Repo.aggregate(
               from(p in EnrollmentPolicy, where: p.program_id == ^program.id),
               :count
             ) == 1
    end

    test "clearing only the minimum is never guarded" do
      program = insert(:program_schema)

      {:ok, _} =
        Enrollment.set_enrollment_policy(%{
          program_id: program.id,
          min_enrollment: 3,
          max_enrollment: 12
        })

      insert(:enrollment_schema, program_id: program.id, status: "confirmed")

      assert {:ok, _} =
               Enrollment.set_enrollment_policy(%{
                 program_id: program.id,
                 min_enrollment: nil,
                 max_enrollment: 12
               })

      assert %EnrollmentPolicy{min_enrollment: nil, max_enrollment: 12} = stored_policy(program.id)
    end
  end

  describe "set_enrollment_policy/1 — removing the cap with active enrollments" do
    test "refuses an unacknowledged removal and leaves the stored cap intact" do
      program = capped_program(12)
      insert(:enrollment_schema, program_id: program.id, status: "confirmed")
      insert(:enrollment_schema, program_id: program.id, status: "pending")

      assert {:error, {:cap_removal_blocked, 2}} =
               Enrollment.set_enrollment_policy(%{program_id: program.id, max_enrollment: nil})

      assert %EnrollmentPolicy{max_enrollment: 12} = stored_policy(program.id)
    end

    test "permits the removal when explicitly acknowledged" do
      program = capped_program(12)
      insert(:enrollment_schema, program_id: program.id, status: "confirmed")

      assert {:ok, _} =
               Enrollment.set_enrollment_policy(%{
                 program_id: program.id,
                 max_enrollment: nil,
                 acknowledge_cap_removal: true
               })

      assert %EnrollmentPolicy{max_enrollment: nil} = stored_policy(program.id)
    end

    test "ignores cancelled enrollments when counting" do
      program = capped_program(12)
      insert(:enrollment_schema, program_id: program.id, status: "cancelled")

      assert {:ok, _} =
               Enrollment.set_enrollment_policy(%{program_id: program.id, max_enrollment: nil})

      assert %EnrollmentPolicy{max_enrollment: nil} = stored_policy(program.id)
    end

    test "leaves raising the cap unguarded" do
      program = capped_program(12)
      insert(:enrollment_schema, program_id: program.id, status: "confirmed")

      assert {:ok, _} =
               Enrollment.set_enrollment_policy(%{program_id: program.id, max_enrollment: 30})

      assert %EnrollmentPolicy{max_enrollment: 30} = stored_policy(program.id)
    end

    test "leaves lowering the cap below the enrolled count unguarded" do
      program = capped_program(12)

      for _ <- 1..3, do: insert(:enrollment_schema, program_id: program.id, status: "confirmed")

      assert {:ok, _} =
               Enrollment.set_enrollment_policy(%{program_id: program.id, max_enrollment: 2})

      assert %EnrollmentPolicy{max_enrollment: 2} = stored_policy(program.id)
    end

    test "is inert on create, where there is no cap to remove" do
      program = insert(:program_schema)
      insert(:enrollment_schema, program_id: program.id, status: "confirmed")

      assert {:ok, _} =
               Enrollment.set_enrollment_policy(%{
                 program_id: program.id,
                 min_enrollment: 3,
                 max_enrollment: nil
               })

      assert %EnrollmentPolicy{min_enrollment: 3, max_enrollment: nil} = stored_policy(program.id)
    end
  end

  describe "assess_capacity_change/2" do
    test "reports the removal and the count that makes it consequential" do
      program = capped_program(12)
      insert(:enrollment_schema, program_id: program.id, status: "confirmed")
      insert(:enrollment_schema, program_id: program.id, status: "pending")

      assert {:cap_removal, 2} = Enrollment.assess_capacity_change(program.id, nil)
    end

    test "reports :ok when the cap is being kept" do
      program = capped_program(12)
      insert(:enrollment_schema, program_id: program.id, status: "confirmed")

      assert :ok = Enrollment.assess_capacity_change(program.id, 30)
    end

    test "reports :ok when no one is enrolled" do
      program = capped_program(12)

      assert :ok = Enrollment.assess_capacity_change(program.id, nil)
    end

    test "reports :ok when no policy exists yet" do
      program = insert(:program_schema)

      assert :ok = Enrollment.assess_capacity_change(program.id, nil)
    end

    # The whole point of the shared predicate: the hint the provider sees and the
    # rule the write enforces must never disagree, or the form warns about a save
    # that succeeds (or stays silent before one that fails).
    test "agrees with what the write actually does" do
      for {max, enrolled} <- [{nil, 0}, {nil, 2}, {30, 2}, {5, 2}] do
        program = capped_program(12)

        for _ <- 1..enrolled//1,
            do: insert(:enrollment_schema, program_id: program.id, status: "confirmed")

        assessment = Enrollment.assess_capacity_change(program.id, max)
        write = Enrollment.set_enrollment_policy(%{program_id: program.id, max_enrollment: max})

        assert match?({:cap_removal, _}, assessment) == match?({:error, {:cap_removal_blocked, _}}, write),
               """
               assessment and write disagreed for max=#{inspect(max)}, enrolled=#{enrolled}
                 assessment: #{inspect(assessment)}
                 write:      #{inspect(write)}
               """
      end
    end
  end
end
