defmodule KlassHero.Enrollment.Adapters.Driven.Persistence.Repositories.EnrollmentRepositoryTest do
  use KlassHero.DataCase, async: true

  import KlassHero.Factory

  alias Ecto.Adapters.SQL.Sandbox
  alias KlassHero.Enrollment.Adapters.Driven.Persistence.Repositories.EnrollmentRepository
  alias KlassHero.Enrollment.Domain.Models.Enrollment

  describe "create/1" do
    test "creates enrollment with valid attributes" do
      program = insert(:program_schema)
      {child, parent} = insert_child_with_guardian()

      attrs = %{
        program_id: program.id,
        child_id: child.id,
        parent_id: parent.id,
        status: "pending",
        enrolled_at: DateTime.utc_now(),
        subtotal: Decimal.new("100.00"),
        vat_amount: Decimal.new("19.00"),
        card_fee_amount: Decimal.new("2.00"),
        total_amount: Decimal.new("121.00"),
        payment_method: "card"
      }

      assert {:ok, enrollment} = EnrollmentRepository.create(attrs)
      assert %Enrollment{} = enrollment
      assert enrollment.program_id == program.id
      assert enrollment.child_id == child.id
      assert enrollment.parent_id == parent.id
      assert enrollment.status == :pending
    end

    test "returns domain entity with string IDs" do
      program = insert(:program_schema)
      {child, parent} = insert_child_with_guardian()

      attrs = %{
        program_id: program.id,
        child_id: child.id,
        parent_id: parent.id,
        status: "pending",
        enrolled_at: DateTime.utc_now()
      }

      {:ok, enrollment} = EnrollmentRepository.create(attrs)

      assert is_binary(enrollment.id)
      assert is_binary(enrollment.program_id)
      assert is_binary(enrollment.child_id)
      assert is_binary(enrollment.parent_id)
    end

    test "returns error when required fields are missing" do
      attrs = %{}

      assert {:error, changeset} = EnrollmentRepository.create(attrs)
      assert %Ecto.Changeset{} = changeset
      refute changeset.valid?
    end

    test "returns duplicate_resource error for active enrollment duplicate" do
      enrollment = insert(:enrollment_schema, status: "pending")

      attrs = %{
        program_id: enrollment.program_id,
        child_id: enrollment.child_id,
        parent_id: enrollment.parent_id,
        status: "pending",
        enrolled_at: DateTime.utc_now()
      }

      assert {:error, :duplicate_resource} = EnrollmentRepository.create(attrs)
    end

    test "allows duplicate for cancelled enrollment" do
      cancelled = insert(:enrollment_schema, status: "cancelled")

      attrs = %{
        program_id: cancelled.program_id,
        child_id: cancelled.child_id,
        parent_id: cancelled.parent_id,
        status: "pending",
        enrolled_at: DateTime.utc_now()
      }

      assert {:ok, _enrollment} = EnrollmentRepository.create(attrs)
    end

    test "allows duplicate for completed enrollment" do
      completed = insert(:enrollment_schema, status: "completed")

      attrs = %{
        program_id: completed.program_id,
        child_id: completed.child_id,
        parent_id: completed.parent_id,
        status: "pending",
        enrolled_at: DateTime.utc_now()
      }

      assert {:ok, _enrollment} = EnrollmentRepository.create(attrs)
    end
  end

  describe "get_by_id/1" do
    test "returns enrollment when found" do
      enrollment_schema = insert(:enrollment_schema)

      assert {:ok, enrollment} = EnrollmentRepository.get_by_id(enrollment_schema.id)
      assert %Enrollment{} = enrollment
      assert enrollment.id == to_string(enrollment_schema.id)
    end

    test "returns domain entity with correct status atom" do
      enrollment_schema = insert(:enrollment_schema, status: "confirmed")

      {:ok, enrollment} = EnrollmentRepository.get_by_id(enrollment_schema.id)

      assert enrollment.status == :confirmed
    end

    test "returns not_found when enrollment does not exist" do
      assert {:error, :not_found} = EnrollmentRepository.get_by_id(Ecto.UUID.generate())
    end
  end

  describe "list_by_parent/1" do
    test "returns all enrollments for parent" do
      parent = insert(:parent_profile_schema)
      {child1, _parent} = insert_child_with_guardian(parent: parent)
      {child2, _parent} = insert_child_with_guardian(parent: parent)

      enrollment1 = insert(:enrollment_schema, parent_id: parent.id, child_id: child1.id)
      enrollment2 = insert(:enrollment_schema, parent_id: parent.id, child_id: child2.id)
      _other = insert(:enrollment_schema)

      enrollments = EnrollmentRepository.list_by_parent(parent.id)

      assert length(enrollments) == 2
      ids = Enum.map(enrollments, & &1.id)
      assert to_string(enrollment1.id) in ids
      assert to_string(enrollment2.id) in ids
    end

    test "returns enrollments ordered by enrolled_at descending" do
      parent = insert(:parent_profile_schema)
      {child, _parent} = insert_child_with_guardian(parent: parent)

      old =
        insert(:enrollment_schema,
          parent_id: parent.id,
          child_id: child.id,
          enrolled_at: ~U[2025-01-10 10:00:00Z]
        )

      recent =
        insert(:enrollment_schema,
          parent_id: parent.id,
          child_id: child.id,
          enrolled_at: ~U[2025-01-20 10:00:00Z],
          status: "confirmed"
        )

      middle =
        insert(:enrollment_schema,
          parent_id: parent.id,
          child_id: child.id,
          enrolled_at: ~U[2025-01-15 10:00:00Z],
          status: "completed"
        )

      enrollments = EnrollmentRepository.list_by_parent(parent.id)

      ids = Enum.map(enrollments, & &1.id)
      assert ids == [to_string(recent.id), to_string(middle.id), to_string(old.id)]
    end

    test "returns empty list when no enrollments" do
      assert EnrollmentRepository.list_by_parent(Ecto.UUID.generate()) == []
    end

    test "returns domain entities" do
      enrollment_schema = insert(:enrollment_schema)

      [enrollment] = EnrollmentRepository.list_by_parent(enrollment_schema.parent_id)

      assert %Enrollment{} = enrollment
      assert is_atom(enrollment.status)
    end
  end

  describe "count_monthly_bookings/3" do
    test "counts active enrollments in date range" do
      parent = insert(:parent_profile_schema)
      {child, _parent} = insert_child_with_guardian(parent: parent)

      insert(:enrollment_schema,
        parent_id: parent.id,
        child_id: child.id,
        status: "pending",
        enrolled_at: ~U[2025-01-15 10:00:00Z]
      )

      insert(:enrollment_schema,
        parent_id: parent.id,
        child_id: child.id,
        status: "confirmed",
        enrolled_at: ~U[2025-01-20 10:00:00Z]
      )

      count =
        EnrollmentRepository.count_monthly_bookings(parent.id, ~D[2025-01-01], ~D[2025-01-31])

      assert count == 2
    end

    test "excludes completed and cancelled enrollments" do
      parent = insert(:parent_profile_schema)
      {child, _parent} = insert_child_with_guardian(parent: parent)

      insert(:enrollment_schema,
        parent_id: parent.id,
        child_id: child.id,
        status: "pending",
        enrolled_at: ~U[2025-01-15 10:00:00Z]
      )

      insert(:enrollment_schema,
        parent_id: parent.id,
        child_id: child.id,
        status: "completed",
        enrolled_at: ~U[2025-01-16 10:00:00Z]
      )

      insert(:enrollment_schema,
        parent_id: parent.id,
        child_id: child.id,
        status: "cancelled",
        enrolled_at: ~U[2025-01-17 10:00:00Z]
      )

      count =
        EnrollmentRepository.count_monthly_bookings(parent.id, ~D[2025-01-01], ~D[2025-01-31])

      assert count == 1
    end

    test "excludes enrollments outside date range" do
      parent = insert(:parent_profile_schema)
      {child, _parent} = insert_child_with_guardian(parent: parent)

      insert(:enrollment_schema,
        parent_id: parent.id,
        child_id: child.id,
        status: "pending",
        enrolled_at: ~U[2024-12-15 10:00:00Z]
      )

      insert(:enrollment_schema,
        parent_id: parent.id,
        child_id: child.id,
        status: "pending",
        enrolled_at: ~U[2025-01-15 10:00:00Z]
      )

      insert(:enrollment_schema,
        parent_id: parent.id,
        child_id: child.id,
        status: "confirmed",
        enrolled_at: ~U[2025-02-15 10:00:00Z]
      )

      count =
        EnrollmentRepository.count_monthly_bookings(parent.id, ~D[2025-01-01], ~D[2025-01-31])

      assert count == 1
    end

    test "returns 0 when no matching enrollments" do
      count =
        EnrollmentRepository.count_monthly_bookings(
          Ecto.UUID.generate(),
          ~D[2025-01-01],
          ~D[2025-01-31]
        )

      assert count == 0
    end
  end

  describe "update/2" do
    test "updates enrollment status and returns domain entity" do
      schema = insert(:enrollment_schema, status: "pending")

      attrs = %{
        status: "cancelled",
        cancelled_at: DateTime.utc_now() |> DateTime.truncate(:second),
        cancellation_reason: "Admin cancelled"
      }

      assert {:ok, enrollment} = EnrollmentRepository.update(schema.id, attrs)
      assert enrollment.status == :cancelled
      assert enrollment.cancellation_reason == "Admin cancelled"
      assert enrollment.cancelled_at != nil
    end

    test "returns not_found for nonexistent enrollment" do
      assert {:error, :not_found} =
               EnrollmentRepository.update(Ecto.UUID.generate(), %{status: "cancelled"})
    end

    test "returns changeset error for invalid status" do
      schema = insert(:enrollment_schema, status: "pending")

      assert {:error, changeset} =
               EnrollmentRepository.update(schema.id, %{status: "bogus"})

      assert %Ecto.Changeset{} = changeset
      assert {"is invalid", _} = changeset.errors[:status]
    end
  end

  describe "list_by_program/1" do
    test "returns active enrollments for a program" do
      program = insert(:program_schema)
      {child, parent} = insert_child_with_guardian()

      enrollment =
        insert(:enrollment_schema,
          program_id: program.id,
          child_id: child.id,
          parent_id: parent.id,
          status: "pending"
        )

      result = EnrollmentRepository.list_by_program(program.id)

      assert length(result) == 1
      assert hd(result).id == to_string(enrollment.id)
      assert hd(result).child_id == to_string(child.id)
    end

    test "returns both pending and confirmed enrollments" do
      program = insert(:program_schema)
      {child1, parent1} = insert_child_with_guardian()
      {child2, parent2} = insert_child_with_guardian()

      insert(:enrollment_schema,
        program_id: program.id,
        child_id: child1.id,
        parent_id: parent1.id,
        status: "pending"
      )

      insert(:enrollment_schema,
        program_id: program.id,
        child_id: child2.id,
        parent_id: parent2.id,
        status: "confirmed"
      )

      result = EnrollmentRepository.list_by_program(program.id)
      assert length(result) == 2
    end

    test "excludes cancelled and completed enrollments" do
      program = insert(:program_schema)
      {child1, parent1} = insert_child_with_guardian()
      {child2, parent2} = insert_child_with_guardian()

      insert(:enrollment_schema,
        program_id: program.id,
        child_id: child1.id,
        parent_id: parent1.id,
        status: "cancelled"
      )

      insert(:enrollment_schema,
        program_id: program.id,
        child_id: child2.id,
        parent_id: parent2.id,
        status: "completed"
      )

      assert EnrollmentRepository.list_by_program(program.id) == []
    end

    test "returns empty list for non-existent program" do
      assert EnrollmentRepository.list_by_program(Ecto.UUID.generate()) == []
    end

    test "returns domain entities ordered by enrolled_at descending" do
      program = insert(:program_schema)
      {child1, parent1} = insert_child_with_guardian()
      {child2, parent2} = insert_child_with_guardian()

      old =
        insert(:enrollment_schema,
          program_id: program.id,
          child_id: child1.id,
          parent_id: parent1.id,
          enrolled_at: ~U[2025-01-10 10:00:00Z]
        )

      recent =
        insert(:enrollment_schema,
          program_id: program.id,
          child_id: child2.id,
          parent_id: parent2.id,
          enrolled_at: ~U[2025-01-20 10:00:00Z],
          status: "confirmed"
        )

      result = EnrollmentRepository.list_by_program(program.id)

      ids = Enum.map(result, & &1.id)
      assert ids == [to_string(recent.id), to_string(old.id)]
      assert Enum.all?(result, &(%Enrollment{} = &1))
    end

    test "does not return enrollments from other programs" do
      program1 = insert(:program_schema)
      program2 = insert(:program_schema)
      {child, parent} = insert_child_with_guardian()

      insert(:enrollment_schema,
        program_id: program1.id,
        child_id: child.id,
        parent_id: parent.id
      )

      assert EnrollmentRepository.list_by_program(program2.id) == []
    end
  end

  describe "list_pending_by_programs/1" do
    test "returns only pending enrollments across the given programs" do
      program_a = insert(:program_schema)
      program_b = insert(:program_schema)
      program_c = insert(:program_schema)

      pending_a = insert(:enrollment_schema, program_id: program_a.id, status: :pending)
      pending_b = insert(:enrollment_schema, program_id: program_b.id, status: :pending)
      _confirmed_a = insert(:enrollment_schema, program_id: program_a.id, status: :confirmed)
      _cancelled_b = insert(:enrollment_schema, program_id: program_b.id, status: :cancelled)
      _completed_a = insert(:enrollment_schema, program_id: program_a.id, status: :completed)
      _other_program = insert(:enrollment_schema, program_id: program_c.id, status: :pending)

      ids =
        EnrollmentRepository.list_pending_by_programs([program_a.id, program_b.id])
        |> MapSet.new(& &1.id)

      assert MapSet.equal?(ids, MapSet.new([to_string(pending_a.id), to_string(pending_b.id)]))
    end

    test "returns Enrollment domain structs (not Ecto schemas)" do
      program = insert(:program_schema)
      insert(:enrollment_schema, program_id: program.id, status: :pending)

      [enrollment] = EnrollmentRepository.list_pending_by_programs([program.id])

      assert %Enrollment{status: :pending} = enrollment
    end

    test "returns [] for empty program_ids" do
      insert(:enrollment_schema, status: :pending)

      assert EnrollmentRepository.list_pending_by_programs([]) == []
    end

    test "returns [] when no pending enrollments match" do
      program = insert(:program_schema)
      insert(:enrollment_schema, program_id: program.id, status: :confirmed)

      assert EnrollmentRepository.list_pending_by_programs([program.id]) == []
    end
  end

  describe "concurrent create/1" do
    # Verifies that the unique constraint on (program_id, child_id) for active
    # enrollments is handled gracefully when two requests race to enroll the
    # same child in the same program. One must succeed and the other must return
    # {:error, :duplicate_resource} rather than crashing or leaking a raw
    # constraint error to callers.
    test "one request succeeds and the other returns duplicate_resource" do
      program = insert(:program_schema)
      {child, parent} = insert_child_with_guardian()
      test_pid = self()

      attrs = %{
        program_id: program.id,
        child_id: child.id,
        parent_id: parent.id,
        status: "pending",
        enrolled_at: DateTime.utc_now()
      }

      # Barrier pattern: both tasks signal readiness, then the test process
      # releases them simultaneously so the DB inserts actually overlap.
      tasks =
        Enum.map([1, 2], fn _ ->
          Task.async(fn ->
            Sandbox.allow(Repo, test_pid, self())
            send(test_pid, {:ready, self()})

            receive do
              :go -> :ok
            end

            EnrollmentRepository.create(attrs)
          end)
        end)

      pids = Enum.map(tasks, & &1.pid)

      # Wait for both tasks to be ready
      for pid <- pids do
        assert_receive {:ready, ^pid}, 5_000
      end

      # Release both at the same time
      for pid <- pids do
        send(pid, :go)
      end

      results = Task.await_many(tasks, 5_000)

      ok_count = Enum.count(results, &match?({:ok, _}, &1))
      dup_count = Enum.count(results, &match?({:error, :duplicate_resource}, &1))

      assert ok_count == 1, "Expected exactly one successful enrollment, got: #{inspect(results)}"

      assert dup_count == 1,
             "Expected exactly one :duplicate_resource error, got: #{inspect(results)}"
    end
  end
end
