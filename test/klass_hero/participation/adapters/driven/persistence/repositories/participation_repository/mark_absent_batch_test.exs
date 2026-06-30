# credo:disable-for-this-file Credo.Check.Readability.MaxLineLength
defmodule KlassHero.Participation.Adapters.Driven.Persistence.Repositories.ParticipationRepository.MarkAbsentBatchTest do
  use KlassHero.DataCase, async: true

  import KlassHero.Factory

  alias KlassHero.Participation.Adapters.Driven.Persistence.Repositories.ParticipationRepository
  alias KlassHero.Participation.ParticipationRecord
  alias KlassHero.Repo

  describe "mark_absent_batch/1" do
    test "returns {:ok, 0} for empty list" do
      assert {:ok, 0} = ParticipationRepository.mark_absent_batch([])
    end

    test "marks all registered records as absent and returns count" do
      session = insert(:program_session_schema, status: :in_progress)
      record1 = insert(:participation_record_schema, session_id: session.id, status: :registered)
      record2 = insert(:participation_record_schema, session_id: session.id, status: :registered)
      record3 = insert(:participation_record_schema, session_id: session.id, status: :registered)

      assert {:ok, 3} =
               ParticipationRepository.mark_absent_batch([record1.id, record2.id, record3.id])

      reloaded_statuses =
        Repo.all(
          from(r in ParticipationRecord,
            where: r.session_id == ^session.id,
            select: r.status
          )
        )

      assert Enum.all?(reloaded_statuses, &(&1 == :absent))
    end

    test "skips non-registered records via WHERE status = :registered guard" do
      session = insert(:program_session_schema, status: :in_progress)
      staff_user = KlassHero.AccountsFixtures.unconfirmed_user_fixture()

      registered = insert(:participation_record_schema, session_id: session.id, status: :registered)

      checked_in =
        insert(:participation_record_schema,
          session_id: session.id,
          status: :checked_in,
          check_in_at: DateTime.utc_now(),
          check_in_by: staff_user.id
        )

      assert {:ok, 1} =
               ParticipationRepository.mark_absent_batch([registered.id, checked_in.id])

      assert Repo.get(ParticipationRecord, registered.id).status == :absent
      assert Repo.get(ParticipationRecord, checked_in.id).status == :checked_in
    end

    test "increments lock_version on updated records" do
      session = insert(:program_session_schema, status: :in_progress)
      record = insert(:participation_record_schema, session_id: session.id, status: :registered)
      original_version = record.lock_version

      assert {:ok, 1} = ParticipationRepository.mark_absent_batch([record.id])

      reloaded = Repo.get(ParticipationRecord, record.id)
      assert reloaded.lock_version == original_version + 1
    end
  end
end
