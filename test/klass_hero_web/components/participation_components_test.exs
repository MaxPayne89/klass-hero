defmodule KlassHeroWeb.ParticipationComponentsTest do
  use KlassHeroWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias KlassHero.Provider.SessionDetail
  alias KlassHeroWeb.ParticipationComponents

  describe "participation_status/1" do
    test "renders :cancelled with red badge and x-circle icon" do
      html =
        render_component(&ParticipationComponents.participation_status/1,
          status: :cancelled,
          size: :sm
        )

      assert html =~ "bg-red-100"
      assert html =~ "hero-x-circle"
      assert html =~ "Cancelled"
    end
  end

  describe "participation_card/1 — Session Capacity" do
    setup do
      %{
        session:
          KlassHero.Factory.build(:program_session,
            status: :scheduled,
            max_capacity: nil
          )
      }
    end

    test "shows the roster against the Session Capacity when one is set", %{session: session} do
      html =
        render_component(&ParticipationComponents.participation_card/1,
          session: %{session | max_capacity: 5},
          role: :provider,
          attendance: %{roster: 4, checked_in: 0}
        )

      assert html =~ "4 of 5"
    end

    test "renders the plain count when the session is uncapped", %{session: session} do
      html =
        render_component(&ParticipationComponents.participation_card/1,
          session: session,
          role: :provider,
          attendance: %{roster: 4, checked_in: 0}
        )

      assert html =~ "4 children enrolled"
      refute html =~ "data-occupancy"
    end

    test "marks a session whose roster exceeds its Session Capacity", %{session: session} do
      html =
        render_component(&ParticipationComponents.participation_card/1,
          session: %{session | max_capacity: 5},
          role: :provider,
          attendance: %{roster: 6, checked_in: 0}
        )

      assert html =~ ~s(data-occupancy="over")
      assert html =~ "Over capacity"
    end

    test "does not mark a cancelled session, whose roster no longer means anything", %{
      session: session
    } do
      html =
        render_component(&ParticipationComponents.participation_card/1,
          session: %{session | max_capacity: 5, status: :cancelled},
          role: :provider,
          attendance: %{roster: 6, checked_in: 0}
        )

      refute html =~ "Over capacity"
    end

    test "still marks a completed session, whose overflow is real history", %{session: session} do
      html =
        render_component(&ParticipationComponents.participation_card/1,
          session: %{session | max_capacity: 5, status: :completed},
          role: :provider,
          attendance: %{roster: 6, checked_in: 6}
        )

      assert html =~ "Over capacity"
    end

    test "does not mark a session sitting exactly at its Session Capacity", %{session: session} do
      html =
        render_component(&ParticipationComponents.participation_card/1,
          session: %{session | max_capacity: 5},
          role: :provider,
          attendance: %{roster: 5, checked_in: 0}
        )

      refute html =~ "Over capacity"
    end
  end

  describe "session_table/1" do
    # Every status navigates, cancelled included: a cancelled session still has a
    # roster worth reading, and hiding the way in was the whole complaint in #1074.
    for {persona, base} <- [provider: "/provider/participation", staff: "/staff/participation"],
        status <- [:scheduled, :in_progress, :completed, :cancelled] do
      test "a #{status} row links every cell to the #{persona} session page" do
        html =
          render_component(&ParticipationComponents.session_table/1,
            sessions: [session_detail(session_id: "s-42", status: unquote(status))],
            persona: unquote(persona)
          )

        hrefs =
          html
          |> LazyHTML.from_fragment()
          |> LazyHTML.query("tbody a")
          |> LazyHTML.attribute("href")

        # One per cell, not one per row: an <a> wrapping <td>s is invalid HTML.
        assert hrefs == List.duplicate("#{unquote(base)}/s-42", 4)
      end
    end

    test "shows the empty state when there are no sessions" do
      html =
        render_component(&ParticipationComponents.session_table/1,
          sessions: [],
          persona: :provider
        )

      assert html =~ "No sessions scheduled yet"
    end

    test "a caller may replace the empty-state sentence" do
      html =
        render_component(&ParticipationComponents.session_table/1,
          sessions: [],
          persona: :staff,
          empty_message: "No sessions assigned to you yet."
        )

      assert html =~ "No sessions assigned to you yet."
      refute html =~ "No sessions scheduled yet"
    end

    test "renders the sessions it is given, in the order given" do
      html =
        render_component(&ParticipationComponents.session_table/1,
          sessions: [
            session_detail(session_id: "s-1", current_assigned_staff_name: "Alice"),
            session_detail(
              session_id: "s-2",
              session_date: ~D[2026-05-08],
              status: :cancelled,
              current_assigned_staff_name: nil
            )
          ],
          persona: :provider
        )

      assert html =~ "Alice"
      assert html =~ "Unassigned"
      # Cancelled row hides attendance (same-line match; a dotall regex spans rows
      # and fires even for a correct implementation).
      refute html =~ ~r/0\s*\/\s*0.*cancelled/i
    end

    defp session_detail(overrides) do
      struct!(
        %SessionDetail{
          session_id: "s-1",
          program_id: "prog-1",
          provider_id: "prv-1",
          session_date: ~D[2026-05-01],
          start_time: ~T[15:00:00],
          end_time: ~T[16:00:00],
          status: :scheduled,
          program_title: "Judo",
          current_assigned_staff_name: "Alice",
          checked_in_count: 0,
          total_count: 0
        },
        overrides
      )
    end
  end
end
