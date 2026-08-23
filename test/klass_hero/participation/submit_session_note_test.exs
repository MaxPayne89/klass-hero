defmodule KlassHero.Participation.SubmitSessionNoteTest do
  @moduledoc """
  Integration tests for SubmitSessionNote use case.
  """

  use KlassHero.DataCase, async: true

  import KlassHero.Factory

  alias KlassHero.Accounts.Scope
  alias KlassHero.AccountsFixtures
  alias KlassHero.Participation
  alias KlassHero.Participation.Domain.Events.ParticipationEvents
  alias KlassHero.Participation.Notifications
  alias KlassHero.Participation.SessionNote
  alias KlassHero.ProviderFixtures

  describe "submit_session_note/2" do
    setup do
      user = AccountsFixtures.unconfirmed_user_fixture()

      # The session's program must have a real owner: authorization follows the
      # role the context derives from the caller's scope (#1329), so provider
      # ownership and staff assignment have to actually exist to be found.
      provider = ProviderFixtures.provider_profile_fixture()
      program = insert(:program_schema, provider_id: provider.id)
      session = insert(:program_session_schema, program_id: program.id, status: "in_progress")

      staff = ProviderFixtures.staff_member_fixture(%{provider_id: provider.id})

      ProviderFixtures.program_assignment_fixture(%{
        provider_id: provider.id,
        staff_member_id: staff.id,
        program_id: program.id
      })

      {child, parent} = insert_child_with_guardian()

      record =
        insert(:participation_record_schema,
          session_id: session.id,
          child_id: child.id,
          parent_id: parent.id,
          status: :checked_in,
          check_in_at: DateTime.utc_now(),
          check_in_by: user.id
        )

      %{
        record: record,
        session: session,
        provider: provider,
        user: user,
        provider_scope: %Scope{user: user, provider: provider},
        staff_scope: %Scope{user: user, staff_member: staff},
        admin_scope: AccountsFixtures.admin_scope_fixture()
      }
    end

    test "submits a session note for a checked-in record", %{
      record: record,
      provider: provider,
      provider_scope: scope
    } do
      assert {:ok, note} =
               Participation.submit_session_note(scope, %{
                 participation_record_id: record.id,
                 content: "Child was very engaged today"
               })

      assert note.status == :pending_approval
      assert note.content == "Child was very engaged today"
      assert note.child_id == record.child_id
      assert note.provider_id == provider.id
    end

    test "submits a session note for a checked-out record", %{
      session: session,
      user: user,
      provider_scope: scope
    } do
      {child, parent} = insert_child_with_guardian()

      record =
        insert(:participation_record_schema,
          session_id: session.id,
          child_id: child.id,
          parent_id: parent.id,
          status: :checked_out,
          check_in_at: DateTime.add(DateTime.utc_now(), -3600, :second),
          check_in_by: user.id,
          check_out_at: DateTime.utc_now(),
          check_out_by: user.id
        )

      assert {:ok, note} =
               Participation.submit_session_note(scope, %{
                 participation_record_id: record.id,
                 content: "Well behaved"
               })

      assert note.status == :pending_approval
    end

    test "returns error for registered record", %{session: session, provider_scope: scope} do
      {child, parent} = insert_child_with_guardian()

      record =
        insert(:participation_record_schema,
          session_id: session.id,
          child_id: child.id,
          parent_id: parent.id,
          status: :registered
        )

      assert {:error, :invalid_record_status} =
               Participation.submit_session_note(scope, %{
                 participation_record_id: record.id,
                 content: "Some note"
               })
    end

    test "returns error for absent record", %{session: session, provider_scope: scope} do
      {child, parent} = insert_child_with_guardian()

      record =
        insert(:participation_record_schema,
          session_id: session.id,
          child_id: child.id,
          parent_id: parent.id,
          status: :absent
        )

      assert {:error, :invalid_record_status} =
               Participation.submit_session_note(scope, %{
                 participation_record_id: record.id,
                 content: "Some note"
               })
    end

    test "returns error for non-existent record", %{provider_scope: scope} do
      assert {:error, :not_found} =
               Participation.submit_session_note(scope, %{
                 participation_record_id: Ecto.UUID.generate(),
                 content: "Some note"
               })
    end

    test "returns error for blank content", %{record: record, provider_scope: scope} do
      assert {:error, :blank_content} =
               Participation.submit_session_note(scope, %{
                 participation_record_id: record.id,
                 content: "   "
               })
    end

    test "returns error for duplicate note from same provider", %{
      record: record,
      provider_scope: scope
    } do
      assert {:ok, _} =
               Participation.submit_session_note(scope, %{
                 participation_record_id: record.id,
                 content: "First note"
               })

      assert {:error, :duplicate_note} =
               Participation.submit_session_note(scope, %{
                 participation_record_id: record.id,
                 content: "Second note"
               })
    end

    test "refuses a provider who does not own the session's program", %{
      record: record,
      user: user
    } do
      other_provider = ProviderFixtures.provider_profile_fixture()

      assert {:error, :unauthorized} =
               Participation.submit_session_note(
                 %Scope{user: user, provider: other_provider},
                 %{participation_record_id: record.id, content: "Not mine to write"}
               )
    end

    test "refuses an actor with no persona and no admin flag", %{record: record, user: user} do
      assert {:error, :unauthorized} =
               Participation.submit_session_note(%Scope{user: user}, %{
                 participation_record_id: record.id,
                 content: "Not mine to write"
               })
    end

    test "refuses an admin scope", %{record: record, admin_scope: scope} do
      # An admin holds no provider identity, and a Session Note is the Instructor's.
      assert {:error, :unauthorized} =
               Participation.submit_session_note(scope, %{
                 participation_record_id: record.id,
                 content: "Not mine to write"
               })
    end

    test "a staff member assigned to the session succeeds, authored as the employing provider",
         %{record: record, provider: provider, staff_scope: scope} do
      assert {:ok, note} =
               Participation.submit_session_note(scope, %{
                 participation_record_id: record.id,
                 content: "Engaged all session"
               })

      assert note.provider_id == provider.id
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

  describe "session-note PubSub topics" do
    # Proves publisher and subscriber meet: notify each session-note event through
    # the real notifier while subscribed to the exact topic the provider and staff
    # LiveViews subscribe to. Both sides call `Participation.provider_topic/1`, so a
    # change to it moves them together; a change to only one fails here instead of
    # silently in production.
    #
    # Notes used to fan out on three registry-derived `session_note:<event>` topics,
    # which carried every provider's notes to every subscribed view. They now route
    # by the `provider_id` already in the payload.

    setup do
      note = build(:session_note)
      Phoenix.PubSub.subscribe(KlassHero.PubSub, Participation.provider_topic(note.provider_id))
      %{note: note}
    end

    @note_events [:session_note_submitted, :session_note_approved, :session_note_rejected]

    for event_type <- @note_events do
      test "#{event_type} reaches the provider topic the LiveViews subscribe to", %{note: note} do
        ParticipationEvents
        |> apply(unquote(event_type), [note])
        |> Notifications.notify()

        assert_receive :session_notes_changed
      end
    end

    test "a note never reaches another provider's topic", %{note: note} do
      other_provider_id = Ecto.UUID.generate()
      Phoenix.PubSub.subscribe(KlassHero.PubSub, Participation.provider_topic(other_provider_id))

      note
      |> ParticipationEvents.session_note_submitted()
      |> Notifications.notify()

      # One message, for this note's own provider — not two.
      assert_receive :session_notes_changed
      refute_receive :session_notes_changed, 50
    end
  end

  # The roster is seeded by `seed_session_roster/2`, not by inserting a record
  # directly: an inserted record lets the test choose `parent_id`, which is the
  # one field the runtime seeding path never writes. Building the fixture the way
  # production builds it is the whole point of this test.
  describe "a submitted note reaches the child's parent" do
    test "appears in the parent's pending queue" do
      provider = insert(:provider_profile_schema)
      program = insert(:program_schema, provider_id: provider.id)
      enrollment = insert(:enrollment_schema, program_id: program.id, status: "confirmed")
      session = insert(:program_session_schema, program_id: program.id, status: :in_progress)

      :ok = Participation.seed_session_roster(session.id, program.id)

      {:ok, %{roster: [%{record: record}]}} = Participation.get_session_with_roster(session.id)

      admin_scope = AccountsFixtures.admin_scope_fixture()
      {:ok, _} = Participation.record_check_in(admin_scope, record.id)

      provider_scope = %Scope{user: AccountsFixtures.unconfirmed_user_fixture(), provider: provider}

      {:ok, _note} =
        Participation.submit_session_note(provider_scope, %{
          participation_record_id: record.id,
          content: "Very engaged today"
        })

      assert {:ok, [pending]} = Participation.list_pending_session_notes(enrollment.parent_id)
      assert pending.content == "Very engaged today"
    end
  end
end
