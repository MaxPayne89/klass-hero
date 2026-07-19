defmodule KlassHeroWeb.Parent.ParticipationHistoryLiveTest do
  @moduledoc """
  Tests for ParticipationHistoryLive session notes review functionality.
  """

  use KlassHeroWeb.ConnCase, async: true

  import KlassHero.EventTestHelper
  import KlassHero.Factory
  import Phoenix.LiveViewTest

  alias KlassHero.Participation.Domain.Events.ParticipationEvents
  alias KlassHero.Shared.Domain.Events.DomainEvent

  setup :register_and_log_in_parent

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

  describe "real-time attendance updates (#1108)" do
    setup %{parent: parent} do
      {child, _parent} =
        insert_child_with_guardian(parent: parent, first_name: "Emma", last_name: "Mueller")

      # No participation record at mount — the history stream starts empty, so an
      # event that streams a row is an unambiguous, observable delta.
      %{child: child}
    end

    test "streams the parent's own child when a check-in event arrives", %{conn: conn, child: child} do
      {:ok, view, _html} = live(conn, ~p"/parent/participation")
      record = insert(:participation_record_schema, child_id: child.id, status: :checked_in)

      emit_domain_event(view, ParticipationEvents.child_checked_in(record, []))

      assert has_element?(view, "#participation_records-#{record.id}")
    end

    test "handles child_marked_absent (guard atom fix)", %{conn: conn, child: child} do
      {:ok, view, _html} = live(conn, ~p"/parent/participation")
      record = insert(:participation_record_schema, child_id: child.id, status: :absent)

      emit_domain_event(view, ParticipationEvents.child_marked_absent(record, []))

      assert has_element?(view, "#participation_records-#{record.id}")
    end

    test "ignores an attendance event for another family's child (privacy)", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/parent/participation")
      foreign_record_id = Ecto.UUID.generate()

      foreign_event =
        DomainEvent.new(:child_checked_in, foreign_record_id, :participation, %{
          record_id: foreign_record_id,
          child_id: Ecto.UUID.generate()
        })

      emit_domain_event(view, foreign_event)

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
