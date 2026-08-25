defmodule KlassHero.Enrollment.ListProgramEnrollmentsTest do
  use KlassHero.DataCase, async: true

  import KlassHero.Factory

  describe "execute/1" do
    test "returns enriched roster entries with child names" do
      program = insert(:program_schema)
      {child, parent} = insert_child_with_guardian(first_name: "Emma", last_name: "Smith")

      insert(:enrollment_schema,
        program_id: program.id,
        child_id: child.id,
        parent_id: parent.id,
        status: "pending",
        enrolled_at: ~U[2025-06-15 10:00:00Z]
      )

      result = KlassHero.Enrollment.list_program_enrollments(program.id)

      assert length(result) == 1
      entry = hd(result)
      assert entry.child_name == "Emma Smith"
      assert entry.status == :pending
      assert entry.enrolled_at == ~U[2025-06-15 10:00:00Z]
      assert {:ok, _} = Ecto.UUID.dump(entry.enrollment_id)
      assert entry.child_id == to_string(child.id)
    end

    test "returns multiple entries for program with multiple enrollments" do
      program = insert(:program_schema)
      {child1, parent1} = insert_child_with_guardian(first_name: "Emma", last_name: "Smith")
      {child2, parent2} = insert_child_with_guardian(first_name: "Liam", last_name: "Jones")

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

      result = KlassHero.Enrollment.list_program_enrollments(program.id)

      assert length(result) == 2
      names = Enum.map(result, & &1.child_name) |> Enum.sort()
      assert names == ["Emma Smith", "Liam Jones"]
    end

    test "excludes cancelled enrollments" do
      program = insert(:program_schema)
      {child, parent} = insert_child_with_guardian()

      insert(:enrollment_schema,
        program_id: program.id,
        child_id: child.id,
        parent_id: parent.id,
        status: "cancelled"
      )

      assert KlassHero.Enrollment.list_program_enrollments(program.id) == []
    end

    test "returns empty list for non-existent program" do
      assert KlassHero.Enrollment.list_program_enrollments(Ecto.UUID.generate()) == []
    end

    test "returns empty list when program has no enrollments" do
      program = insert(:program_schema)
      assert KlassHero.Enrollment.list_program_enrollments(program.id) == []
    end

    test "includes parent_id and parent_user_id in roster entries" do
      program = insert(:program_schema)
      {child, parent} = insert_child_with_guardian(first_name: "Emma", last_name: "Smith")

      insert(:enrollment_schema,
        program_id: program.id,
        child_id: child.id,
        parent_id: parent.id,
        status: "confirmed"
      )

      [entry] = KlassHero.Enrollment.list_program_enrollments(program.id)

      assert entry.parent_id == to_string(parent.id)
      assert entry.parent_user_id == to_string(parent.identity_id)
    end

    test "returns nil parent_user_id when parent profile not found" do
      program = insert(:program_schema)
      {child, parent} = insert_child_with_guardian(first_name: "Orphan", last_name: "Entry")

      insert(:enrollment_schema,
        program_id: program.id,
        child_id: child.id,
        parent_id: parent.id,
        status: "confirmed"
      )

      # Trigger: simulate orphaned enrollment (parent profile deleted after enrollment)
      # Why: FK constraints normally prevent this, but we need to test defensive code
      # Outcome: parent lookup returns nil, parent_user_id should be nil
      parent_id_bin = Ecto.UUID.dump!(parent.id)

      # Disable FK trigger checks so we can simulate an orphaned enrollment
      KlassHero.Repo.query!("SET session_replication_role = 'replica'")

      KlassHero.Repo.query!("DELETE FROM children_guardians WHERE guardian_id = $1", [
        parent_id_bin
      ])

      KlassHero.Repo.query!("DELETE FROM parents WHERE id = $1", [parent_id_bin])

      # Re-enable FK trigger checks to avoid leaking session state
      KlassHero.Repo.query!("SET session_replication_role = 'origin'")

      [entry] = KlassHero.Enrollment.list_program_enrollments(program.id)

      assert entry.parent_id == to_string(parent.id)
      assert entry.parent_user_id == nil
    end
  end

  describe "waiver status" do
    setup do
      provider = insert(:provider_profile_schema)
      program = insert(:program_schema, provider_id: provider.id)
      {child, parent} = insert_child_with_guardian()

      %{provider: provider, program: program, child: child, parent: parent}
    end

    test "is :not_required when the program has no required waivers", ctx do
      {:ok, _} = enroll(ctx, :deferred)

      assert [%{waiver_status: :not_required}] =
               KlassHero.Enrollment.list_program_enrollments(ctx.program.id)
    end

    test "is :unsigned while a required waiver is outstanding", ctx do
      {_waiver, _version} = require_waiver(ctx)
      {:ok, _} = enroll(ctx, :deferred)

      assert [%{waiver_status: :unsigned}] =
               KlassHero.Enrollment.list_program_enrollments(ctx.program.id)
    end

    test "is :signed once the parent has signed", ctx do
      {_waiver, version} = require_waiver(ctx)
      {:ok, _} = enroll(ctx, {:accepted, [version.id]})

      assert [%{waiver_status: :signed}] =
               KlassHero.Enrollment.list_program_enrollments(ctx.program.id)
    end

    defp require_waiver(%{provider: provider, program: program}) do
      {:ok, %{waiver: waiver, version: version}} =
        KlassHero.Enrollment.create_waiver(provider.id, %{
          program_id: program.id,
          title: "Liability Waiver",
          required: true,
          body: "I agree."
        })

      {waiver, version}
    end

    defp enroll(%{program: program, child: child, parent: parent}, intent) do
      KlassHero.Enrollment.create_enrollment(%{
        program_id: program.id,
        child_id: child.id,
        parent_id: parent.id,
        waivers: intent
      })
    end
  end
end
