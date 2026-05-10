defmodule KlassHeroWeb.Provider.IncidentReportsLiveTest do
  use KlassHeroWeb.ConnCase, async: true

  import KlassHero.Factory
  import KlassHero.ProviderFixtures
  import Phoenix.LiveViewTest

  alias KlassHero.Provider.Adapters.Driven.Persistence.Schemas.ProviderProgramProjectionSchema
  alias KlassHero.Provider.Adapters.Driven.Persistence.Schemas.ProviderSessionDetailSchema
  alias KlassHero.Repo

  defp insert_owned_program!(provider_id, name) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    program_id = Ecto.UUID.generate()

    Repo.insert!(%ProviderProgramProjectionSchema{
      program_id: program_id,
      provider_id: provider_id,
      name: name,
      status: "active",
      inserted_at: now,
      updated_at: now
    })

    insert(:program_schema, id: program_id, provider_id: provider_id)

    program_id
  end

  defp put_provider_session_detail!(session_id, program_id, provider_id) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    Repo.insert!(%ProviderSessionDetailSchema{
      session_id: session_id,
      program_id: program_id,
      program_title: "Test Program",
      provider_id: provider_id,
      session_date: ~D[2026-04-21],
      start_time: ~T[09:00:00],
      end_time: ~T[12:00:00],
      status: :scheduled,
      checked_in_count: 0,
      total_count: 0,
      inserted_at: now,
      updated_at: now
    })
  end

  describe "auth" do
    test "redirects to login when not authenticated", %{conn: conn} do
      bogus_id = Ecto.UUID.generate()

      assert {:error, {:redirect, %{to: path}}} =
               live(conn, ~p"/provider/programs/#{bogus_id}/incidents")

      assert path =~ "/users/log-in"
    end
  end

  describe "ownership" do
    setup :register_and_log_in_provider

    test "redirects to dashboard when program is not owned by provider", %{conn: conn} do
      bogus_id = Ecto.UUID.generate()

      assert {:error, {:live_redirect, %{to: "/provider/dashboard/programs", flash: flash}}} =
               live(conn, ~p"/provider/programs/#{bogus_id}/incidents")

      assert flash["error"] =~ "not found"
    end
  end

  describe "empty state" do
    setup :register_and_log_in_provider

    test "renders empty marker when there are no reports", %{conn: conn, provider: provider} do
      program_id = insert_owned_program!(provider.id, "Robotics")

      {:ok, view, _html} = live(conn, ~p"/provider/programs/#{program_id}/incidents")

      assert has_element?(view, "#incident-reports-empty")
    end
  end

  describe "sidebar navigation" do
    setup :register_and_log_in_provider

    test "highlights Programs in the sidebar", %{conn: conn, provider: provider} do
      program_id = insert_owned_program!(provider.id, "Robotics")

      {:ok, view, _html} = live(conn, ~p"/provider/programs/#{program_id}/incidents")

      assert has_element?(view, "a[aria-current='page']", "Programs")
    end
  end

  describe "list" do
    setup :register_and_log_in_provider

    test "renders program-direct reports with reporter name and category", %{
      conn: conn,
      provider: provider,
      user: user
    } do
      program_id = insert_owned_program!(provider.id, "Robotics")

      _ =
        incident_report_fixture(
          provider_profile_id: provider.id,
          reporter_user_id: user.id,
          program_id: program_id,
          reporter_display_name: "Maria Schmidt",
          category: :injury,
          severity: :high
        )

      {:ok, _view, html} = live(conn, ~p"/provider/programs/#{program_id}/incidents")

      assert html =~ "Maria Schmidt"
      assert html =~ "Injury"
      assert html =~ "High"
    end

    test "includes session-linked reports for sessions of the program", %{
      conn: conn,
      provider: provider,
      user: user
    } do
      program_id = insert_owned_program!(provider.id, "Robotics")
      session = insert(:program_session_schema, program_id: program_id)
      put_provider_session_detail!(session.id, program_id, provider.id)

      _ =
        incident_report_fixture(
          provider_profile_id: provider.id,
          reporter_user_id: user.id,
          program_id: nil,
          session_id: session.id,
          reporter_display_name: "Anna Becker",
          category: :safety_concern
        )

      {:ok, _view, html} = live(conn, ~p"/provider/programs/#{program_id}/incidents")

      assert html =~ "Anna Becker"
      assert html =~ "Safety concern"
    end

    test "lists reports ordered by occurred_at descending", %{
      conn: conn,
      provider: provider,
      user: user
    } do
      program_id = insert_owned_program!(provider.id, "Robotics")

      _older =
        incident_report_fixture(
          provider_profile_id: provider.id,
          reporter_user_id: user.id,
          program_id: program_id,
          reporter_display_name: "Older Reporter",
          occurred_at: ~U[2026-04-10 09:00:00Z]
        )

      _newer =
        incident_report_fixture(
          provider_profile_id: provider.id,
          reporter_user_id: user.id,
          program_id: program_id,
          reporter_display_name: "Newer Reporter",
          occurred_at: ~U[2026-04-22 09:00:00Z]
        )

      {:ok, _view, html} = live(conn, ~p"/provider/programs/#{program_id}/incidents")

      assert :binary.match(html, "Newer Reporter") < :binary.match(html, "Older Reporter")
    end
  end
end
