defmodule KlassHeroWeb.Admin.IncidentLiveTest do
  use KlassHeroWeb.ConnCase, async: true

  import KlassHero.Factory
  import KlassHero.ProviderFixtures
  import Phoenix.LiveViewTest

  # A provider distinct from the logged-in admin, plus a program it owns.
  # `provider_profile_fixture/1` creates the backing user, which doubles as the
  # incident's reporter.
  defp provider_with_program(business_name, program_title) do
    provider = provider_profile_fixture(business_name: business_name)
    program = insert(:program_schema, title: program_title, provider_id: provider.id)

    %{provider: provider, program: program}
  end

  describe "admin access control" do
    setup :register_and_log_in_admin

    test "admin can access /admin/incidents", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/admin/incidents")
      assert html =~ "Incident"
    end
  end

  describe "non-admin access control" do
    setup :register_and_log_in_user

    test "non-admin is redirected from /admin/incidents", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/", flash: flash}}} =
               live(conn, ~p"/admin/incidents")

      assert flash["error"] =~ "access"
    end

    test "non-admin is redirected from the incident show page", %{conn: conn} do
      %{provider: provider, program: program} = provider_with_program("Acme Clubs", "Robotics")

      report =
        incident_report_fixture(
          provider_profile_id: provider.id,
          reporter_user_id: provider.identity_id,
          program_id: program.id
        )

      assert {:error, {:redirect, %{to: "/", flash: flash}}} =
               live(conn, ~p"/admin/incidents/#{report.id}/show")

      assert flash["error"] =~ "access"
    end
  end

  describe "unauthenticated access control" do
    test "unauthenticated user is redirected from /admin/incidents", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/users/log-in"}}} =
               live(conn, ~p"/admin/incidents")
    end
  end

  describe "incident list" do
    setup :register_and_log_in_admin

    test "displays provider name, program title and severity", %{conn: conn} do
      %{provider: provider, program: program} = provider_with_program("Acme Clubs", "Robotics")

      incident_report_fixture(
        provider_profile_id: provider.id,
        reporter_user_id: provider.identity_id,
        program_id: program.id,
        reporter_display_name: "Maria Schmidt",
        category: :injury,
        severity: :critical
      )

      {:ok, view, _html} = live(conn, ~p"/admin/incidents")

      assert has_element?(view, "td", "Acme Clubs")
      assert has_element?(view, "td", "Robotics")
      assert has_element?(view, "td", "Maria Schmidt")
      assert has_element?(view, "span", "Critical")
      assert has_element?(view, "td", "Injury")
    end

    test "lists reports from every provider, not just one", %{conn: conn} do
      %{provider: first, program: first_program} = provider_with_program("Acme Clubs", "Robotics")
      %{provider: second, program: second_program} = provider_with_program("Zeta Camps", "Chess")

      incident_report_fixture(
        provider_profile_id: first.id,
        reporter_user_id: first.identity_id,
        program_id: first_program.id
      )

      incident_report_fixture(
        provider_profile_id: second.id,
        reporter_user_id: second.identity_id,
        program_id: second_program.id
      )

      {:ok, view, _html} = live(conn, ~p"/admin/incidents")

      assert has_element?(view, "td", "Acme Clubs")
      assert has_element?(view, "td", "Zeta Camps")
    end

    # The programs join must be a LEFT join: a session-scoped report has a NULL
    # program_id (DB CHECK one_of_program_or_session), so an inner join drops it.
    test "displays session-scoped reports, which have no program_id", %{conn: conn} do
      provider = provider_profile_fixture(business_name: "Session Only Provider")
      session = insert(:program_session_schema)

      incident_report_fixture(
        provider_profile_id: provider.id,
        reporter_user_id: provider.identity_id,
        session_id: session.id,
        reporter_display_name: "Session Reporter"
      )

      {:ok, view, _html} = live(conn, ~p"/admin/incidents")

      assert has_element?(view, "td", "Session Only Provider")
      assert has_element?(view, "td", "Session Reporter")
      assert has_element?(view, "span", "Session report")
    end

    test "description is not shown on the index", %{conn: conn} do
      %{provider: provider, program: program} = provider_with_program("Acme Clubs", "Robotics")

      incident_report_fixture(
        provider_profile_id: provider.id,
        reporter_user_id: provider.identity_id,
        program_id: program.id,
        description: "Sensitive free text that must stay off the index."
      )

      {:ok, _view, html} = live(conn, ~p"/admin/incidents")

      refute html =~ "Sensitive free text"
    end

    test "new incident button is not shown on index", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/incidents")
      refute has_element?(view, "a", "New")
    end

    test "displays the read-only safety banner", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/incidents")
      assert has_element?(view, "div.bg-amber-50", "Read-only safety record")
    end
  end

  describe "filters" do
    setup :register_and_log_in_admin

    setup do
      %{provider: provider, program: program} = provider_with_program("Acme Clubs", "Robotics")

      for {category, severity} <- [{:injury, :critical}, {:property_damage, :low}] do
        incident_report_fixture(
          provider_profile_id: provider.id,
          reporter_user_id: provider.identity_id,
          program_id: program.id,
          category: category,
          severity: severity
        )
      end

      :ok
    end

    # {filter key, submitted value, label that must survive, label that must not}
    @filter_cases [
      {"severity", "critical", "Critical", "Low"},
      {"category", "injury", "Injury", "Property damage"}
    ]

    test "each filter narrows the list to matching reports", %{conn: conn} do
      for {key, value, kept, dropped} <- @filter_cases do
        {:ok, view, _html} = live(conn, ~p"/admin/incidents")

        # Boolean filters render checkboxes (`name[]`), so the param is a list —
        # unlike the Select-based filters elsewhere in admin, which take a string.
        view
        |> element("form[phx-change='change-filter']")
        |> render_change(%{"filters" => %{key => [value]}})

        assert has_element?(view, "td", kept),
               "#{key}=#{value} should keep the #{kept} report"

        refute has_element?(view, "td", dropped),
               "#{key}=#{value} should drop the #{dropped} report"
      end
    end
  end

  describe "incident show" do
    setup :register_and_log_in_admin

    test "displays the full description", %{conn: conn} do
      %{provider: provider, program: program} = provider_with_program("Acme Clubs", "Robotics")

      report =
        incident_report_fixture(
          provider_profile_id: provider.id,
          reporter_user_id: provider.identity_id,
          program_id: program.id,
          description: "A child slipped near the play area but is unharmed."
        )

      {:ok, _view, html} = live(conn, ~p"/admin/incidents/#{report.id}/show")

      assert html =~ "slipped near the play area"
    end

    test "edit and delete buttons are not shown", %{conn: conn} do
      %{provider: provider, program: program} = provider_with_program("Acme Clubs", "Robotics")

      report =
        incident_report_fixture(
          provider_profile_id: provider.id,
          reporter_user_id: provider.identity_id,
          program_id: program.id
        )

      {:ok, view, _html} = live(conn, ~p"/admin/incidents/#{report.id}/show")

      refute has_element?(view, "a", "Edit")
      refute has_element?(view, "a", "Delete")
    end

    test "renders a signed URL for an attached photo", %{conn: conn} do
      %{provider: provider, program: program} = provider_with_program("Acme Clubs", "Robotics")

      report =
        incident_report_fixture(
          provider_profile_id: provider.id,
          reporter_user_id: provider.identity_id,
          program_id: program.id,
          photo_url: "incident-reports/providers/#{provider.id}/123_photo.jpg",
          original_filename: "photo.jpg"
        )

      {:ok, view, _html} = live(conn, ~p"/admin/incidents/#{report.id}/show")

      assert has_element?(view, ~s{img[src^="stub://signed/"]})
    end

    test "renders a no-photo marker when no photo is attached", %{conn: conn} do
      %{provider: provider, program: program} = provider_with_program("Acme Clubs", "Robotics")

      report =
        incident_report_fixture(
          provider_profile_id: provider.id,
          reporter_user_id: provider.identity_id,
          program_id: program.id
        )

      {:ok, view, _html} = live(conn, ~p"/admin/incidents/#{report.id}/show")

      assert has_element?(view, "span", "No photo")
      refute has_element?(view, "img[src^='stub://signed/']")
    end
  end
end
