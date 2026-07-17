# Remediation script for issue #299: Duplicate Child on Parent Profile
#
# Identifies duplicate children per guardian (same first_name, last_name, date_of_birth)
# and merges them into a single survivor record.
#
# Usage (via fly ssh console with rpc):
#   DRY RUN (default -- logs only, no changes):
#   fly ssh console -a klass-hero-dev -C "/app/bin/klass_hero rpc '[path] = Path.wildcard(\"/app/lib/klass_hero-*/priv/repo/scripts/remediate_duplicate_children.exs\"); Code.eval_file(path)'"
#
#   EXECUTE (edit dry_run to false first, redeploy, then run same command)

import Ecto.Query

alias KlassHero.Repo

dry_run = true
IO.puts("[Remediate] Mode: #{if dry_run, do: "DRY RUN", else: "EXECUTE"}\n")

# Step 1: Find duplicate groups
duplicate_groups =
  from(cg in "children_guardians",
    join: c in "children",
    on: c.id == cg.child_id,
    where: not is_nil(c.date_of_birth),
    group_by: [
      cg.guardian_id,
      fragment("lower(?)", c.first_name),
      fragment("lower(?)", c.last_name),
      c.date_of_birth
    ],
    having: count(c.id) > 1,
    select: %{
      guardian_id: cg.guardian_id,
      first_name_lower: fragment("lower(?)", c.first_name),
      last_name_lower: fragment("lower(?)", c.last_name),
      date_of_birth: c.date_of_birth,
      count: count(c.id)
    }
  )
  |> Repo.all()

IO.puts("[Remediate] Found #{length(duplicate_groups)} duplicate group(s)")

if duplicate_groups == [] do
  IO.puts("[Remediate] Nothing to do.")
else
  mergeable_fields = [:emergency_contact, :support_needs, :allergies, :school_name, :school_grade]

  results =
    for group <- duplicate_groups do
      IO.puts(
        "\n--- #{group.first_name_lower} #{group.last_name_lower} " <>
          "(DOB: #{group.date_of_birth}) -- #{group.count} copies ---"
      )

      children_in_group =
        from(c in "children",
          join: cg in "children_guardians",
          on: c.id == cg.child_id,
          where:
            cg.guardian_id == ^group.guardian_id and
              fragment("lower(?)", c.first_name) == ^group.first_name_lower and
              fragment("lower(?)", c.last_name) == ^group.last_name_lower and
              c.date_of_birth == ^group.date_of_birth,
          order_by: [asc: c.inserted_at],
          select: map(c, ^([:id, :inserted_at] ++ mergeable_fields))
        )
        |> Repo.all()

      # Trigger: multiple children match the same (name, dob) for this guardian
      # Why: oldest record chosen as survivor to preserve longest-standing enrollments/consent history
      # Outcome: first-inserted child kept; newer duplicates merged into it.
      #   Relies on order_by: [asc: c.inserted_at] above to guarantee head = oldest.
      [survivor | duplicates] = children_in_group
      IO.puts("  Survivor:   #{Ecto.UUID.cast!(survivor.id)} (#{survivor.inserted_at})")

      for dup <- duplicates,
          do: IO.puts("  Duplicate:  #{Ecto.UUID.cast!(dup.id)} (#{dup.inserted_at})")

      if dry_run do
        :skipped
      else
        case Repo.transaction(fn ->
               duplicate_ids = Enum.map(duplicates, & &1.id)

               # 1. Merge non-null fields into survivor
               merged =
                 Enum.reduce(duplicates, %{}, fn dup, acc ->
                   Enum.reduce(mergeable_fields, acc, fn field, inner ->
                     if is_nil(Map.get(survivor, field)) && !is_nil(Map.get(dup, field)) do
                       Map.put(inner, field, Map.get(dup, field))
                     else
                       inner
                     end
                   end)
                 end)

               if merged != %{} do
                 from(c in "children", where: c.id == ^survivor.id)
                 |> Repo.update_all(set: Enum.to_list(merged))

                 IO.puts("  Merged fields: #{inspect(Map.keys(merged))}")
               end

               # 2. Re-point enrollments (delete dup's if survivor already enrolled in same program)
               survivor_programs =
                 from(e in "enrollments", where: e.child_id == ^survivor.id, select: e.program_id)
                 |> Repo.all()

               if survivor_programs != [] do
                 from(e in "enrollments",
                   where: e.child_id in ^duplicate_ids and e.program_id in ^survivor_programs
                 )
                 |> Repo.delete_all()
               end

               {enrolled, _} =
                 from(e in "enrollments", where: e.child_id in ^duplicate_ids)
                 |> Repo.update_all(set: [child_id: survivor.id])

               IO.puts("  Re-pointed #{enrolled} enrollment(s)")

               # 3. Re-point consents (delete dup's conflicting active consents first)
               active_types =
                 from(c in "consents",
                   where: c.child_id == ^survivor.id and is_nil(c.withdrawn_at),
                   select: c.consent_type
                 )
                 |> Repo.all()

               if active_types != [] do
                 from(c in "consents",
                   where:
                     c.child_id in ^duplicate_ids and
                       c.consent_type in ^active_types and
                       is_nil(c.withdrawn_at)
                 )
                 |> Repo.delete_all()
               end

               from(c in "consents", where: c.child_id in ^duplicate_ids)
               |> Repo.update_all(set: [child_id: survivor.id])

               IO.puts("  Re-pointed consents")

               # 4. Re-point participation records (delete dup's conflicting sessions)
               survivor_sessions =
                 from(p in "participation_records",
                   where: p.child_id == ^survivor.id,
                   select: p.session_id
                 )
                 |> Repo.all()

               if survivor_sessions != [] do
                 from(p in "participation_records",
                   where: p.child_id in ^duplicate_ids and p.session_id in ^survivor_sessions
                 )
                 |> Repo.delete_all()
               end

               from(p in "participation_records", where: p.child_id in ^duplicate_ids)
               |> Repo.update_all(set: [child_id: survivor.id])

               IO.puts("  Re-pointed participation records")

               # 5. Re-point session notes (no unique constraint;
               #    if duplicates had notes on different participation records, both are preserved)
               {notes, _} =
                 from(b in "session_notes", where: b.child_id in ^duplicate_ids)
                 |> Repo.update_all(set: [child_id: survivor.id])

               IO.puts("  Re-pointed #{notes} session note(s)")

               # 6. Delete duplicate guardian links and child records
               # Note: covers enrollments, consents, participation_records, session_notes.
               # If a new FK to children.id is added later, the transaction will roll back
               # with a constraint error (visible in the summary below).
               from(cg in "children_guardians", where: cg.child_id in ^duplicate_ids)
               |> Repo.delete_all()

               {deleted, _} =
                 from(c in "children", where: c.id in ^duplicate_ids)
                 |> Repo.delete_all()

               IO.puts("  Deleted #{deleted} duplicate(s)")
             end) do
          {:ok, _} ->
            IO.puts("  [OK] Group remediated successfully")
            :ok

          {:error, reason} ->
            IO.puts("  [FAILED] Transaction rolled back: #{inspect(reason)}")
            :error
        end
      end
    end

  succeeded = Enum.count(results, &(&1 == :ok))
  failed = Enum.count(results, &(&1 == :error))

  IO.puts("\n[Remediate] Complete: #{succeeded} succeeded, #{failed} failed")
end
