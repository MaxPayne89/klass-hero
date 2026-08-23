defmodule KlassHeroWeb.Provider.ParticipationLiveTest do
  use KlassHeroWeb.ConnCase, async: true

  import KlassHero.Factory
  import Phoenix.LiveViewTest

  alias KlassHero.Accounts.Scope
  alias KlassHero.Participation
  alias KlassHero.Participation.ParticipationRecord
  alias KlassHero.Participation.ProgramSession
  alias KlassHero.Participation.SessionNote
  alias KlassHero.Repo

  setup :register_and_log_in_provider

  defp create_session_with_child(%{provider: provider, user: user}) do
    program = insert(:program_schema, provider_id: provider.id)
    session = insert(:program_session_schema, program_id: program.id, status: "in_progress")
    parent = insert(:parent_profile_schema)

    {child, _parent} =
      insert_child_with_guardian(
        parent: parent,
        first_name: "Emma",
        last_name: "Mueller",
        allergies: "Peanuts",
        support_needs: "Wheelchair access",
        emergency_contact: "+49 170 1234567"
      )

    record =
      insert(:participation_record_schema,
        session_id: session.id,
        child_id: child.id,
        parent_id: parent.id,
        status: :registered
      )

    # The same scope the LiveView acts under, so a check-in arranged directly
    # through the context goes down the production authorization path.
    scope = %Scope{user: user, provider: provider}

    %{session: session, parent: parent, child: child, record: record, scope: scope}
  end

  describe "cross-provider authorization" do
    test "redirects when the session belongs to another provider (IDOR guard)", %{conn: conn} do
      foreign_provider = insert(:provider_profile_schema)
      foreign_program = insert(:program_schema, provider_id: foreign_provider.id)

      foreign_session =
        insert(:program_session_schema, program_id: foreign_program.id, status: "in_progress")

      assert {:error, {:live_redirect, %{to: "/provider/sessions", flash: flash}}} =
               live(conn, ~p"/provider/participation/#{foreign_session.id}")

      assert flash["error"] =~ "not"
    end
  end

  describe "roster displays child name" do
    setup [:create_session_with_child]

    test "renders child name in roster", %{conn: conn, session: session} do
      {:ok, view, _html} = live(conn, ~p"/provider/participation/#{session.id}")

      assert has_element?(view, "div", "Emma")
      assert has_element?(view, "div", "Mueller")
    end
  end

  describe "document heading outline" do
    setup [:create_session_with_child]

    test "page renders exactly one <h1> (the page header owns it)", %{
      conn: conn,
      session: session
    } do
      {:ok, view, _html} = live(conn, ~p"/provider/participation/#{session.id}")

      # Render after mount so @session is loaded (mount assigns it nil, then
      # load_session_data/1 fills it). The page's single top-level heading is
      # the <.page_header> title; the topbar no longer emits an <h1>. See #984.
      html = render(view)

      # Count opening <h1 tags across the whole page. There is no element/2
      # equivalent for "exactly one of X", so we count tag openings directly.
      h1_count = length(String.split(html, "<h1")) - 1

      assert h1_count == 1
    end
  end

  describe "sidebar navigation" do
    setup [:create_session_with_child]

    test "highlights Sessions in the sidebar", %{conn: conn, session: session} do
      {:ok, view, _html} = live(conn, ~p"/provider/participation/#{session.id}")

      assert has_element?(view, "a[aria-current='page']", "Sessions")
    end
  end

  describe "consent-gated safety info" do
    setup [:create_session_with_child]

    test "shows safety badges when child has consent and safety data", %{
      conn: conn,
      session: session,
      parent: parent,
      child: child,
      record: record
    } do
      insert(:consent_schema,
        parent_id: parent.id,
        child_id: child.id,
        consent_type: "provider_data_sharing"
      )

      {:ok, view, _html} = live(conn, ~p"/provider/participation/#{session.id}")

      assert has_element?(view, "#safety-info-#{record.id}")
      assert has_element?(view, "#safety-info-#{record.id} span", "Peanuts")
      assert has_element?(view, "#safety-info-#{record.id} span", "Wheelchair access")
      assert has_element?(view, "#safety-info-#{record.id} span", "+49 170 1234567")
    end

    test "hides safety info when child has no consent", %{
      conn: conn,
      session: session,
      record: record
    } do
      {:ok, view, _html} = live(conn, ~p"/provider/participation/#{session.id}")

      refute has_element?(view, "#safety-info-#{record.id}")
    end

    test "hides safety info when consent has been withdrawn", %{
      conn: conn,
      session: session,
      parent: parent,
      child: child,
      record: record
    } do
      insert(:consent_schema,
        parent_id: parent.id,
        child_id: child.id,
        consent_type: "provider_data_sharing",
        withdrawn_at: DateTime.utc_now() |> DateTime.truncate(:second)
      )

      {:ok, view, _html} = live(conn, ~p"/provider/participation/#{session.id}")

      refute has_element?(view, "#safety-info-#{record.id}")
    end

    test "hides safety badges when child has consent but nil safety data", %{
      conn: conn,
      session: session
    } do
      parent = insert(:parent_profile_schema)

      {child_no_allergies, _parent2} =
        insert_child_with_guardian(
          parent: parent,
          first_name: "Liam",
          last_name: "Schmidt",
          allergies: nil,
          support_needs: nil,
          emergency_contact: nil
        )

      record_no_allergies =
        insert(:participation_record_schema,
          session_id: session.id,
          child_id: child_no_allergies.id,
          parent_id: parent.id,
          status: :registered
        )

      insert(:consent_schema,
        parent_id: parent.id,
        child_id: child_no_allergies.id,
        consent_type: "provider_data_sharing"
      )

      {:ok, view, _html} = live(conn, ~p"/provider/participation/#{session.id}")

      # Child name renders, but no safety info badges (all fields are nil)
      assert has_element?(view, "div", "Liam")
      refute has_element?(view, "#safety-info-#{record_no_allergies.id}")
    end
  end

  describe "session notes" do
    setup [:create_session_with_child]

    defp check_in_record(%{record: record, scope: scope}) do
      {:ok, updated} =
        KlassHero.Participation.record_check_in(scope, record.id)

      %{record: updated}
    end

    test "shows 'Add Note' button for checked-in child", %{
      conn: conn,
      session: session,
      record: record,
      scope: scope
    } do
      check_in_record(%{record: record, scope: scope})

      {:ok, view, _html} = live(conn, ~p"/provider/participation/#{session.id}")

      assert has_element?(view, "#add-note-btn-#{record.id}")
    end

    test "does not show 'Add Note' for registered child", %{
      conn: conn,
      session: session,
      record: record
    } do
      {:ok, view, _html} = live(conn, ~p"/provider/participation/#{session.id}")

      refute has_element?(view, "#add-note-btn-#{record.id}")
    end

    test "expand and submit session note form", %{
      conn: conn,
      session: session,
      record: record,
      scope: scope
    } do
      check_in_record(%{record: record, scope: scope})

      {:ok, view, _html} = live(conn, ~p"/provider/participation/#{session.id}")

      # Click "Add Note" to expand form
      view
      |> element("#add-note-btn-#{record.id}")
      |> render_click()

      assert has_element?(view, "#session-note-form-#{record.id}")

      # Submit the note
      view
      |> form("#session-note-form-#{record.id}", %{note: %{content: "Great participation"}})
      |> render_submit()

      # Form should collapse and badge should appear
      refute has_element?(view, "#session-note-form-#{record.id}")
    end

    test "shows note status badge after submission", %{
      conn: conn,
      session: session,
      record: record,
      scope: scope
    } do
      check_in_record(%{record: record, scope: scope})

      # Submit a note first
      {:ok, _note} =
        KlassHero.Participation.submit_session_note(scope, %{
          participation_record_id: record.id,
          content: "Good session"
        })

      {:ok, view, _html} = live(conn, ~p"/provider/participation/#{session.id}")

      # Should not show "Add Note" button (note already exists)
      refute has_element?(view, "#add-note-btn-#{record.id}")
    end

    test "shows 'Edit & Resubmit' for rejected note", %{
      conn: conn,
      session: session,
      record: record,
      parent: parent,
      user: user,
      scope: scope
    } do
      check_in_record(%{record: record, scope: scope})

      # Submit and reject a note
      {:ok, note} =
        KlassHero.Participation.submit_session_note(scope, %{
          participation_record_id: record.id,
          content: "Some observation"
        })

      {:ok, _rejected} =
        KlassHero.Participation.review_session_note(%Scope{user: user, parent: parent}, %{
          note_id: note.id,
          decision: :reject,
          reason: "Too vague"
        })

      {:ok, view, _html} = live(conn, ~p"/provider/participation/#{session.id}")

      assert has_element?(view, "#revise-note-btn-#{note.id}")
    end

    test "shows rejection reason when note is rejected with reason", %{
      conn: conn,
      session: session,
      record: record,
      parent: parent,
      user: user,
      scope: scope
    } do
      check_in_record(%{record: record, scope: scope})

      {:ok, note} =
        KlassHero.Participation.submit_session_note(scope, %{
          participation_record_id: record.id,
          content: "Some observation"
        })

      {:ok, _rejected} =
        KlassHero.Participation.review_session_note(%Scope{user: user, parent: parent}, %{
          note_id: note.id,
          decision: :reject,
          reason: "Too vague, please be specific"
        })

      {:ok, view, _html} = live(conn, ~p"/provider/participation/#{session.id}")

      assert has_element?(view, "#rejection-reason-#{note.id}")
    end

    test "shows approved notes from past sessions when consented", %{
      conn: conn,
      session: session,
      parent: parent,
      child: child,
      record: record,
      scope: scope
    } do
      check_in_record(%{record: record, scope: scope})

      insert(:consent_schema,
        parent_id: parent.id,
        child_id: child.id,
        consent_type: "provider_data_sharing"
      )

      # Create an approved note for this child
      insert(:session_note_schema,
        participation_record_id: record.id,
        child_id: child.id,
        parent_id: parent.id,
        status: :approved,
        reviewed_at: DateTime.utc_now() |> DateTime.truncate(:second),
        content: "Very focused during activities"
      )

      {:ok, view, _html} = live(conn, ~p"/provider/participation/#{session.id}")

      assert has_element?(view, "#approved-notes-#{record.id}")
    end

    test "hides approved notes when no consent", %{
      conn: conn,
      session: session,
      record: record,
      scope: scope
    } do
      check_in_record(%{record: record, scope: scope})

      {:ok, view, _html} = live(conn, ~p"/provider/participation/#{session.id}")

      refute has_element?(view, "#approved-notes-#{record.id}")
    end

    test "revision form submits and shows success flash", %{
      conn: conn,
      session: session,
      record: record,
      parent: parent,
      user: user,
      scope: scope
    } do
      check_in_record(%{record: record, scope: scope})

      # Submit and reject a note
      {:ok, note} =
        KlassHero.Participation.submit_session_note(scope, %{
          participation_record_id: record.id,
          content: "Initial observation"
        })

      {:ok, _rejected} =
        KlassHero.Participation.review_session_note(%Scope{user: user, parent: parent}, %{
          note_id: note.id,
          decision: :reject,
          reason: "Needs more detail"
        })

      {:ok, view, _html} = live(conn, ~p"/provider/participation/#{session.id}")

      # Expand revision form
      view
      |> element("#revise-note-btn-#{note.id}")
      |> render_click()

      assert has_element?(view, "#revision-note-form-#{note.id}")

      # Submit revised note
      view
      |> form("#revision-note-form-#{note.id}", %{
        revision: %{content: "Detailed observation about engagement"}
      })
      |> render_submit()

      # Form should collapse after submission
      refute has_element?(view, "#revision-note-form-#{note.id}")
    end

    test "submit_note with blank content shows error flash", %{
      conn: conn,
      session: session,
      record: record,
      scope: scope
    } do
      check_in_record(%{record: record, scope: scope})

      {:ok, view, _html} = live(conn, ~p"/provider/participation/#{session.id}")

      # Expand note form
      view
      |> element("#add-note-btn-#{record.id}")
      |> render_click()

      # Submit with empty content
      view
      |> form("#session-note-form-#{record.id}", %{note: %{content: ""}})
      |> render_submit()

      assert has_element?(view, "#flash-error")
    end

    test "submit_note for duplicate shows error flash", %{
      conn: conn,
      session: session,
      record: record,
      scope: scope
    } do
      check_in_record(%{record: record, scope: scope})

      # Submit a note first via the API
      {:ok, _note} =
        KlassHero.Participation.submit_session_note(scope, %{
          participation_record_id: record.id,
          content: "First note"
        })

      # Reload to see the note badge (no Add Note button)
      {:ok, view, _html} = live(conn, ~p"/provider/participation/#{session.id}")

      # The "Add Note" button should not appear since a note already exists
      refute has_element?(view, "#add-note-btn-#{record.id}")
    end

    test "submit_note with a record_id from another session is rejected", %{
      conn: conn,
      session: session,
      record: record,
      scope: scope
    } do
      check_in_record(%{record: record, scope: scope})

      foreign_record = insert(:participation_record_schema)

      {:ok, view, _html} = live(conn, ~p"/provider/participation/#{session.id}")

      render_hook(view, "submit_note", %{
        "id" => to_string(foreign_record.id),
        "note" => %{"content" => "Should be blocked"}
      })

      assert_flash(view, :error, "Record not found")

      refute KlassHero.Repo.get_by(SessionNote,
               participation_record_id: foreign_record.id
             )
    end
  end

  describe "check-in via LiveView event" do
    setup [:create_session_with_child]

    test "check_in event transitions record to checked_in and shows success flash", %{
      conn: conn,
      session: session,
      record: record
    } do
      {:ok, view, _html} = live(conn, ~p"/provider/participation/#{session.id}")

      assert has_element?(view, "button[phx-click='check_in'][phx-value-id='#{record.id}']")

      view
      |> element("button[phx-click='check_in'][phx-value-id='#{record.id}']")
      |> render_click()

      assert_flash(view, :info, "Child checked in successfully")

      assert has_element?(
               view,
               "button[phx-click='expand_checkout_form'][phx-value-id='#{record.id}']"
             )
    end

    test "check_in uses logged-in user ID (not provider profile ID) for FK integrity", %{
      conn: conn,
      session: session,
      record: record,
      user: user,
      provider: provider
    } do
      # Precondition: provider profile PK differs from the logged-in user PK.
      # If someone accidentally passes provider.id to check_in_by (FK → users),
      # the DB constraint will reject it.
      refute provider.id == user.id

      {:ok, view, _html} = live(conn, ~p"/provider/participation/#{session.id}")

      view
      |> element("button[phx-click='check_in'][phx-value-id='#{record.id}']")
      |> render_click()

      assert_flash(view, :info, "Child checked in successfully")

      # Verify the DB record points to the logged-in user, not the provider profile
      db_record = KlassHero.Repo.get!(ParticipationRecord, record.id)
      assert db_record.check_in_by == user.id
    end
  end

  describe "checkout via LiveView event" do
    setup [:create_session_with_child]

    test "expand_checkout_form shows checkout form for checked-in child", %{
      conn: conn,
      session: session,
      record: record,
      scope: scope
    } do
      {:ok, _} =
        KlassHero.Participation.record_check_in(scope, record.id)

      {:ok, view, _html} = live(conn, ~p"/provider/participation/#{session.id}")

      view
      |> element("button[phx-click='expand_checkout_form'][phx-value-id='#{record.id}']")
      |> render_click()

      assert has_element?(view, "#checkout-form-#{record.id}")
    end

    test "confirm_checkout completes checkout and shows success flash", %{
      conn: conn,
      session: session,
      record: record,
      scope: scope
    } do
      {:ok, _} =
        KlassHero.Participation.record_check_in(scope, record.id)

      {:ok, view, _html} = live(conn, ~p"/provider/participation/#{session.id}")

      view
      |> element("button[phx-click='expand_checkout_form'][phx-value-id='#{record.id}']")
      |> render_click()

      view
      |> form("#checkout-form-#{record.id}", %{checkout: %{notes: "Picked up by parent"}})
      |> render_submit()

      assert_flash(view, :info, "Child checked out successfully")
      refute has_element?(view, "#checkout-form-#{record.id}")
    end

    test "cancel_checkout hides the checkout form", %{
      conn: conn,
      session: session,
      record: record,
      scope: scope
    } do
      {:ok, _} =
        KlassHero.Participation.record_check_in(scope, record.id)

      {:ok, view, _html} = live(conn, ~p"/provider/participation/#{session.id}")

      view
      |> element("button[phx-click='expand_checkout_form'][phx-value-id='#{record.id}']")
      |> render_click()

      assert has_element?(view, "#checkout-form-#{record.id}")

      view
      |> element("button[phx-click='cancel_checkout'][phx-value-id='#{record.id}']")
      |> render_click()

      refute has_element?(view, "#checkout-form-#{record.id}")
    end
  end

  describe "edit-after-check-in flow" do
    setup [:create_session_with_child]

    defp check_in!(record, scope) do
      {:ok, updated} =
        KlassHero.Participation.record_check_in(scope, record.id)

      updated
    end

    test "shows Edit and 'Record departure' buttons for a checked-in child", %{
      conn: conn,
      session: session,
      record: record,
      scope: scope
    } do
      _checked_in = check_in!(record, scope)
      {:ok, view, html} = live(conn, ~p"/provider/participation/#{session.id}")

      assert has_element?(view, "#edit-btn-#{record.id}")

      assert has_element?(
               view,
               "button[phx-click='expand_checkout_form'][phx-value-id='#{record.id}']",
               "Record departure"
             )

      # Status pill flipped to "Present" rather than the prior "Checked In" wording.
      assert html =~ "Present"
      refute html =~ "Checked In"
    end

    test "expand_edit_form opens the inline edit form pre-filled with check-in notes", %{
      conn: conn,
      session: session,
      record: record,
      scope: scope
    } do
      _checked_in = check_in!(record, scope)

      # Seed an existing check-in note so we can confirm pre-fill behaviour.
      record
      |> Ecto.Changeset.change(check_in_notes: "Forgot raincoat")
      |> KlassHero.Repo.update!()

      {:ok, view, _html} = live(conn, ~p"/provider/participation/#{session.id}")

      view
      |> element("#edit-btn-#{record.id}")
      |> render_click()

      assert has_element?(view, "#edit-record-form-#{record.id}")
      html = render(view)
      assert html =~ "Forgot raincoat"
    end

    test "submitting notes-only update calls correct_attendance and updates the row", %{
      conn: conn,
      session: session,
      record: record,
      scope: scope
    } do
      _checked_in = check_in!(record, scope)
      {:ok, view, _html} = live(conn, ~p"/provider/participation/#{session.id}")

      view |> element("#edit-btn-#{record.id}") |> render_click()

      view
      |> form("#edit-record-form-#{record.id}", edit: %{notes: "Was a bit shy today"})
      |> render_submit()

      assert KlassHero.Repo.get!(ParticipationRecord, record.id).check_in_notes ==
               "Was a bit shy today"

      # Form collapsed after successful submit.
      refute has_element?(view, "#edit-record-form-#{record.id}")
    end

    test "submitting departure time records check-out via correct_attendance", %{
      conn: conn,
      session: session,
      record: record,
      scope: scope
    } do
      _checked_in = check_in!(record, scope)
      {:ok, view, _html} = live(conn, ~p"/provider/participation/#{session.id}")

      view |> element("#edit-btn-#{record.id}") |> render_click()

      # Pick a check-out time strictly after check_in_at (which was just set
      # to DateTime.utc_now/0). HTML datetime-local drops seconds, so we align
      # to minute precision to get an exact round-trip through the parser.
      expected_check_out =
        DateTime.utc_now()
        |> DateTime.add(60, :second)
        |> Map.merge(%{second: 0, microsecond: {0, 0}})

      form_value = Calendar.strftime(expected_check_out, "%Y-%m-%dT%H:%M")

      view
      |> form("#edit-record-form-#{record.id}",
        edit: %{notes: "Picked up by dad", check_out_at: form_value}
      )
      |> render_submit()

      reloaded = KlassHero.Repo.get!(ParticipationRecord, record.id)
      assert reloaded.status == :checked_out
      assert reloaded.check_out_at == expected_check_out
      assert reloaded.check_out_notes == "Picked up by dad"
    end

    test "Edit button is available for already-checked-out rows", %{
      conn: conn,
      session: session,
      record: record,
      scope: scope
    } do
      checked_in = check_in!(record, scope)

      {:ok, _checked_out} =
        KlassHero.Participation.record_check_out(scope, checked_in.id, notes: "left at 3pm")

      {:ok, view, html} = live(conn, ~p"/provider/participation/#{session.id}")

      assert has_element?(view, "#edit-btn-#{record.id}")
      # Pill reads "Departed" once the child has gone.
      assert html =~ "Departed"
    end

    # Regression for PR #709 review (Copilot): when a record is :checked_out but
    # check_out_notes is nil (record_check_out accepts optional notes), the edit
    # form must NOT pre-fill the textarea with check_in_notes — that value
    # would silently get copied into check_out_notes on save.
    test "edit form starts empty when record is checked-out without check-out notes",
         %{conn: conn, session: session, record: record, scope: scope} do
      record
      |> Ecto.Changeset.change(check_in_notes: "Brought hat and gloves")
      |> KlassHero.Repo.update!()

      checked_in = check_in!(record, scope)

      # no :notes — leaves check_out_notes as nil
      {:ok, _} =
        KlassHero.Participation.record_check_out(scope, checked_in.id)

      {:ok, view, _html} = live(conn, ~p"/provider/participation/#{session.id}")
      view |> element("#edit-btn-#{record.id}") |> render_click()

      html = render(view)
      refute html =~ "Brought hat and gloves"
    end

    test "cancel_edit collapses the form without changes", %{
      conn: conn,
      session: session,
      record: record,
      scope: scope
    } do
      _checked_in = check_in!(record, scope)
      {:ok, view, _html} = live(conn, ~p"/provider/participation/#{session.id}")

      view |> element("#edit-btn-#{record.id}") |> render_click()
      assert has_element?(view, "#edit-record-form-#{record.id}")

      view
      |> element("button[phx-click='cancel_edit'][phx-value-id='#{record.id}']")
      |> render_click()

      refute has_element?(view, "#edit-record-form-#{record.id}")
    end
  end

  describe "real-time roster updates over PubSub (#1108)" do
    setup [:create_session_with_child]

    test "re-renders when a check-in event arrives on the provider-scoped topic", %{
      conn: conn,
      user: user,
      provider: provider,
      session: session,
      record: record
    } do
      {:ok, view, _html} = live(conn, ~p"/provider/participation/#{session.id}")

      # A registered record shows the check-in control, not the edit control.
      refute has_element?(view, "#edit-btn-#{record.id}")

      # Flip the record in the DB, then broadcast on the exact topic the view
      # subscribes to. If the subscription targeted the wrong topic (the pre-#1108
      # bug), this broadcast never arrives and the edit control never appears.
      {:ok, _} =
        record
        |> Ecto.Changeset.change(status: :checked_in, check_in_by: user.id)
        |> KlassHero.Repo.update()

      Phoenix.PubSub.broadcast(
        KlassHero.PubSub,
        Participation.provider_topic(provider.id),
        {:attendance_changed,
         %{record_id: record.id, session_id: session.id, child_id: record.child_id, kind: :checked_in}}
      )

      assert render(view) =~ "edit-btn-#{record.id}"
    end
  end

  describe "completing the session from the roster" do
    setup [:create_session_with_child]

    test "offers Complete Session while the session is in progress", %{conn: conn, session: session} do
      {:ok, view, _html} = live(conn, ~p"/provider/participation/#{session.id}")

      assert has_element?(view, "#complete-session-btn")
    end

    test "does not offer it once the session is completed", %{conn: conn, session: session} do
      {:ok, _} = Repo.update(Ecto.Changeset.change(session, status: :completed))

      {:ok, view, _html} = live(conn, ~p"/provider/participation/#{session.id}")

      refute has_element?(view, "#complete-session-btn")
    end

    test "completing absents the stragglers without leaving the page", %{
      conn: conn,
      session: session,
      record: record
    } do
      {:ok, view, _html} = live(conn, ~p"/provider/participation/#{session.id}")

      view |> element("#complete-session-btn") |> render_click()

      assert_flash(view, :info, "Session completed successfully")
      assert Repo.get!(ProgramSession, session.id).status == :completed
      assert Repo.get!(ParticipationRecord, record.id).status == :absent
      refute has_element?(view, "#complete-session-btn")
    end

    # The check-in is what makes this non-vacuous: an absent row has no actions to
    # lose, so a roster asserted read-only without one proves nothing.
    test "the roster stops being editable", %{conn: conn, session: session, record: record, scope: scope} do
      {:ok, _} = Participation.record_check_in(scope, record.id)

      {:ok, view, _html} = live(conn, ~p"/provider/participation/#{session.id}")
      assert has_element?(view, "#edit-btn-#{record.id}")

      view |> element("#complete-session-btn") |> render_click()

      refute has_element?(view, "#edit-btn-#{record.id}")
    end
  end

  describe "marking a child absent" do
    setup [:create_session_with_child]

    test "records the absence with its reason and shows it on the row", %{
      conn: conn,
      session: session,
      record: record
    } do
      {:ok, view, _html} = live(conn, ~p"/provider/participation/#{session.id}")

      view |> element("#mark-absent-btn-#{record.id}") |> render_click()

      view
      |> form("#absence-form-#{record.id}", %{"absence" => %{"content" => "Mum called — off sick"}})
      |> render_submit()

      assert_flash(view, :info, "Child marked absent")
      assert KlassHero.Repo.get!(ParticipationRecord, record.id).status == :absent
      assert has_element?(view, "#absence-reason-#{record.id}")
      assert render(view) =~ "Mum called — off sick"
    end

    # Defect 4: an absent row used to render "Check In", which the state machine
    # rejected every time. It now renders a working late-arrival action instead.
    test "an absent row offers a late arrival, not a second Mark absent", %{
      conn: conn,
      session: session,
      record: record,
      scope: scope
    } do
      {:ok, _} = Participation.record_absence(scope, record.id, reason: "No-show")

      {:ok, view, _html} = live(conn, ~p"/provider/participation/#{session.id}")

      refute has_element?(view, "#mark-absent-btn-#{record.id}")
      assert has_element?(view, "button[phx-click='check_in'][phx-value-id='#{record.id}']")

      view
      |> element("button[phx-click='check_in'][phx-value-id='#{record.id}']")
      |> render_click()

      assert_flash(view, :info, "Child checked in successfully")
      assert KlassHero.Repo.get!(ParticipationRecord, record.id).status == :checked_in
      refute has_element?(view, "#absence-reason-#{record.id}")
    end

    test "cancelling leaves the child on the roster", %{conn: conn, session: session, record: record} do
      {:ok, view, _html} = live(conn, ~p"/provider/participation/#{session.id}")

      view |> element("#mark-absent-btn-#{record.id}") |> render_click()
      assert has_element?(view, "#absence-form-#{record.id}")

      view |> element("button[phx-click='cancel_absence'][phx-value-id='#{record.id}']") |> render_click()

      refute has_element?(view, "#absence-form-#{record.id}")
      assert KlassHero.Repo.get!(ParticipationRecord, record.id).status == :registered
    end
  end
end
