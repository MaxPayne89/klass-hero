defmodule KlassHero.Enrollment.Application.Queries.EnrollmentPolicyQueriesTest do
  use KlassHero.DataCase, async: true

  import KlassHero.Factory

  alias KlassHero.Enrollment.Adapters.Driven.Persistence.Repositories.EnrollmentPolicyRepository
  alias KlassHero.Enrollment.Application.Queries.EnrollmentPolicyQueries

  # Helpers for setting up policies and enrollments
  defp upsert_policy!(program_id, attrs \\ %{}) do
    {:ok, policy} =
      EnrollmentPolicyRepository.upsert(Map.merge(%{program_id: program_id}, attrs))

    policy
  end

  defp insert_enrollment!(program_id, status \\ "pending") do
    {child, parent} = insert_child_with_guardian()

    insert(:enrollment_schema,
      program_id: program_id,
      child_id: child.id,
      parent_id: parent.id,
      status: status
    )
  end

  describe "remaining_capacity/1" do
    test "returns :unlimited when no policy exists for the program" do
      program = insert(:program_schema)

      assert {:ok, :unlimited} = EnrollmentPolicyQueries.remaining_capacity(program.id)
    end

    test "returns :unlimited when policy has no max_enrollment" do
      program = insert(:program_schema)
      upsert_policy!(program.id, %{max_enrollment: nil})

      assert {:ok, :unlimited} = EnrollmentPolicyQueries.remaining_capacity(program.id)
    end

    test "returns remaining spots when some enrollments exist" do
      program = insert(:program_schema)
      upsert_policy!(program.id, %{max_enrollment: 10})
      insert_enrollment!(program.id, "pending")
      insert_enrollment!(program.id, "confirmed")

      assert {:ok, 8} = EnrollmentPolicyQueries.remaining_capacity(program.id)
    end

    test "returns 0 when program is fully enrolled" do
      program = insert(:program_schema)
      upsert_policy!(program.id, %{max_enrollment: 2})
      insert_enrollment!(program.id, "pending")
      insert_enrollment!(program.id, "confirmed")

      assert {:ok, 0} = EnrollmentPolicyQueries.remaining_capacity(program.id)
    end

    test "ignores cancelled enrollments in the count" do
      program = insert(:program_schema)
      upsert_policy!(program.id, %{max_enrollment: 3})
      insert_enrollment!(program.id, "cancelled")

      assert {:ok, 3} = EnrollmentPolicyQueries.remaining_capacity(program.id)
    end
  end

  describe "get_remaining_capacities/1" do
    test "returns empty map for empty program list" do
      assert %{} == EnrollmentPolicyQueries.get_remaining_capacities([])
    end

    test "returns :unlimited for programs without a policy" do
      program = insert(:program_schema)

      result = EnrollmentPolicyQueries.get_remaining_capacities([program.id])

      assert result == %{program.id => :unlimited}
    end

    test "returns :unlimited for programs with no max_enrollment" do
      program = insert(:program_schema)
      upsert_policy!(program.id, %{max_enrollment: nil})

      result = EnrollmentPolicyQueries.get_remaining_capacities([program.id])

      assert result == %{program.id => :unlimited}
    end

    test "returns correct remaining capacity for programs with capped policies" do
      program = insert(:program_schema)
      upsert_policy!(program.id, %{max_enrollment: 5})
      insert_enrollment!(program.id, "pending")
      insert_enrollment!(program.id, "confirmed")

      result = EnrollmentPolicyQueries.get_remaining_capacities([program.id])

      assert result == %{program.id => 3}
    end

    test "handles a mix of programs with and without policies" do
      capped = insert(:program_schema)
      unlimited = insert(:program_schema)

      upsert_policy!(capped.id, %{max_enrollment: 4})
      insert_enrollment!(capped.id, "confirmed")

      result = EnrollmentPolicyQueries.get_remaining_capacities([capped.id, unlimited.id])

      assert result == %{capped.id => 3, unlimited.id => :unlimited}
    end
  end

  describe "get_enrollment_summary_batch/1" do
    test "returns empty map for empty program list" do
      assert %{} == EnrollmentPolicyQueries.get_enrollment_summary_batch([])
    end

    test "returns nil capacity for programs without a policy" do
      program = insert(:program_schema)

      result = EnrollmentPolicyQueries.get_enrollment_summary_batch([program.id])

      assert result == %{program.id => %{enrolled: 0, capacity: nil}}
    end

    test "returns nil capacity for programs with unlimited policy (no max)" do
      program = insert(:program_schema)
      upsert_policy!(program.id, %{max_enrollment: nil})
      insert_enrollment!(program.id, "confirmed")

      result = EnrollmentPolicyQueries.get_enrollment_summary_batch([program.id])

      assert result == %{program.id => %{enrolled: 1, capacity: nil}}
    end

    test "returns correct enrolled count and total capacity for capped programs" do
      program = insert(:program_schema)
      upsert_policy!(program.id, %{max_enrollment: 5})
      insert_enrollment!(program.id, "pending")
      insert_enrollment!(program.id, "confirmed")

      result = EnrollmentPolicyQueries.get_enrollment_summary_batch([program.id])

      assert result == %{program.id => %{enrolled: 2, capacity: 5}}
    end

    test "handles fully enrolled program — enrolled equals capacity" do
      program = insert(:program_schema)
      upsert_policy!(program.id, %{max_enrollment: 2})
      insert_enrollment!(program.id, "pending")
      insert_enrollment!(program.id, "confirmed")

      result = EnrollmentPolicyQueries.get_enrollment_summary_batch([program.id])

      assert result == %{program.id => %{enrolled: 2, capacity: 2}}
    end

    test "handles mixed programs in a single batch call" do
      capped = insert(:program_schema)
      unlimited = insert(:program_schema)
      no_policy = insert(:program_schema)

      upsert_policy!(capped.id, %{max_enrollment: 10})
      upsert_policy!(unlimited.id, %{max_enrollment: nil})

      insert_enrollment!(capped.id, "pending")
      insert_enrollment!(unlimited.id, "confirmed")

      result =
        EnrollmentPolicyQueries.get_enrollment_summary_batch([
          capped.id,
          unlimited.id,
          no_policy.id
        ])

      assert result == %{
               capped.id => %{enrolled: 1, capacity: 10},
               unlimited.id => %{enrolled: 1, capacity: nil},
               no_policy.id => %{enrolled: 0, capacity: nil}
             }
    end
  end
end
