defmodule KlassHeroWeb.Parent.ParticipationHistoryLiveTest do
  @moduledoc """
  Tests for ParticipationHistoryLive session notes review functionality.
  """

  use KlassHeroWeb.ConnCase, async: true

  import KlassHero.Factory
  import Phoenix.LiveViewTest

  alias KlassHero.Participation.Domain.Events.ParticipationEvents
  alias KlassHero.Participation.Notifications
  alias KlassHero.Shared.Domain.Events.IntegrationEvent

  setup :register_and_log_in_parent

  # The production path itself, not an imitation of it: the notifier derives the
  # child topic and the message shape, so a change to either fails here rather
  # than silently passing against a hand-written broadcast.
  defp broadcast_on_child_topic(event), do: Notifications.notify(event)

  defp create_child_with_note(%{parent: parent, user: user}) do
    {child, _parent} =
      insert_child_with_guardian(parent: parent, first_name: "Emma", last_name: "Mueller")

    session = insert(:program_session_schema, status: "in_progress")

    # Trigger: check_in_by references users table via FK constraint
    # Why: consolidated migrations enforce referential integrity
    # Outcome: use the logged-in user's ID instead of a random UUID
    record =
      insert(:participation_record_schema,
        session_id: session.id,
        child_id: child.id,
        parent_id: parent.id,
        status: :checked_in,
        check_in_at: DateTime.utc_now(),
        check_in_by: user.id
      )

    note =
      insert(:session_note_schema,
        participation_record_id: record.id,
        child_id: child.id,
        parent_id: parent.id,
        status: :pending_approval,
        content: "Very focused during activities"
      )

    %{child: child, session: session, record: record, note: note}
  end

  describe "pending notes section" do
    setup [:create_child_with_note]

    test "shows pending notes section when notes exist", %{conn: conn, note: note} do
      {:ok, view, _html} = live(conn, ~p"/parent/participation")

      assert has_element?(view, "#pending-notes-section")
      assert has_element?(view, "#pending-note-#{note.id}")
    end

    test "does not show pending notes section when no notes", %{
      conn: conn,
      note: note,
      parent: parent
    } do
      # Approve the note so nothing is pending
      KlassHero.Participation.review_session_note(%{
        note_id: note.id,
        parent_id: parent.id,
        decision: :approve
      })

      {:ok, view, _html} = live(conn, ~p"/parent/participation")

      refute has_element?(view, "#pending-notes-section")
    end

    test "approve note removes it from pending section", %{conn: conn, note: note} do
      {:ok, view, _html} = live(conn, ~p"/parent/participation")

      assert has_element?(view, "#pending-note-#{note.id}")

      view
      |> element("#approve-note-btn-#{note.id}")
      |> render_click()

      refute has_element?(view, "#pending-note-#{note.id}")
    end

    test "shows approve and reject buttons", %{conn: conn, note: note} do
      {:ok, view, _html} = live(conn, ~p"/parent/participation")

      assert has_element?(view, "#approve-note-btn-#{note.id}")
      assert has_element?(view, "#reject-note-btn-#{note.id}")
    end

    test "expand reject form shows reason textarea", %{conn: conn, note: note} do
      {:ok, view, _html} = live(conn, ~p"/parent/participation")

      view
      |> element("#reject-note-btn-#{note.id}")
      |> render_click()

      assert has_element?(view, "#reject-form-#{note.id}")
      assert has_element?(view, "#reject-note-form-#{note.id}")
    end

    test "reject note removes it from pending section", %{conn: conn, note: note} do
      {:ok, view, _html} = live(conn, ~p"/parent/participation")

      # Expand reject form
      view
      |> element("#reject-note-btn-#{note.id}")
      |> render_click()

      # Submit rejection
      view
      |> form("#reject-note-form-#{note.id}", %{reject: %{reason: "Not accurate"}})
      |> render_submit()

      refute has_element?(view, "#pending-note-#{note.id}")
    end
  end

  describe "real-time attendance updates (child-scoped topics, #1121)" do
    setup %{parent: parent} do
      {child, _parent} =
        insert_child_with_guardian(parent: parent, first_name: "Emma", last_name: "Mueller")

      # No participation record at mount — the history stream starts empty, so an
      # event that streams a row is an unambiguous, observable delta.
      %{child: child}
    end

    test "streams the parent's own child when a check-in is broadcast on its child topic", %{
      conn: conn,
      child: child
    } do
      {:ok, view, _html} = live(conn, ~p"/parent/participation")
      record = insert(:participation_record_schema, child_id: child.id, status: :checked_in)

      broadcast_on_child_topic(ParticipationEvents.child_checked_in(record, []))

      assert render(view) =~ record.id
      assert has_element?(view, "#participation_records-#{record.id}")
    end

    test "streams on child_marked_absent (guard atom fix)", %{conn: conn, child: child} do
      {:ok, view, _html} = live(conn, ~p"/parent/participation")
      record = insert(:participation_record_schema, child_id: child.id, status: :absent)

      broadcast_on_child_topic(ParticipationEvents.child_marked_absent(record, []))

      assert render(view) =~ record.id
      assert has_element?(view, "#participation_records-#{record.id}")
    end

    test "survives session-note review events fanned out on its child topic (#1121)", %{
      conn: conn,
      child: child
    } do
      {:ok, view, _html} = live(conn, ~p"/parent/participation")

      # publish_to_child_topic fans out ANY child_id-bearing event, including
      # session_note_approved/rejected. The LiveView must handle them, not crash —
      # review_session_note/1 dispatches these in the parent's own process.
      for event_type <- [:session_note_approved, :session_note_rejected] do
        event =
          IntegrationEvent.new(event_type, :participation, :session_note, Ecto.UUID.generate(), %{
            child_id: child.id,
            note_id: Ecto.UUID.generate()
          })

        broadcast_on_child_topic(event)
        assert render(view), "LiveView crashed on #{event_type}"
      end
    end

    test "never receives another family's child event — not subscribed to its topic (privacy)", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/parent/participation")
      foreign_record_id = Ecto.UUID.generate()

      foreign_event =
        IntegrationEvent.new(:child_checked_in, :participation, :participation_record, foreign_record_id, %{
          record_id: foreign_record_id,
          child_id: Ecto.UUID.generate()
        })

      broadcast_on_child_topic(foreign_event)

      refute has_element?(view, "#participation_records-#{foreign_record_id}")
    end
  end

  describe "auth" do
    test "redirects when not logged in", %{conn: _conn} do
      conn = build_conn()
      {:error, redirect} = live(conn, ~p"/parent/participation")
      assert {:redirect, %{to: path}} = redirect
      assert path =~ "/users/log-in"
    end
  end
end
