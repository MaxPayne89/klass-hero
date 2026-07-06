defmodule KlassHero.Participation.GetSessionWithRosterTest do
  @moduledoc """
  Integration tests for GetSessionWithRoster use case.

  Tests retrieving a session with its participation roster.
  """

  use KlassHero.DataCase, async: true

  import KlassHero.Factory

  alias KlassHero.Participation.ParticipationRecord
  alias KlassHero.Participation.ProgramSession

  describe "execute/1" do
    test "returns session with roster entries" do
      session_schema = insert(:program_session_schema)
      child1 = insert(:child_schema)
      child2 = insert(:child_schema)

      insert(:participation_record_schema,
        session_id: session_schema.id,
        child_id: child1.id,
        status: :registered
      )

      insert(:participation_record_schema,
        session_id: session_schema.id,
        child_id: child2.id,
        status: :checked_in,
        check_in_at: DateTime.utc_now(),
        check_in_by: KlassHero.AccountsFixtures.unconfirmed_user_fixture().id
      )

      assert {:ok, result} = KlassHero.Participation.get_session_with_roster(session_schema.id)
      assert %ProgramSession{} = result.session
      assert result.session.id == session_schema.id
      assert is_list(result.roster)
      assert length(result.roster) == 2

      assert Enum.all?(result.roster, fn entry -> match?(%ParticipationRecord{}, entry.record) end)
    end

    test "returns session with empty roster when no participation records" do
      session_schema = insert(:program_session_schema)

      assert {:ok, result} = KlassHero.Participation.get_session_with_roster(session_schema.id)
      assert %ProgramSession{} = result.session
      assert result.roster == []
    end

    test "returns error when session not found" do
      non_existent_id = Ecto.UUID.generate()

      assert {:error, :not_found} = KlassHero.Participation.get_session_with_roster(non_existent_id)
    end

    test "includes child name in roster entries" do
      session_schema = insert(:program_session_schema)
      child = insert(:child_schema)
      check_in_time = DateTime.utc_now()

      insert(:participation_record_schema,
        session_id: session_schema.id,
        child_id: child.id,
        status: :checked_in,
        check_in_at: check_in_time,
        check_in_by: KlassHero.AccountsFixtures.unconfirmed_user_fixture().id,
        check_in_notes: "Arrived on time"
      )

      assert {:ok, result} = KlassHero.Participation.get_session_with_roster(session_schema.id)
      assert [entry] = result.roster
      assert entry.record.child_id == child.id
      assert entry.record.status == :checked_in
      assert entry.record.check_in_notes == "Arrived on time"
      assert is_binary(entry.child_name)
    end

    test "only returns roster for specified session" do
      session1 = insert(:program_session_schema)
      session2 = insert(:program_session_schema)
      child = insert(:child_schema)

      insert(:participation_record_schema,
        session_id: session1.id,
        child_id: child.id,
        status: :registered
      )

      insert(:participation_record_schema,
        session_id: session2.id,
        child_id: child.id,
        status: :checked_in,
        check_in_at: DateTime.utc_now(),
        check_in_by: KlassHero.AccountsFixtures.unconfirmed_user_fixture().id
      )

      assert {:ok, result} = KlassHero.Participation.get_session_with_roster(session1.id)
      assert length(result.roster) == 1
      assert hd(result.roster).record.session_id == session1.id
    end
  end

  describe "execute_enriched/1" do
    test "returns session with participation_records attached" do
      session_schema = insert(:program_session_schema)
      child = insert(:child_schema)

      insert(:participation_record_schema,
        session_id: session_schema.id,
        child_id: child.id,
        status: :registered
      )

      assert {:ok, session} = KlassHero.Participation.get_session_with_roster_enriched(session_schema.id)
      assert is_map(session)
      assert session.id == session_schema.id
      assert is_list(session.participation_records)
      assert length(session.participation_records) == 1
    end

    test "resolves program_name via the ProgramCatalog facade" do
      program = insert(:program_schema, title: "Chess Club")
      session_schema = insert(:program_session_schema, program_id: program.id)

      assert {:ok, session} = KlassHero.Participation.get_session_with_roster_enriched(session_schema.id)
      assert session.program_name == "Chess Club"
    end

    test "returns error when session not found" do
      non_existent_id = Ecto.UUID.generate()

      assert {:error, :not_found} = KlassHero.Participation.get_session_with_roster_enriched(non_existent_id)
    end

    test "enriched records include safety info when child has active consent" do
      parent = insert(:parent_profile_schema)

      {child, _parent} =
        insert_child_with_guardian(
          parent: parent,
          allergies: "Peanuts",
          support_needs: "Wheelchair access",
          emergency_contact: "+49 123 456789"
        )

      insert(:consent_schema,
        parent_id: parent.id,
        child_id: child.id,
        consent_type: "provider_data_sharing"
      )

      session_schema = insert(:program_session_schema)

      insert(:participation_record_schema,
        session_id: session_schema.id,
        child_id: child.id,
        parent_id: parent.id,
        status: :registered
      )

      assert {:ok, session} = KlassHero.Participation.get_session_with_roster_enriched(session_schema.id)
      assert [record] = session.participation_records
      assert record.allergies == "Peanuts"
      assert record.support_needs == "Wheelchair access"
      assert record.emergency_contact == "+49 123 456789"
    end

    test "enriched records have nil safety fields when no consent" do
      child = insert(:child_schema, allergies: "Peanuts", support_needs: "ADHD")
      session_schema = insert(:program_session_schema)

      insert(:participation_record_schema,
        session_id: session_schema.id,
        child_id: child.id,
        status: :registered
      )

      assert {:ok, session} = KlassHero.Participation.get_session_with_roster_enriched(session_schema.id)
      assert [record] = session.participation_records
      assert record.allergies == nil
      assert record.support_needs == nil
      assert record.emergency_contact == nil
    end

    test "mixed roster: some children consented, some not" do
      # Child with consent
      parent1 = insert(:parent_profile_schema)

      {child_with_consent, _parent1} =
        insert_child_with_guardian(
          parent: parent1,
          allergies: "Dairy"
        )

      insert(:consent_schema,
        parent_id: parent1.id,
        child_id: child_with_consent.id,
        consent_type: "provider_data_sharing"
      )

      # Child without consent
      child_without_consent = insert(:child_schema, allergies: "Gluten")

      session_schema = insert(:program_session_schema)

      insert(:participation_record_schema,
        session_id: session_schema.id,
        child_id: child_with_consent.id,
        parent_id: parent1.id,
        status: :registered
      )

      insert(:participation_record_schema,
        session_id: session_schema.id,
        child_id: child_without_consent.id,
        status: :registered
      )

      assert {:ok, session} = KlassHero.Participation.get_session_with_roster_enriched(session_schema.id)
      assert length(session.participation_records) == 2

      consented_record =
        Enum.find(session.participation_records, &(&1.child_id == child_with_consent.id))

      non_consented_record =
        Enum.find(session.participation_records, &(&1.child_id == child_without_consent.id))

      assert consented_record.allergies == "Dairy"
      assert non_consented_record.allergies == nil
    end
  end

  describe "execute/1 roster entries include safety info" do
    test "roster entries include safety fields when child has consent" do
      parent = insert(:parent_profile_schema)

      {child, _parent} =
        insert_child_with_guardian(
          parent: parent,
          allergies: "Nuts",
          emergency_contact: "Mom: +49 111"
        )

      insert(:consent_schema,
        parent_id: parent.id,
        child_id: child.id,
        consent_type: "provider_data_sharing"
      )

      session_schema = insert(:program_session_schema)

      insert(:participation_record_schema,
        session_id: session_schema.id,
        child_id: child.id,
        parent_id: parent.id,
        status: :registered
      )

      assert {:ok, result} = KlassHero.Participation.get_session_with_roster(session_schema.id)
      assert [entry] = result.roster
      assert entry.allergies == "Nuts"
      assert entry.emergency_contact == "Mom: +49 111"
      assert entry.support_needs == nil
    end

    test "roster entries have nil safety fields when no consent" do
      child = insert(:child_schema, allergies: "Peanuts")
      session_schema = insert(:program_session_schema)

      insert(:participation_record_schema,
        session_id: session_schema.id,
        child_id: child.id,
        status: :registered
      )

      assert {:ok, result} = KlassHero.Participation.get_session_with_roster(session_schema.id)
      assert [entry] = result.roster
      assert entry.allergies == nil
      assert entry.support_needs == nil
      assert entry.emergency_contact == nil
    end
  end

  describe "behavioral notes in roster" do
    test "enriched records include approved behavioral notes when consented" do
      parent = insert(:parent_profile_schema)

      {child, _parent} =
        insert_child_with_guardian(
          parent: parent,
          allergies: "Peanuts"
        )

      insert(:consent_schema,
        parent_id: parent.id,
        child_id: child.id,
        consent_type: "provider_data_sharing"
      )

      session_schema = insert(:program_session_schema)

      record =
        insert(:participation_record_schema,
          session_id: session_schema.id,
          child_id: child.id,
          parent_id: parent.id,
          status: :checked_in,
          check_in_at: DateTime.utc_now(),
          check_in_by: KlassHero.AccountsFixtures.unconfirmed_user_fixture().id
        )

      insert(:behavioral_note_schema,
        participation_record_id: record.id,
        child_id: child.id,
        parent_id: parent.id,
        status: :approved,
        reviewed_at: DateTime.utc_now() |> DateTime.truncate(:second)
      )

      assert {:ok, session} = KlassHero.Participation.get_session_with_roster_enriched(session_schema.id)
      assert [enriched] = session.participation_records
      assert length(enriched.behavioral_notes) == 1
      assert hd(enriched.behavioral_notes).status == :approved
    end

    test "enriched records have empty behavioral notes when no consent" do
      child = insert(:child_schema, allergies: "Peanuts")
      session_schema = insert(:program_session_schema)

      record =
        insert(:participation_record_schema,
          session_id: session_schema.id,
          child_id: child.id,
          status: :checked_in,
          check_in_at: DateTime.utc_now(),
          check_in_by: KlassHero.AccountsFixtures.unconfirmed_user_fixture().id
        )

      insert(:behavioral_note_schema,
        participation_record_id: record.id,
        child_id: child.id,
        status: :approved,
        reviewed_at: DateTime.utc_now() |> DateTime.truncate(:second)
      )

      assert {:ok, session} = KlassHero.Participation.get_session_with_roster_enriched(session_schema.id)
      assert [enriched] = session.participation_records
      assert enriched.behavioral_notes == []
    end

    test "roster entries include approved behavioral notes when consented" do
      parent = insert(:parent_profile_schema)

      {child, _parent} =
        insert_child_with_guardian(
          parent: parent,
          allergies: "Nuts"
        )

      insert(:consent_schema,
        parent_id: parent.id,
        child_id: child.id,
        consent_type: "provider_data_sharing"
      )

      session_schema = insert(:program_session_schema)

      record =
        insert(:participation_record_schema,
          session_id: session_schema.id,
          child_id: child.id,
          parent_id: parent.id,
          status: :registered
        )

      insert(:behavioral_note_schema,
        participation_record_id: record.id,
        child_id: child.id,
        parent_id: parent.id,
        status: :approved,
        reviewed_at: DateTime.utc_now() |> DateTime.truncate(:second)
      )

      assert {:ok, result} = KlassHero.Participation.get_session_with_roster(session_schema.id)
      assert [entry] = result.roster
      assert length(entry.behavioral_notes) == 1
    end

    test "roster entries have empty behavioral notes when no consent" do
      child = insert(:child_schema)
      session_schema = insert(:program_session_schema)

      record =
        insert(:participation_record_schema,
          session_id: session_schema.id,
          child_id: child.id,
          status: :registered
        )

      insert(:behavioral_note_schema,
        participation_record_id: record.id,
        child_id: child.id,
        status: :approved,
        reviewed_at: DateTime.utc_now() |> DateTime.truncate(:second)
      )

      assert {:ok, result} = KlassHero.Participation.get_session_with_roster(session_schema.id)
      assert [entry] = result.roster
      assert entry.behavioral_notes == []
    end

    test "only approved notes appear in enriched records (pending excluded)" do
      parent = insert(:parent_profile_schema)

      {child, _parent} =
        insert_child_with_guardian(parent: parent)

      insert(:consent_schema,
        parent_id: parent.id,
        child_id: child.id,
        consent_type: "provider_data_sharing"
      )

      session_schema = insert(:program_session_schema)

      record =
        insert(:participation_record_schema,
          session_id: session_schema.id,
          child_id: child.id,
          parent_id: parent.id,
          status: :checked_in,
          check_in_at: DateTime.utc_now(),
          check_in_by: KlassHero.AccountsFixtures.unconfirmed_user_fixture().id
        )

      # Approved note — should appear
      insert(:behavioral_note_schema,
        participation_record_id: record.id,
        child_id: child.id,
        parent_id: parent.id,
        status: :approved,
        reviewed_at: DateTime.utc_now() |> DateTime.truncate(:second)
      )

      # Pending note — should NOT appear
      insert(:behavioral_note_schema,
        participation_record_id: record.id,
        child_id: child.id,
        parent_id: parent.id,
        status: :pending_approval
      )

      assert {:ok, session} = KlassHero.Participation.get_session_with_roster_enriched(session_schema.id)
      assert [enriched] = session.participation_records
      assert length(enriched.behavioral_notes) == 1
      assert hd(enriched.behavioral_notes).status == :approved
    end
  end
end
