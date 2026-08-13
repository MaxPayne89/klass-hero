defmodule KlassHeroWeb.ProviderComponentsTest do
  use KlassHeroWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias KlassHero.Provider.SessionDetail

  describe "programs_table/1" do
    test "renders a Sessions button per row" do
      html = render_table(program_row(id: "prog-1"))

      assert html =~ "phx-click=\"view_sessions\""
      assert html =~ "phx-value-program-id=\"prog-1\""
      assert html =~ ~s|aria-label="View sessions"|
    end

    test "renders a Report Incident link per row that targets the new incident page" do
      html = render_table(program_row(id: "prog-123"))

      assert html =~ ~s|href="/provider/incidents/new?program_id=prog-123"|
      assert html =~ ~s|aria-label="Report Incident"|
    end

    test "renders an Incident Reports link per row that targets the per-program list" do
      html = render_table(program_row(id: "prog-456"))

      assert html =~ ~s|href="/provider/programs/prog-456/incidents"|
      assert html =~ ~s|aria-label="Incident Reports"|
    end
  end

  # The three states the staff column must keep apart (#1310). Before it, the
  # middle one rendered identically to the last, so a provider could not tell a
  # leaderless-but-staffed program from an empty one.
  describe "programs_table/1 assigned staff column" do
    test "a lead with others shows the lead and an overflow count" do
      staff = %{
        lead: %{id: "s-1", name: "Dirk Schreiber", initials: "DS", headshot_url: nil},
        count: 2,
        others_count: 1
      }

      html = render_table(program_row(id: "p1", assigned_staff: staff))

      assert html =~ ~s|id="program-staff-lead-p1"|
      assert html =~ "Dirk Schreiber"
      assert html =~ "+1"
      refute html =~ ~s|id="program-staff-leaderless-p1"|
      refute html =~ ~s|id="program-staff-empty-p1"|
    end

    test "a lone lead shows no overflow count" do
      staff = %{
        lead: %{id: "s-1", name: "Ada Lovelace", initials: "AL", headshot_url: nil},
        count: 1,
        others_count: 0
      }

      html = render_table(program_row(id: "p2", assigned_staff: staff))

      assert html =~ ~s|id="program-staff-lead-p2"|
      assert html =~ "Ada Lovelace"
      refute html =~ "+0"
    end

    test "a staffed but leaderless program shows its headcount, not Unassigned" do
      staff = %{lead: nil, count: 2, others_count: 2}

      html = render_table(program_row(id: "p3", assigned_staff: staff))

      assert html =~ ~s|id="program-staff-leaderless-p3"|
      assert html =~ "2 staff"
      refute html =~ ~s|id="program-staff-empty-p3"|
      refute html =~ "Unassigned"
    end

    test "a program nobody is on shows Unassigned" do
      html = render_table(program_row(id: "p4"))

      assert html =~ ~s|id="program-staff-empty-p4"|
      assert html =~ "Unassigned"
      refute html =~ ~s|id="program-staff-lead-p4"|
      refute html =~ ~s|id="program-staff-leaderless-p4"|
    end
  end

  defp program_row(overrides) do
    Enum.into(overrides, %{
      id: "prog-1",
      name: "Judo",
      category: "Sports",
      price: "120",
      assigned_staff: %{lead: nil, count: 0, others_count: 0},
      status: :active,
      enrolled: 5,
      capacity: 10
    })
  end

  defp render_table(program) do
    render_component(&KlassHeroWeb.ProviderComponents.programs_table/1,
      programs: [{"programs-#{program.id}", program}],
      staff_options: [%{value: "all", label: "All Staff"}]
    )
  end

  describe "sessions_modal/1" do
    test "renders the provided sessions in order" do
      modal = %{
        program_id: "prog-1",
        program_title: "Judo",
        sessions: [
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
          %SessionDetail{
            session_id: "s-2",
            program_id: "prog-1",
            provider_id: "prv-1",
            session_date: ~D[2026-05-08],
            start_time: ~T[15:00:00],
            end_time: ~T[16:00:00],
            status: :cancelled,
            program_title: "Judo",
            current_assigned_staff_name: nil,
            checked_in_count: 0,
            total_count: 0
          }
        ]
      }

      html = render_component(&KlassHeroWeb.ProviderComponents.sessions_modal/1, modal: modal)

      assert html =~ "Judo"
      assert html =~ "Alice"
      assert html =~ "Unassigned"
      # Cancelled row hides attendance (same-line match; dotall flag removed because the
      # plan's `/is` regex spans across rows and fires even for a correct implementation)
      refute html =~ ~r/0\s*\/\s*0.*cancelled/i
    end

    test "shows empty state when sessions is []" do
      modal = %{program_id: "p", program_title: "T", sessions: []}
      html = render_component(&KlassHeroWeb.ProviderComponents.sessions_modal/1, modal: modal)
      assert html =~ "No sessions scheduled yet"
    end
  end
end
