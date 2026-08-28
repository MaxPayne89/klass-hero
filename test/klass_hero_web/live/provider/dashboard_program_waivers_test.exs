defmodule KlassHeroWeb.Provider.DashboardProgramWaiversTest do
  @moduledoc """
  The per-program waivers panel on the Programs tab: authoring the legal text parents sign
  at enrollment, publishing revisions, and retiring a form.

  Sibling of `dashboard_program_staffing_test.exs` — same modal shape, different concern.
  """
  use KlassHeroWeb.ConnCase, async: true

  import KlassHero.Factory
  import Phoenix.LiveViewTest

  alias KlassHero.Enrollment
  alias KlassHero.Repo

  setup :register_and_log_in_provider

  setup %{provider: provider} do
    %{program: insert_listed_program(provider, "Summer Camp")}
  end

  describe "opening and closing the panel" do
    test "opens from the program row and closes again", %{conn: conn, program: program} do
      {:ok, view, _html} = live(conn, ~p"/provider/dashboard/programs")

      refute has_element?(view, "#program-waivers-modal")

      view |> element("#manage-waivers-#{program.id}") |> render_click()
      assert has_element?(view, "#program-waivers-modal")

      view |> element("#program-waivers-modal button[phx-click=close_waivers]") |> render_click()
      refute has_element?(view, "#program-waivers-modal")
    end

    test "shows an empty state when the program has no waivers", %{conn: conn, program: program} do
      view = open_panel(conn, program)

      assert has_element?(view, "#waivers-empty")
    end
  end

  describe "creating a waiver" do
    test "publishes the first version and lists it", %{conn: conn, program: program} do
      view = open_panel(conn, program)

      view
      |> form("#waiver-form", %{
        waiver: %{title: "Liability Waiver", body: "I agree to hold the provider harmless.", required: "true"}
      })
      |> render_submit()

      assert has_element?(view, "#waiver-list")
      refute has_element?(view, "#waivers-empty")

      assert [%{waiver: waiver, version: version}] = Enrollment.list_program_waivers(program.id)
      assert waiver.title == "Liability Waiver"
      assert waiver.required
      assert version.version == 1
    end

    test "reports a blank body instead of creating an empty waiver", %{conn: conn, program: program} do
      view = open_panel(conn, program)

      html =
        view
        |> form("#waiver-form", %{waiver: %{title: "Liability Waiver", body: "   ", required: "true"}})
        |> render_submit()

      assert html =~ "body"
      assert Enrollment.list_program_waivers(program.id) == []
    end
  end

  describe "requirement labelling" do
    # One vocabulary across all three waiver surfaces (provider panel, booking form, signing
    # page). Labelling only one state would leave the other readable by absence — the weakest
    # signal for the fact that decides whether a parent can enrol at all.
    test "labels both required and optional waivers", %{conn: conn, program: program, provider: provider} do
      {:ok, %{waiver: blocking}} =
        Enrollment.create_waiver(provider.id, %{
          program_id: program.id,
          title: "Liability",
          required: true,
          body: "text"
        })

      {:ok, %{waiver: skippable}} =
        Enrollment.create_waiver(provider.id, %{
          program_id: program.id,
          title: "Photo release",
          required: false,
          body: "text"
        })

      view = open_panel(conn, program)

      assert has_element?(view, "#waiver-#{blocking.id}", "Required")
      assert has_element?(view, "#waiver-#{skippable.id}", "(optional)")
    end
  end

  describe "revising a waiver" do
    test "publishing new text bumps the version and keeps the old one readable", %{
      conn: conn,
      provider: provider,
      program: program
    } do
      {:ok, %{waiver: waiver, version: v1}} =
        Enrollment.create_waiver(provider.id, %{
          program_id: program.id,
          title: "Liability Waiver",
          body: "Original text"
        })

      view = open_panel(conn, program)

      view |> element("#edit-waiver-#{waiver.id}") |> render_click()

      view
      |> form("#waiver-form", %{waiver: %{body: "Revised text"}})
      |> render_submit()

      assert [%{version: current}] = Enrollment.list_program_waivers(program.id)
      assert current.version == 2
      assert current.body == "Revised text"

      # The signed wording of v1 is still on disk, unchanged.
      assert Repo.get(Enrollment.WaiverVersion, v1.id).body == "Original text"
    end
  end

  describe "archiving a waiver" do
    test "retires it from the list without deleting the record", %{
      conn: conn,
      provider: provider,
      program: program
    } do
      {:ok, %{waiver: waiver}} =
        Enrollment.create_waiver(provider.id, %{
          program_id: program.id,
          title: "Old form",
          body: "Text"
        })

      view = open_panel(conn, program)

      view |> element("#archive-waiver-#{waiver.id}") |> render_click()

      assert has_element?(view, "#waivers-empty")
      assert Enrollment.list_program_waivers(program.id) == []
      assert Repo.get(Enrollment.Waiver, waiver.id)
    end
  end

  describe "IDOR ownership guards" do
    test "refuses to open the panel for another provider's program", %{conn: conn} do
      other_provider = insert(:provider_profile_schema)
      victim_program = insert(:program_schema, provider_id: other_provider.id)

      {:ok, view, _html} = live(conn, ~p"/provider/dashboard/programs")

      view = assert_idor_guarded(view, "manage_waivers", victim_program.id, "Program not found.")
      refute has_element?(view, "#program-waivers-modal")
    end

    test "refuses to archive another provider's waiver", %{conn: conn, program: program} do
      other_provider = insert(:provider_profile_schema)
      victim_program = insert(:program_schema, provider_id: other_provider.id)

      {:ok, %{waiver: victim_waiver}} =
        Enrollment.create_waiver(other_provider.id, %{
          program_id: victim_program.id,
          title: "Their form",
          body: "Their text"
        })

      view = open_panel(conn, program)

      render_click(view, "archive_waiver", %{"id" => victim_waiver.id})

      # Untouched.
      assert [%{waiver: still_active}] = Enrollment.list_program_waivers(victim_program.id)
      assert still_active.id == victim_waiver.id
    end
  end

  defp open_panel(conn, program) do
    {:ok, view, _html} = live(conn, ~p"/provider/dashboard/programs")
    view |> element("#manage-waivers-#{program.id}") |> render_click()
    view
  end

  defp insert_listed_program(provider, title) do
    program = insert(:program_schema, provider_id: provider.id, title: title)

    program
  end
end
