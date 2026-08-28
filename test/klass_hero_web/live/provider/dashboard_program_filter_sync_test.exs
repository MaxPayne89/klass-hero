defmodule KlassHeroWeb.Provider.DashboardProgramFilterSyncTest do
  @moduledoc """
  What saving a program does to a *filtered* programs table.

  Sibling of `dashboard_program_creation_test.exs` (the form itself) and
  `dashboard_program_staffing_test.exs` (the per-program staffing panel). This one
  owns the interaction between the two: the table filters on search and staff, so
  every path that writes a single row has to agree with the filters the table
  claims to be applying (#1346).
  """
  use KlassHeroWeb.ConnCase, async: true

  import KlassHero.Factory
  import Phoenix.LiveViewTest

  alias KlassHero.ProgramCatalog.Program
  alias KlassHero.Provider
  alias KlassHero.Repo

  setup :register_and_log_in_provider

  # "New Program" is disabled for an unverified provider, so every test here
  # would fail on the button rather than on what it is actually pinning.
  setup %{provider: provider} do
    provider
    |> Ecto.Changeset.change(%{
      verified: true,
      verified_at: DateTime.utc_now() |> DateTime.truncate(:second)
    })
    |> Repo.update!()

    %{ann: insert_staff(provider, "Ann", "Blake")}
  end

  describe "creating while a filter is active" do
    test "shows the new program and clears the staff filter that would hide it", %{
      conn: conn,
      provider: provider,
      ann: ann
    } do
      staffed = insert_listed_program(provider, "Ann's Camp")
      assign_staff!(staffed, ann)

      {:ok, view, _html} = live(conn, ~p"/provider/dashboard/programs")

      filter_by_staff(view, ann)
      assert has_element?(view, "#programs-#{staffed.id}")

      create_program(view, "Unstaffed Chess Club")

      created = Repo.get_by!(Program, title: "Unstaffed Chess Club")

      assert has_element?(view, "#programs-#{created.id}")
      assert has_element?(view, "#programs-staff-filter-form option[value=all][selected]")
    end

    test "shows the new program and clears the search that would hide it", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/provider/dashboard/programs")

      search_for(view, "Pottery")

      create_program(view, "Unstaffed Chess Club")

      created = Repo.get_by!(Program, title: "Unstaffed Chess Club")

      assert has_element?(view, "#programs-#{created.id}")
      assert has_element?(view, ~s(#programs-search-form input[name=search][value=""]))
    end

    # Deliberate, not incidental: when one axis hides the new row, *both* yield,
    # even the one it still matches. Surgical per-axis clearing would buy a
    # rarely-hit nicety for a branch on every combination.
    test "clears both axes when only one of them hides the new program", %{
      conn: conn,
      provider: provider,
      ann: ann
    } do
      staffed = insert_listed_program(provider, "Ann's Chess Camp")
      assign_staff!(staffed, ann)

      {:ok, view, _html} = live(conn, ~p"/provider/dashboard/programs")

      search_for(view, "Chess")
      filter_by_staff(view, ann)

      # Matches the search, but has no staff at all — only the staff axis hides it.
      create_program(view, "Chess Club")

      created = Repo.get_by!(Program, title: "Chess Club")

      assert has_element?(view, "#programs-#{created.id}")
      assert has_element?(view, "#programs-staff-filter-form option[value=all][selected]")
      assert has_element?(view, ~s(#programs-search-form input[name=search][value=""]))
    end

    # The filter only yields when it would hide the new row. A provider who
    # searched for "Chess" and then made a chess program keeps their search.
    test "keeps a filter the new program already matches", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/provider/dashboard/programs")

      search_for(view, "Chess")

      create_program(view, "Unstaffed Chess Club")

      created = Repo.get_by!(Program, title: "Unstaffed Chess Club")

      assert has_element?(view, "#programs-#{created.id}")
      assert has_element?(view, ~s(#programs-search-form input[name=search][value="Chess"]))
    end
  end

  describe "editing while a filter is active" do
    # The edit is the opposite call from the create: nothing here was just made,
    # so the row that no longer matches leaves rather than the filter.
    test "drops the row when the edit renames the program out of the search", %{
      conn: conn,
      provider: provider
    } do
      program = insert_listed_program(provider, "Chess Club")

      {:ok, view, _html} = live(conn, ~p"/provider/dashboard/programs")

      search_for(view, "Chess")
      assert has_element?(view, "#programs-#{program.id}")

      edit_program(view, program, "Pottery Basics")

      refute has_element?(view, "#programs-#{program.id}")
    end

    # The filter controls sit outside the program form, so a provider can change
    # the filter with the form open and save into a table that no longer wants
    # the row.
    test "does not re-insert the row when a staff filter excludes the program", %{
      conn: conn,
      provider: provider,
      ann: ann
    } do
      program = insert_listed_program(provider, "Chess Club")

      {:ok, view, _html} = live(conn, ~p"/provider/dashboard/programs")

      view
      |> element(~s([phx-click="edit_program"][phx-value-id="#{program.id}"]))
      |> render_click()

      filter_by_staff(view, ann)
      refute has_element?(view, "#programs-#{program.id}")

      view
      |> form("#program-form", %{
        "program_schema" => %{
          "title" => "Chess Club",
          "description" => "Saved while a foreign staff filter was active",
          "category" => "arts",
          "price" => "25.00"
        }
      })
      |> render_submit()

      refute has_element?(view, "#programs-#{program.id}")
    end

    # The other direction: the same writer has to *add* a row an edit moved into
    # the filter, not only drop one it moved out.
    test "shows the row when the edit renames the program into the search", %{
      conn: conn,
      provider: provider
    } do
      program = insert_listed_program(provider, "Chess Club")

      {:ok, view, _html} = live(conn, ~p"/provider/dashboard/programs")

      view
      |> element(~s([phx-click="edit_program"][phx-value-id="#{program.id}"]))
      |> render_click()

      search_for(view, "Pottery")
      refute has_element?(view, "#programs-#{program.id}")

      view
      |> form("#program-form", %{
        "program_schema" => %{
          "title" => "Pottery Basics",
          "description" => "Renamed into the active search",
          "category" => "arts",
          "price" => "25.00"
        }
      })
      |> render_submit()

      assert has_element?(view, "#programs-#{program.id}")
    end
  end

  describe "staffing the program while a filter is active" do
    # The third write path. #1334 taught it the staff filter; it learned the
    # search filter only by being folded onto the shared row writer, and nothing
    # in the staffing suite covers that axis.
    test "does not re-insert the row when the search no longer matches", %{
      conn: conn,
      provider: provider,
      ann: ann
    } do
      program = insert_listed_program(provider, "Chess Club")

      {:ok, view, _html} = live(conn, ~p"/provider/dashboard/programs")

      view |> element("#manage-staffing-#{program.id}") |> render_click()

      search_for(view, "Pottery")
      refute has_element?(view, "#programs-#{program.id}")

      view |> form("#staffing-add-form", %{"staff-id" => ann.id}) |> render_submit()

      assert has_element?(view, "#staffing-member-#{ann.id}")
      refute has_element?(view, "#programs-#{program.id}")
    end
  end

  # Drives the wrapping <form>, not the bare <select>: LiveView rejects a
  # phx-change on an input outside a form in the browser, and `element/2` +
  # render_change/2 would happily bypass that check (#1310).
  defp filter_by_staff(view, staff) do
    view
    |> form("#programs-staff-filter-form", %{"staff_filter" => staff.id})
    |> render_change()
  end

  defp search_for(view, query) do
    view
    |> form("#programs-search-form", %{"search" => query})
    |> render_change()
  end

  defp create_program(view, title) do
    view |> element("#new-program-btn") |> render_click()

    view
    |> form("#program-form", %{
      "program_schema" => %{
        "title" => title,
        "description" => "Created while a filter was active",
        "category" => "arts",
        "price" => "25.00"
      }
    })
    |> render_submit()
  end

  defp edit_program(view, program, new_title) do
    view
    |> element(~s([phx-click="edit_program"][phx-value-id="#{program.id}"]))
    |> render_click()

    view
    |> form("#program-form", %{
      "program_schema" => %{
        "title" => new_title,
        "description" => "Renamed while a filter was active",
        "category" => "arts",
        "price" => "25.00"
      }
    })
    |> render_submit()
  end

  # The provider programs table renders from the `program_listings` read table, so
  # a program without a matching listing row is invisible and every row-level
  # assertion below would fail for an unrelated reason.
  defp insert_listed_program(provider, title) do
    program = insert(:program_schema, provider_id: provider.id, title: title)

    program
  end

  defp insert_staff(provider, first_name, last_name) do
    insert(:staff_member_schema, provider_id: provider.id, first_name: first_name, last_name: last_name)
  end

  defp assign_staff!(program, staff) do
    {:ok, assignment} =
      Provider.assign_staff_to_program(%{
        provider_id: program.provider_id,
        program_id: program.id,
        staff_member_id: staff.id
      })

    assignment
  end
end
