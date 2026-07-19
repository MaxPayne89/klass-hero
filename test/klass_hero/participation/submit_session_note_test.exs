defmodule KlassHero.Participation.SubmitSessionNoteTest do
  @moduledoc """
  Integration tests for SubmitSessionNote use case.
  """

  use KlassHero.DataCase, async: true

  import KlassHero.EventTestHelper
  import KlassHero.Factory

  alias KlassHero.Participation
  alias KlassHero.Participation.Adapters.Driving.Events.EventHandlers.NotifyLiveViews
  alias KlassHero.Participation.Domain.Events.ParticipationEvents
  alias KlassHero.Participation.SessionNote

  describe "execute/1" do
    test "submits a session note for a checked-in record" do
      staff_user = KlassHero.AccountsFixtures.unconfirmed_user_fixture()

      record =
        insert(:participation_record_schema,
          status: :checked_in,
          check_in_at: DateTime.utc_now(),
          check_in_by: staff_user.id
        )

      provider_id = insert(:provider_profile_schema).id

      assert {:ok, note} =
               KlassHero.Participation.submit_session_note(%{
                 participation_record_id: record.id,
                 provider_id: provider_id,
                 content: "Child was very engaged today"
               })

      assert note.status == :pending_approval
      assert note.content == "Child was very engaged today"
      assert note.child_id == record.child_id
      assert note.parent_id == record.parent_id
      assert note.provider_id == provider_id
    end

    test "submits a session note for a checked-out record" do
      staff_user = KlassHero.AccountsFixtures.unconfirmed_user_fixture()

      record =
        insert(:participation_record_schema,
          status: :checked_out,
          check_in_at: DateTime.add(DateTime.utc_now(), -3600, :second),
          check_in_by: staff_user.id,
          check_out_at: DateTime.utc_now(),
          check_out_by: staff_user.id
        )

      assert {:ok, note} =
               KlassHero.Participation.submit_session_note(%{
                 participation_record_id: record.id,
                 provider_id: insert(:provider_profile_schema).id,
                 content: "Well behaved"
               })

      assert note.status == :pending_approval
    end

    test "returns error for registered record" do
      record = insert(:participation_record_schema, status: :registered)

      assert {:error, :invalid_record_status} =
               KlassHero.Participation.submit_session_note(%{
                 participation_record_id: record.id,
                 provider_id: Ecto.UUID.generate(),
                 content: "Some note"
               })
    end

    test "returns error for absent record" do
      record = insert(:participation_record_schema, status: :absent)

      assert {:error, :invalid_record_status} =
               KlassHero.Participation.submit_session_note(%{
                 participation_record_id: record.id,
                 provider_id: Ecto.UUID.generate(),
                 content: "Some note"
               })
    end

    test "returns error for non-existent record" do
      assert {:error, :not_found} =
               KlassHero.Participation.submit_session_note(%{
                 participation_record_id: Ecto.UUID.generate(),
                 provider_id: Ecto.UUID.generate(),
                 content: "Some note"
               })
    end

    test "returns error for blank content" do
      record =
        insert(:participation_record_schema,
          status: :checked_in,
          check_in_at: DateTime.utc_now(),
          check_in_by: KlassHero.AccountsFixtures.unconfirmed_user_fixture().id
        )

      assert {:error, :blank_content} =
               KlassHero.Participation.submit_session_note(%{
                 participation_record_id: record.id,
                 provider_id: Ecto.UUID.generate(),
                 content: "   "
               })
    end

    test "returns error for duplicate note from same provider" do
      record =
        insert(:participation_record_schema,
          status: :checked_in,
          check_in_at: DateTime.utc_now(),
          check_in_by: KlassHero.AccountsFixtures.unconfirmed_user_fixture().id
        )

      provider_id = insert(:provider_profile_schema).id

      assert {:ok, _} =
               KlassHero.Participation.submit_session_note(%{
                 participation_record_id: record.id,
                 provider_id: provider_id,
                 content: "First note"
               })

      assert {:error, :duplicate_note} =
               KlassHero.Participation.submit_session_note(%{
                 participation_record_id: record.id,
                 provider_id: provider_id,
                 content: "Second note"
               })
    end
  end

  describe "session_notes constraint names" do
    # Ecto infers foreign-key constraint names from the schema source, so the
    # `behavioral_notes_*` constraints had to be renamed alongside the table
    # (#924). If a name drifts, Ecto stops recognising the violation and raises
    # Postgrex.Error instead of returning a changeset — invisible to every
    # happy-path test.

    setup do
      record = insert(:participation_record_schema)
      %{record: record, provider_id: insert(:provider_profile_schema).id}
    end

    defp note_attrs(overrides) do
      Map.merge(
        %{
          participation_record_id: Ecto.UUID.generate(),
          child_id: Ecto.UUID.generate(),
          provider_id: Ecto.UUID.generate(),
          content: "Engaged throughout",
          status: :pending_approval,
          submitted_at: DateTime.utc_now() |> DateTime.truncate(:second)
        },
        overrides
      )
    end

    test "a missing participation record errors the changeset", %{
      record: record,
      provider_id: provider_id
    } do
      attrs =
        note_attrs(%{
          child_id: record.child_id,
          provider_id: provider_id,
          participation_record_id: Ecto.UUID.generate()
        })

      assert {:error, changeset} = attrs |> SessionNote.create_changeset() |> Repo.insert()
      assert "does not exist" in errors_on(changeset).participation_record_id
    end

    test "a missing child errors the changeset", %{record: record, provider_id: provider_id} do
      attrs =
        note_attrs(%{
          participation_record_id: record.id,
          provider_id: provider_id,
          child_id: Ecto.UUID.generate()
        })

      assert {:error, changeset} = attrs |> SessionNote.create_changeset() |> Repo.insert()
      assert "does not exist" in errors_on(changeset).child_id
    end
  end

  describe "session_note PubSub topics (#1108)" do
    # Proves publisher and subscriber meet: publish each session-note event through
    # the real handler, then assert the topic it was actually broadcast on is one the
    # LiveViews subscribe to (`Participation.participation_topics(:session_note)`).
    # Both sides derive from the event registry, so a rename that touches only one
    # side fails here instead of silently in production. Supersedes #924's literal
    # pins now that TestEventPublisher records the topic.

    setup do
      setup_test_events()
      %{note: build(:session_note)}
    end

    @topic_cases [
      {:session_note_submitted, "session_note:session_note_submitted"},
      {:session_note_approved, "session_note:session_note_approved"},
      {:session_note_rejected, "session_note:session_note_rejected"}
    ]

    for {event_type, expected_topic} <- @topic_cases do
      test "#{event_type} is published to a topic the LiveViews subscribe to", %{note: note} do
        event = apply(ParticipationEvents, unquote(event_type), [note])

        NotifyLiveViews.handle(event)

        assert_published_to(unquote(event_type), unquote(expected_topic))
        assert unquote(expected_topic) in Participation.participation_topics(:session_note)
      end
    end
  end
end
