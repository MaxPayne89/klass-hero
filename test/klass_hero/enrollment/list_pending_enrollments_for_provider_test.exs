defmodule KlassHero.Enrollment.ListPendingEnrollmentsForProviderTest do
  use KlassHero.DataCase, async: true

  import KlassHero.Factory

  describe "execute/1" do
    test "returns [] for empty program_ids" do
      assert KlassHero.Enrollment.list_pending_enrollments_for_provider([]) == []
    end

    test "returns enriched entries for pending enrollments in the given programs" do
      provider = insert(:provider_profile_schema)
      program = insert(:program_schema, provider_id: provider.id, title: "Soccer Camp")
      {child, parent} = insert_child_with_guardian(first_name: "Ada", last_name: "Lovelace")

      enrollment =
        insert(:enrollment_schema,
          program_id: program.id,
          parent_id: parent.id,
          child_id: child.id,
          status: :pending
        )

      [entry] = KlassHero.Enrollment.list_pending_enrollments_for_provider([program.id])

      assert entry.enrollment_id == enrollment.id
      assert entry.program_id == program.id
      assert entry.program_title == "Soccer Camp"
      assert entry.child_id == to_string(child.id)
      assert entry.child_name == "Ada Lovelace"
      assert entry.parent_id == to_string(parent.id)
      assert %DateTime{} = entry.enrolled_at
    end

    test "excludes non-pending enrollments" do
      provider = insert(:provider_profile_schema)
      program = insert(:program_schema, provider_id: provider.id)

      {child1, parent1} = insert_child_with_guardian()
      {child2, parent2} = insert_child_with_guardian()
      {child3, parent3} = insert_child_with_guardian()

      insert(:enrollment_schema, program_id: program.id, child_id: child1.id, parent_id: parent1.id, status: :confirmed)
      insert(:enrollment_schema, program_id: program.id, child_id: child2.id, parent_id: parent2.id, status: :cancelled)
      insert(:enrollment_schema, program_id: program.id, child_id: child3.id, parent_id: parent3.id, status: :completed)

      assert KlassHero.Enrollment.list_pending_enrollments_for_provider([program.id]) == []
    end

    test "gracefully handles missing child and program metadata" do
      # Trigger: enrollment exists but its program has been deleted (simulate orphan via FK bypass)
      # Why: program_id FK is :restrict so we insert real records then delete the program to orphan
      # Outcome: entry.program_title falls back to "Unknown"; child_name falls back to "Unknown"
      provider = insert(:provider_profile_schema)
      program = insert(:program_schema, provider_id: provider.id)
      {child, parent} = insert_child_with_guardian()

      enrollment =
        insert(:enrollment_schema,
          program_id: program.id,
          child_id: child.id,
          parent_id: parent.id,
          status: :pending
        )

      program_id = program.id
      program_id_bin = Ecto.UUID.dump!(program.id)
      child_id_bin = Ecto.UUID.dump!(child.id)

      # Disable FK checks so we can orphan the enrollment
      KlassHero.Repo.query!("SET session_replication_role = 'replica'")
      KlassHero.Repo.query!("DELETE FROM children_guardians WHERE child_id = $1", [child_id_bin])
      KlassHero.Repo.query!("DELETE FROM children WHERE id = $1", [child_id_bin])
      KlassHero.Repo.query!("DELETE FROM programs WHERE id = $1", [program_id_bin])
      KlassHero.Repo.query!("SET session_replication_role = 'origin'")

      [entry] = KlassHero.Enrollment.list_pending_enrollments_for_provider([program_id])

      assert entry.enrollment_id == enrollment.id
      assert entry.child_name == "Unknown"
      assert entry.program_title == "Unknown"
    end
  end

  describe "execute/1 with provider_id (binary)" do
    @non_pending_statuses [:confirmed, :cancelled, :completed]

    test "returns enriched entries for the provider's pending enrollments" do
      provider = insert(:provider_profile_schema)
      program = insert(:program_schema, provider_id: provider.id, title: "Soccer Camp")
      {child, parent} = insert_child_with_guardian(first_name: "Ada", last_name: "Lovelace")

      enrollment =
        insert(:enrollment_schema,
          program_id: program.id,
          parent_id: parent.id,
          child_id: child.id,
          status: :pending
        )

      [entry] = KlassHero.Enrollment.list_pending_enrollments_for_provider(provider.id)

      assert entry.enrollment_id == enrollment.id
      assert entry.program_id == program.id
      assert entry.program_title == "Soccer Camp"
      assert entry.child_name == "Ada Lovelace"
    end

    test "excludes non-pending enrollments" do
      provider = insert(:provider_profile_schema)
      program = insert(:program_schema, provider_id: provider.id)

      for status <- @non_pending_statuses do
        {child, parent} = insert_child_with_guardian()

        insert(:enrollment_schema,
          program_id: program.id,
          child_id: child.id,
          parent_id: parent.id,
          status: status
        )
      end

      assert KlassHero.Enrollment.list_pending_enrollments_for_provider(provider.id) == []
    end

    test "excludes other providers' pending enrollments (provider isolation)" do
      provider_a = insert(:provider_profile_schema)
      provider_b = insert(:provider_profile_schema)
      program_a = insert(:program_schema, provider_id: provider_a.id)
      program_b = insert(:program_schema, provider_id: provider_b.id)
      {child_a, parent_a} = insert_child_with_guardian()
      {child_b, parent_b} = insert_child_with_guardian()

      enrollment_a =
        insert(:enrollment_schema,
          program_id: program_a.id,
          child_id: child_a.id,
          parent_id: parent_a.id,
          status: :pending
        )

      # provider_b's pending enrollment — must NOT leak into provider_a's result
      insert(:enrollment_schema,
        program_id: program_b.id,
        child_id: child_b.id,
        parent_id: parent_b.id,
        status: :pending
      )

      entries = KlassHero.Enrollment.list_pending_enrollments_for_provider(provider_a.id)

      # Exactly one row, and it is provider_a's — a bare length check would pass
      # even if the single row were provider_b's leaked in, so pin the identity.
      assert [%{enrollment_id: id}] = entries
      assert id == enrollment_a.id
    end
  end
end
