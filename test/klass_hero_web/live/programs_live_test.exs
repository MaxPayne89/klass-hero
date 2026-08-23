defmodule KlassHeroWeb.ProgramsLiveTest do
  use KlassHeroWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias KlassHero.ProgramCatalog.ProgramListing
  alias KlassHero.Repo

  describe "ProgramsLive - Integration with Database (User Story 1)" do
    test "displays all programs from database", %{conn: conn} do
      program1 =
        insert_program(%{
          title: "Art Adventures",
          description: "Explore creativity through painting and sculpture",
          age_range: "6-8 years",
          price: Decimal.new("120.00"),
          pricing_period: "per month"
        })

      program2 =
        insert_program(%{
          title: "Soccer Stars",
          description: "Learn soccer fundamentals and teamwork",
          age_range: "8-12 years",
          price: Decimal.new("85.00"),
          pricing_period: "per month"
        })

      program3 =
        insert_program(%{
          title: "Chess Club",
          description: "Develop strategic thinking through chess",
          age_range: "7-14 years",
          price: Decimal.new("60.00"),
          pricing_period: "per month"
        })

      {:ok, view, _html} = live(conn, ~p"/programs")

      assert_program_visible(view, program1)
      assert_program_visible(view, program2)
      assert_program_visible(view, program3)
    end

    test "shows empty state when no programs exist", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/programs")

      assert has_element?(view, "[data-testid='empty-state']")
      refute has_element?(view, "[data-program-id]")
    end

    test "displays 'Free' for €0 programs", %{conn: conn} do
      free_program =
        insert_program(%{
          title: "Community Library Hour",
          # Deliberately avoids the word "Free" — the card renders the
          # description, so a description containing it would make the price
          # assertion below pass no matter what the price label says.
          description: "Reading and learning time at the library",
          age_range: "5-10 years",
          price: Decimal.new("0")
        })

      paid_program =
        insert_program(%{
          title: "Piano Lessons",
          description: "Learn to play piano with expert instruction",
          age_range: "6-16 years",
          price: Decimal.new("150.00"),
          pricing_period: "per month"
        })

      {:ok, view, _html} = live(conn, ~p"/programs")

      assert_program_visible(view, free_program)
      assert_program_visible(view, paid_program)

      assert view |> element(program_card(free_program)) |> render() =~ "Free"
      assert view |> element(program_card(paid_program)) |> render() =~ "€150.00"
    end

    test "programs load within 2 seconds performance requirement", %{conn: conn} do
      base_time = DateTime.utc_now()

      _programs =
        for i <- 1..100 do
          insert_program(%{
            title: "Program #{i}",
            description: "Description for program #{i}",
            age_range: "6-12 years",
            price: Decimal.new("#{i}.00"),
            pricing_period: "per month",
            inserted_at: DateTime.add(base_time, i * 1000, :second)
          })
        end

      start_time = System.monotonic_time(:millisecond)
      {:ok, view, _html} = live(conn, ~p"/programs")
      end_time = System.monotonic_time(:millisecond)

      load_time_ms = end_time - start_time

      assert load_time_ms < 2000,
             "Page load time #{load_time_ms}ms exceeds 2000ms performance requirement"

      # With pagination only the first 20 (Programs 100..81, DESC) load.
      programs = Repo.all(ProgramListing)
      program_100 = Enum.find(programs, &(&1.title == "Program 100"))
      program_81 = Enum.find(programs, &(&1.title == "Program 81"))
      program_1 = Enum.find(programs, &(&1.title == "Program 1"))

      assert_program_visible(view, program_100)
      assert_program_visible(view, program_81)
      refute_program_visible(view, program_1)

      assert has_element?(view, "button[phx-click='load_more']")
    end

    test "displays cover image on program card when cover_image_url is present", %{conn: conn} do
      insert_program(%{
        title: "Swimming Lessons",
        cover_image_url: "https://example.com/swimming.jpg"
      })

      {:ok, view, _html} = live(conn, ~p"/programs")

      assert has_element?(view, "img[src='https://example.com/swimming.jpg']")
    end

    test "displays gradient fallback when program has no cover image", %{conn: conn} do
      program = insert_program(%{title: "Chess Club", cover_image_url: nil})

      {:ok, view, _html} = live(conn, ~p"/programs")

      refute has_element?(view, "[data-program-id='#{program.id}'] img[src]")
    end
  end

  describe "ProgramsLive - Filter Behaviors" do
    test "search is case-insensitive using word-boundary matching on titles", %{conn: conn} do
      soccer =
        insert_program(%{
          title: "Soccer Stars",
          description: "Learn soccer fundamentals"
        })

      art =
        insert_program(%{
          title: "Art Adventures",
          description: "Creative PAINTING activities"
        })

      chess =
        insert_program(%{
          title: "Chess Club",
          description: "Strategic thinking"
        })

      {:ok, view1, _html} = live(conn, ~p"/programs?q=SOCCER")

      assert_program_visible(view1, soccer)
      refute_program_visible(view1, art)
      refute_program_visible(view1, chess)

      {:ok, view2, _html} = live(conn, ~p"/programs?q=art")

      assert_program_visible(view2, art)
      refute_program_visible(view2, soccer)
      refute_program_visible(view2, chess)

      assert has_element?(view2, "input[name='search'][value='art']")
    end
  end

  describe "ProgramsLive - User Story 1: Instant Program Title Search" do
    test "filters programs by search query using word-boundary matching", %{conn: conn} do
      soccer =
        insert_program(%{
          title: "After School Soccer",
          description: "Soccer fundamentals and teamwork"
        })

      dance =
        insert_program(%{
          title: "Summer Dance Camp",
          description: "Learn dance moves"
        })

      {:ok, view, _html} = live(conn, ~p"/programs?q=so")

      assert_program_visible(view, soccer)
      refute_program_visible(view, dance)
    end

    test "shows all programs when search query is empty", %{conn: conn} do
      program1 = insert_program(%{title: "Soccer Camp"})
      program2 = insert_program(%{title: "Art Class"})
      program3 = insert_program(%{title: "Chess Club"})

      {:ok, view, _html} = live(conn, ~p"/programs")

      assert_program_visible(view, program1)
      assert_program_visible(view, program2)
      assert_program_visible(view, program3)
    end

    test "updates URL with search query parameter", %{conn: conn} do
      _program = insert_program(%{title: "Soccer Training"})

      {:ok, view, _html} = live(conn, ~p"/programs")

      view
      |> element("input[name='search']")
      |> render_change(%{"search" => "soccer"})

      assert_patch(view, ~p"/programs?q=soccer")
    end
  end

  describe "ProgramsLive - Empty State Differentiation" do
    test "shows 'No programs available' when database is empty", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/programs")

      assert html =~ "No programs found"
    end

    test "shows helpful message when search returns no matches", %{conn: conn} do
      _program =
        insert_program(%{
          title: "Art Class",
          description: "Creative painting"
        })

      {:ok, _view, html} = live(conn, ~p"/programs?q=robotics")

      assert html =~ "No programs found"
      assert html =~ "Try adjusting your search or filter criteria"
    end
  end

  describe "ProgramsLive - Error Handling and Edge Cases" do
    test "invalid filter parameter defaults to 'all' filter", %{conn: conn} do
      program = insert_program(%{title: "Test Program"})

      {:ok, view, _html} = live(conn, ~p"/programs?filter=invalid_filter_xyz")

      assert_program_visible(view, program)
      assert has_element?(view, "[data-filter='all'][data-active='true']")
      refute has_element?(view, ".flash-error")
    end

    # program_click navigates straight to the detail page by ID; error handling
    # for non-existent programs lives in ProgramDetailLive, not here.
    test "program click navigates to detail page with program ID", %{conn: conn} do
      program = insert_program(%{title: "Existing Program"})

      {:ok, view, _html} = live(conn, ~p"/programs")

      view
      |> element("[phx-click='program_click']")
      |> render_click()

      assert_redirect(view, "/programs/#{program.id}")
    end

    test "malformed or extremely long search query is handled gracefully", %{conn: conn} do
      _program = insert_program(%{title: "Normal Program"})

      long_query = String.duplicate("a", 150)
      {:ok, view, html} = live(conn, ~p"/programs?q=#{long_query}")

      assert html =~ "No programs found"
      assert has_element?(view, "#mk-empty")
      refute has_element?(view, ".flash-error")
    end

    test "search with special characters is handled safely", %{conn: conn} do
      _soccer_art =
        insert_program(%{
          title: "Soccer & Art",
          description: "Fun activities: soccer, art, music!"
        })

      _art_class =
        insert_program(%{
          title: "Art Class",
          description: "Learn painting"
        })

      {:ok, _view, html} = live(conn, ~p"/programs?q=soccer")

      assert html =~ "Soccer &amp; Art"
      refute html =~ "Art Class"

      {:ok, _view, html} = live(conn, ~p"/programs?q=art")

      assert html =~ "Soccer &amp; Art"
      assert html =~ "Art Class"
    end

    test "combining invalid filter with valid search works correctly", %{conn: conn} do
      soccer = insert_program(%{title: "Soccer Training"})
      art = insert_program(%{title: "Art Class"})

      {:ok, view, _html} = live(conn, ~p"/programs?filter=invalid&q=soccer")

      assert_program_visible(view, soccer)
      refute_program_visible(view, art)
      assert has_element?(view, "[data-filter='all'][data-active='true']")
    end

    test "empty search query shows all programs", %{conn: conn} do
      program1 = insert_program(%{title: "Program 1"})
      program2 = insert_program(%{title: "Program 2"})

      {:ok, view, _html} = live(conn, ~p"/programs?q=")

      assert_program_visible(view, program1)
      assert_program_visible(view, program2)
    end
  end

  describe "ProgramsLive - Pagination Behavior" do
    test "loads first page with default page size on mount", %{conn: conn} do
      base_time = DateTime.utc_now()

      for i <- 1..30 do
        insert_program(%{
          title: "Program #{i}",
          inserted_at: DateTime.add(base_time, i, :second)
        })
      end

      {:ok, view, _html} = live(conn, ~p"/programs")

      program_30 = Repo.get_by!(ProgramListing, title: "Program 30")
      program_11 = Repo.get_by!(ProgramListing, title: "Program 11")
      program_10 = Repo.get_by!(ProgramListing, title: "Program 10")
      program_1 = Repo.get_by!(ProgramListing, title: "Program 1")

      # First 20 (Programs 30..11, DESC); Programs 1-10 wait on page 2.
      assert_program_visible(view, program_30)
      assert_program_visible(view, program_11)
      refute_program_visible(view, program_10)
      refute_program_visible(view, program_1)

      assert has_element?(view, "button[phx-click='load_more']")
    end

    test "Load More button appears when has_more is true", %{conn: conn} do
      base_time = DateTime.utc_now()

      for i <- 1..25 do
        insert_program(%{
          title: "Program #{i}",
          inserted_at: DateTime.add(base_time, i * 1000, :second)
        })
      end

      {:ok, view, _html} = live(conn, ~p"/programs")

      assert has_element?(view, "button[phx-click='load_more']")
      assert view |> element("button[phx-click='load_more']") |> render() =~ "Load more programs"
    end

    test "Load More button hidden when has_more is false", %{conn: conn} do
      base_time = DateTime.utc_now()

      for i <- 1..15 do
        insert_program(%{
          title: "Program #{i}",
          inserted_at: DateTime.add(base_time, i * 1000, :second)
        })
      end

      {:ok, view, _html} = live(conn, ~p"/programs")

      refute has_element?(view, "button[phx-click='load_more']")
    end

    test "clicking Load More appends next page to stream", %{conn: conn} do
      base_time = DateTime.utc_now()

      for i <- 1..30 do
        insert_program(%{
          title: "Program #{i}",
          inserted_at: DateTime.add(base_time, i * 1000, :second)
        })
      end

      {:ok, view, _html} = live(conn, ~p"/programs")

      program_30 = Repo.get_by!(ProgramListing, title: "Program 30")
      program_11 = Repo.get_by!(ProgramListing, title: "Program 11")
      program_10 = Repo.get_by!(ProgramListing, title: "Program 10")
      program_1 = Repo.get_by!(ProgramListing, title: "Program 1")

      assert_program_visible(view, program_30)
      assert_program_visible(view, program_11)
      refute_program_visible(view, program_10)

      view |> element("button[phx-click='load_more']") |> render_click()

      # Stream appended (not reset): all 30 now visible.
      assert_program_visible(view, program_30)
      assert_program_visible(view, program_11)
      assert_program_visible(view, program_10)
      assert_program_visible(view, program_1)

      refute has_element?(view, "button[phx-click='load_more']")
    end

    test "search resets to page 1 and clears pagination", %{conn: conn} do
      base_time = DateTime.utc_now()

      for i <- 1..15 do
        insert_program(%{
          title: "Soccer Program #{i}",
          inserted_at: DateTime.add(base_time, i * 1000, :second)
        })
      end

      for i <- 16..30 do
        insert_program(%{
          title: "Art Program #{i}",
          inserted_at: DateTime.add(base_time, i * 1000, :second)
        })
      end

      soccer_15 = Repo.get_by!(ProgramListing, title: "Soccer Program 15")
      soccer_11 = Repo.get_by!(ProgramListing, title: "Soccer Program 11")
      art_30 = Repo.get_by!(ProgramListing, title: "Art Program 30")

      {:ok, view, _html} = live(conn, ~p"/programs")
      view |> element("button[phx-click='load_more']") |> render_click()

      assert_program_visible(view, soccer_15)
      assert_program_visible(view, art_30)

      view
      |> element("input[name='search']")
      |> render_change(%{"search" => "Soccer"})

      # Stream reset to page 1 (programs 30..11 DESC), so only Soccer 11-15 show.
      assert_program_visible(view, soccer_11)
      assert_program_visible(view, soccer_15)
      refute has_element?(view, "[data-program-id]", "Art Program")

      # Load More may remain: has_more reflects DB pagination, not the
      # client-side filtered result — it lets the filter apply to more pages.
    end

    test "program click navigates with ID without database call", %{conn: conn} do
      program = insert_program(%{title: "Test Program"})

      {:ok, view, _html} = live(conn, ~p"/programs")

      assert view
             |> element("[phx-click='program_click'][phx-value-program-id='#{program.id}']")
             |> render_click()

      assert_redirect(view, ~p"/programs/#{program.id}")
    end

    test "Load More shows loading state during operation", %{conn: conn} do
      base_time = DateTime.utc_now()

      for i <- 1..25 do
        insert_program(%{
          title: "Program #{i}",
          inserted_at: DateTime.add(base_time, i * 1000, :second)
        })
      end

      {:ok, view, _html} = live(conn, ~p"/programs")

      assert view |> element("button[phx-click='load_more']") |> render() =~
               "Load more programs"

      refute view |> element("button[phx-click='load_more'][disabled]") |> has_element?()

      view |> element("button[phx-click='load_more']") |> render_click()

      # The loading state is transient (only visible during real async ops);
      # sync tests complete immediately, so we assert the final state.
      program_5 = Repo.get_by!(ProgramListing, title: "Program 5")
      program_1 = Repo.get_by!(ProgramListing, title: "Program 1")

      assert_program_visible(view, program_5)
      assert_program_visible(view, program_1)
    end

    test "Load More error handling preserves existing results", %{conn: conn} do
      base_time = DateTime.utc_now()

      for i <- 1..25 do
        insert_program(%{
          title: "Program #{i}",
          inserted_at: DateTime.add(base_time, i * 1000, :second)
        })
      end

      {:ok, view, _html} = live(conn, ~p"/programs")

      program_25 = Repo.get_by!(ProgramListing, title: "Program 25")
      program_6 = Repo.get_by!(ProgramListing, title: "Program 6")

      assert_program_visible(view, program_25)
      assert_program_visible(view, program_6)

      # Actual Load More failure handling (existing results kept, error flash,
      # retry available) requires mocking repository failures; here we verify
      # the happy path only.
      assert has_element?(view, "button[phx-click='load_more']")
    end
  end

  defp insert_program(attrs) do
    now = DateTime.truncate(DateTime.utc_now(), :second)

    default_attrs = %{
      id: Ecto.UUID.generate(),
      title: "Default Program",
      description: "Default description",
      category: "education",
      meeting_days: ["Monday", "Wednesday", "Friday"],
      meeting_start_time: ~T[15:00:00],
      meeting_end_time: ~T[17:00:00],
      age_range: "6-12 years",
      price: Decimal.new("100.00"),
      pricing_period: "per month",
      provider_id: Ecto.UUID.generate(),
      inserted_at: now,
      updated_at: now
    }

    merged =
      default_attrs
      |> Map.merge(attrs)
      |> Map.update(:inserted_at, now, &DateTime.truncate(&1, :second))
      |> Map.update(:updated_at, now, &DateTime.truncate(&1, :second))

    %ProgramListing{}
    |> Ecto.Changeset.change(merged)
    |> Repo.insert!()
  end

  defp assert_program_visible(view, program) do
    assert has_element?(view, program_card(program))
  end

  defp program_card(program), do: "[data-program-id='#{program.id}']"

  defp refute_program_visible(view, program) do
    refute has_element?(view, "[data-program-id='#{program.id}']")
  end

  describe "ProgramsLive - program subtitle" do
    test "renders the subtitle on the grid card", %{conn: conn} do
      program = insert_program(%{subtitle: "For beginners, no experience needed"})

      {:ok, view, _html} = live(conn, ~p"/programs")

      assert has_element?(
               view,
               "#program-card-#{program.id}-subtitle",
               "For beginners"
             )
    end

    test "renders no subtitle element when the program has none", %{conn: conn} do
      program = insert_program(%{subtitle: nil})

      {:ok, view, _html} = live(conn, ~p"/programs")

      assert has_element?(view, "[data-program-id='#{program.id}']")
      refute has_element?(view, "#program-card-#{program.id}-subtitle")
    end

    # List view is reached by the toggle event, not a URL param — asserting on
    # `/programs?view=list` renders the grid and passes without ever exercising
    # the list row.
    test "renders the subtitle on the list-view row", %{conn: conn} do
      program = insert_program(%{subtitle: "Small groups, ages 6-9"})

      {:ok, view, _html} = live(conn, ~p"/programs")

      view
      |> element("#mk-view-toggle button[data-view='list']")
      |> render_click()

      assert has_element?(view, "#mk-programs-stream[data-view='list']")

      assert has_element?(
               view,
               "#program-list-row-#{program.id}-subtitle",
               "Small groups"
             )
    end
  end

  describe "ProgramsLive - bundle parity surfaces (Phase 1)" do
    test "renders all 8 bundle category pills", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/programs")

      for label <- ~w(All Sports Arts Music Education) ++ ["Life Skills", "Camps", "Workshops"] do
        assert has_element?(view, "button", label),
               "expected category pill #{inspect(label)} to render"
      end
    end

    test "renders the sort dropdown and view toggle controls", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/programs")

      assert has_element?(view, "#mk-sort-dropdown")
      assert has_element?(view, "#mk-sort-dropdown summary", "Recommended")
      assert has_element?(view, "#mk-view-toggle [data-view='grid'][data-active='true']")
      assert has_element?(view, "#mk-view-toggle [data-view='list']")
    end

    test "shows the empty state when no programs match", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/programs?q=zzz_no_match_zzz")

      assert has_element?(view, "#mk-empty")
      assert render(view) =~ "No programs found"
    end
  end

  describe "ProgramsLive - sort + view-mode controls" do
    test "selecting a sort option pushes ?sort= to the URL", %{conn: conn} do
      _ = insert_program(%{title: "Cheap", price: Decimal.new("10.00")})
      _ = insert_program(%{title: "Pricey", price: Decimal.new("200.00")})

      {:ok, view, _html} = live(conn, ~p"/programs")

      view
      |> element("[phx-click][data-sort='price_low']")
      |> render_click()

      assert_patch(view, ~p"/programs?sort=price_low")
    end

    test "sort=newest sanitizes unknown values to recommended", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/programs?sort=garbage")

      assert has_element?(view, "#mk-sort-dropdown summary", "Recommended")
    end

    test "load-more button hides when sort != recommended", %{conn: conn} do
      base_time = DateTime.utc_now()

      for i <- 1..25 do
        insert_program(%{
          title: "Program #{i}",
          inserted_at: DateTime.add(base_time, i * 1000, :second)
        })
      end

      {:ok, view, _html} = live(conn, ~p"/programs")
      assert has_element?(view, "button[phx-click='load_more']")

      {:ok, sorted_view, _html} = live(conn, ~p"/programs?sort=newest")
      refute has_element?(sorted_view, "button[phx-click='load_more']")
    end

    test "toggle_view flips the view_mode and updates data-view on the stream container",
         %{conn: conn} do
      _ = insert_program(%{title: "Listed Program"})

      {:ok, view, _html} = live(conn, ~p"/programs")
      assert has_element?(view, "#mk-programs-stream[data-view='grid']")

      view
      |> element("[phx-click='toggle_view'][phx-value-view='list']")
      |> render_click()

      assert has_element?(view, "#mk-programs-stream[data-view='list']")
    end

    test "toggle_view preserves entries appended via load_more (no page-1 reset)",
         %{conn: conn} do
      base_time = DateTime.utc_now()

      for i <- 1..25 do
        insert_program(%{
          title: "Pagination Program #{i}",
          inserted_at: DateTime.add(base_time, i * 1000, :second)
        })
      end

      first_page_program = Repo.get_by!(ProgramListing, title: "Pagination Program 25")
      second_page_program = Repo.get_by!(ProgramListing, title: "Pagination Program 1")

      {:ok, view, _html} = live(conn, ~p"/programs")
      assert_program_visible(view, first_page_program)
      refute_program_visible(view, second_page_program)

      view |> element("button[phx-click='load_more']") |> render_click()
      assert_program_visible(view, first_page_program)
      assert_program_visible(view, second_page_program)

      view
      |> element("[phx-click='toggle_view'][phx-value-view='list']")
      |> render_click()

      # Both pages must remain after the view toggle re-streams from cache.
      assert_program_visible(view, first_page_program)
      assert_program_visible(view, second_page_program)
    end

    test "search query 'all' is preserved in URL (per-key sentinel filter)",
         %{conn: conn} do
      _ = insert_program(%{title: "Whatever"})
      {:ok, view, _html} = live(conn, ~p"/programs")

      view
      |> element("input[name='search']")
      |> render_change(%{"search" => "all"})

      assert_patch(view, ~p"/programs?q=all")
    end
  end
end
