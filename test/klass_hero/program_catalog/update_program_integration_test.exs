defmodule KlassHero.ProgramCatalog.UpdateProgramIntegrationTest do
  use KlassHero.DataCase

  alias KlassHero.ProgramCatalog
  alias KlassHero.ProgramCatalog.Program
  alias KlassHero.ProviderFixtures
  alias KlassHero.Repo

  describe "update_program/3" do
    setup do
      provider = ProviderFixtures.provider_profile_fixture()

      {:ok, program} =
        ProgramCatalog.create_program(%{
          provider_id: provider.id,
          title: "Original Title",
          description: "Original description",
          category: "sports",
          price: Decimal.new("100.00")
        })

      %{program: program, provider: provider}
    end

    test "updates title successfully", %{program: program, provider: provider} do
      assert {:ok, updated} =
               ProgramCatalog.update_program(provider.id, program.id, %{title: "New Title"})

      assert updated.title == "New Title"
      assert updated.description == "Original description"
    end

    test "sets, changes and clears the subtitle", %{program: program, provider: provider} do
      assert program.subtitle == nil

      assert {:ok, with_subtitle} =
               ProgramCatalog.update_program(provider.id, program.id, %{
                 subtitle: "For beginners, no experience needed"
               })

      assert with_subtitle.subtitle == "For beginners, no experience needed"

      assert {:ok, changed} =
               ProgramCatalog.update_program(provider.id, program.id, %{
                 subtitle: "Small groups, ages 6-9"
               })

      assert changed.subtitle == "Small groups, ages 6-9"

      assert {:ok, cleared} =
               ProgramCatalog.update_program(provider.id, program.id, %{subtitle: nil})

      assert cleared.subtitle == nil
    end

    test "rejects a subtitle over 150 characters", %{program: program, provider: provider} do
      assert {:error, %Ecto.Changeset{} = changeset} =
               ProgramCatalog.update_program(provider.id, program.id, %{
                 subtitle: String.duplicate("a", 151)
               })

      assert errors_on(changeset)[:subtitle]
    end

    test "updates multiple fields", %{program: program, provider: provider} do
      assert {:ok, updated} =
               ProgramCatalog.update_program(provider.id, program.id, %{
                 title: "Updated",
                 price: Decimal.new("200.00")
               })

      assert updated.title == "Updated"
      assert updated.price == Decimal.new("200.00")
    end

    test "rejects invalid changes (empty title)", %{program: program, provider: provider} do
      assert {:error, _} = ProgramCatalog.update_program(provider.id, program.id, %{title: ""})

      # Verify original unchanged
      assert {:ok, unchanged} = ProgramCatalog.get_program_by_id(program.id)
      assert unchanged.title == "Original Title"
    end

    test "returns not_found for invalid ID", %{provider: provider} do
      assert {:error, :not_found} =
               ProgramCatalog.update_program(provider.id, Ecto.UUID.generate(), %{title: "New"})
    end

    test "returns not_found and leaves the row unchanged when another provider owns it", %{
      program: program
    } do
      other = ProviderFixtures.provider_profile_fixture()

      # IDOR guard: a foreign provider_id must not update — and must be
      # indistinguishable from a genuine miss (no existence leak).
      assert {:error, :not_found} =
               ProgramCatalog.update_program(other.id, program.id, %{title: "Hijacked"})

      assert {:ok, unchanged} = ProgramCatalog.get_program_by_id(program.id)
      assert unchanged.title == "Original Title"
    end

    # The dedicated :program_schedule_updated event was deleted in #1141 (an
    # unconsumed duplicate of :program_updated, whose payload is a superset).
    # What the old event tests actually protected — that scheduling changes
    # round-trip through update_program — is asserted on the row instead.
    test "persists scheduling field changes", %{program: program, provider: provider} do
      assert {:ok, _updated} =
               ProgramCatalog.update_program(provider.id, program.id, %{
                 meeting_days: ["Tuesday", "Thursday"],
                 meeting_start_time: ~T[14:00:00],
                 meeting_end_time: ~T[15:30:00]
               })

      assert {:ok, stored} = ProgramCatalog.get_program_by_id(program.id)
      assert stored.meeting_days == ["Tuesday", "Thursday"]
      assert stored.meeting_start_time == ~T[14:00:00]
      assert stored.meeting_end_time == ~T[15:30:00]
    end

    test "optimistic lock raises StaleEntryError on a stale version", %{program: program} do
      # Load the row, then bump its version behind the loaded struct's back.
      stale = Repo.get!(Program, program.id)

      Repo.get!(Program, program.id)
      |> Ecto.Changeset.change(%{})
      |> Ecto.Changeset.force_change(:lock_version, 99)
      |> Repo.update!()

      # update_changeset carries the stale lock_version (1); the DB row is at 99,
      # so the guarded UPDATE matches no rows and Ecto raises. update_program/2
      # rescues this into {:error, :stale_data}.
      assert_raise Ecto.StaleEntryError, fn ->
        stale
        |> Program.update_changeset(%{title: "Stale Edit"})
        |> Repo.update!()
      end
    end
  end
end
