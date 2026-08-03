defmodule KlassHeroWeb.ProviderComponentsTest do
  use KlassHeroWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias KlassHero.Provider.SessionDetail

  describe "programs_table/1" do
    test "renders a Sessions button per row" do
      program = %{
        id: "prog-1",
        name: "Judo",
        category: "Sports",
        price: "120",
        assigned_staff: nil,
        status: :active,
        enrolled: 5,
        capacity: 10
      }

      html =
        render_component(&KlassHeroWeb.ProviderComponents.programs_table/1,
          programs: [{"programs-prog-1", program}],
          staff_options: [%{value: "all", label: "All Staff"}]
        )

      assert html =~ "phx-click=\"view_sessions\""
      assert html =~ "phx-value-program-id=\"prog-1\""
      assert html =~ ~s|aria-label="View sessions"|
    end

    test "renders a Report Incident link per row that targets the new incident page" do
      program = %{
        id: "prog-123",
        name: "Art Club",
        category: "Arts",
        price: "50",
        assigned_staff: nil,
        status: :active,
        enrolled: 5,
        capacity: 10
      }

      html =
        render_component(&KlassHeroWeb.ProviderComponents.programs_table/1,
          programs: [{"programs-prog-123", program}],
          staff_options: [%{value: "all", label: "All Staff"}]
        )

      assert html =~ ~s|href="/provider/incidents/new?program_id=prog-123"|
      assert html =~ ~s|aria-label="Report Incident"|
    end

    test "renders an Incident Reports link per row that targets the per-program list" do
      program = %{
        id: "prog-456",
        name: "Robotics",
        category: "STEM",
        price: "75",
        assigned_staff: nil,
        status: :active,
        enrolled: 3,
        capacity: 12
      }

      html =
        render_component(&KlassHeroWeb.ProviderComponents.programs_table/1,
          programs: [{"programs-prog-456", program}],
          staff_options: [%{value: "all", label: "All Staff"}]
        )

      assert html =~ ~s|href="/provider/programs/prog-456/incidents"|
      assert html =~ ~s|aria-label="Incident Reports"|
    end
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
