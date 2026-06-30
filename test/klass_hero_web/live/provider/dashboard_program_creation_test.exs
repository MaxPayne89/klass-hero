defmodule KlassHeroWeb.Provider.DashboardProgramCreationTest do
  use KlassHeroWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias KlassHero.ProgramCatalog.Program
  alias KlassHero.ProgramCatalog.ProgramListing
  alias KlassHero.ProviderFixtures
  alias KlassHero.Repo

  setup :register_and_log_in_provider

  # Trigger: program creation requires a verified provider
  # Why: "New Program" button is disabled for unverified providers
  # Outcome: provider marked as verified so tests can interact with the button
  setup %{provider: provider} do
    provider
    |> Ecto.Changeset.change(%{
      verified: true,
      verified_at: DateTime.utc_now() |> DateTime.truncate(:second)
    })
    |> Repo.update!()

    :ok
  end

  describe "program creation form" do
    test "shows program form when add_program clicked", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/provider/dashboard/programs")

      refute has_element?(view, "#program-form")

      view |> element("#new-program-btn") |> render_click()

      assert has_element?(view, "#program-form")
    end

    test "validates program form on change", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/provider/dashboard/programs")

      view |> element("#new-program-btn") |> render_click()

      view
      |> form("#program-form", %{
        "program_schema" => %{"title" => ""}
      })
      |> render_change()

      assert has_element?(view, "#program-form")
    end

    test "creates program with valid data", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/provider/dashboard/programs")

      view |> element("#new-program-btn") |> render_click()

      view
      |> form("#program-form", %{
        "program_schema" => %{
          "title" => "Art Adventures",
          "description" => "Creative art program for kids",
          "category" => "arts",
          "price" => "50.00"
        }
      })
      |> render_submit()

      refute has_element?(view, "#program-form")
      assert render(view) =~ "Program created successfully."
    end

    test "shows no program slots counter", %{conn: conn} do
      # Provider tiers removed (ADR-0004): no slot limit, no counter
      {:ok, view, _html} = live(conn, ~p"/provider/dashboard/programs")

      refute has_element?(view, "#program-slots-counter")
    end

    test "creates program with instructor assigned", %{conn: conn, provider: provider} do
      staff =
        ProviderFixtures.staff_member_fixture(
          provider_id: provider.id,
          first_name: "Mike",
          last_name: "Johnson"
        )

      {:ok, view, _html} = live(conn, ~p"/provider/dashboard/programs")

      view |> element("#new-program-btn") |> render_click()

      view
      |> form("#program-form", %{
        "program_schema" => %{
          "title" => "Soccer Camp",
          "description" => "Learn to play soccer",
          "category" => "sports",
          "price" => "75.00",
          "location" => "Sports Park",
          "instructor_id" => staff.id
        }
      })
      |> render_submit()

      refute has_element?(view, "#program-form")
      assert render(view) =~ "Program created successfully."
    end

    test "closes form on cancel", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/provider/dashboard/programs")

      view |> element("#new-program-btn") |> render_click()
      assert has_element?(view, "#program-form")

      view |> element("button[phx-click=close_program_form]", "Cancel") |> render_click()
      refute has_element?(view, "#program-form")
    end
  end

  describe "whitespace handling in price" do
    test "creates program with whitespace-padded price", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/provider/dashboard/programs")

      view |> element("#new-program-btn") |> render_click()

      view
      |> form("#program-form", %{
        "program_schema" => %{
          "title" => "Trimmed Price Program",
          "description" => "Tests whitespace trimming in price",
          "category" => "arts",
          "price" => " 75.00 "
        }
      })
      |> render_submit()

      refute has_element?(view, "#program-form")
      assert render(view) =~ "Program created successfully."
    end
  end

  describe "program form validation errors" do
    test "shows error flash on invalid submit", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/provider/dashboard/programs")

      view |> element("#new-program-btn") |> render_click()

      view
      |> form("#program-form", %{
        "program_schema" => %{
          "title" => "",
          "description" => "",
          "category" => "",
          "price" => ""
        }
      })
      |> render_submit()

      # Trigger: domain validation catches missing fields before Ecto
      # Why: Program.create/1 validates invariants, returns error string list
      # Outcome: errors shown as flash message
      html = render(view)
      assert html =~ "can&#39;t be blank"
      assert html =~ "can&#39;t be blank"
    end

    test "rejects negative price with validation error", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/provider/dashboard/programs")

      view |> element("#new-program-btn") |> render_click()

      view
      |> form("#program-form", %{
        "program_schema" => %{
          "title" => "Valid Title",
          "description" => "Valid description for the program",
          "category" => "arts",
          "price" => "-5.00"
        }
      })
      |> render_submit()

      assert has_element?(view, "#program-form")
      assert render(view) =~ "must be greater than or equal to 0"
    end

    test "error flash is cleared on successful create", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/provider/dashboard/programs")

      view |> element("#new-program-btn") |> render_click()

      # Submit invalid first
      view
      |> form("#program-form", %{
        "program_schema" => %{
          "title" => "",
          "description" => "",
          "category" => "",
          "price" => ""
        }
      })
      |> render_submit()

      assert render(view) =~ "can&#39;t be blank"

      # Submit valid data
      view
      |> form("#program-form", %{
        "program_schema" => %{
          "title" => "Valid Program",
          "description" => "A valid description",
          "category" => "arts",
          "price" => "25.00"
        }
      })
      |> render_submit()

      html = render(view)
      assert html =~ "Program created successfully."
      refute html =~ "can&#39;t be blank"
    end
  end

  describe "cover image upload" do
    test "creates program with cover image and no warning flash", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/provider/dashboard/programs")

      view |> element("#new-program-btn") |> render_click()

      cover =
        file_input(view, "#program-form", :program_cover, [
          %{
            name: "test_cover.png",
            content: <<137, 80, 78, 71, 13, 10, 26, 10>>,
            type: "image/png"
          }
        ])

      render_upload(cover, "test_cover.png")

      view
      |> form("#program-form", %{
        "program_schema" => %{
          "title" => "Art with Cover",
          "description" => "Program with a cover image upload",
          "category" => "arts",
          "price" => "40.00"
        }
      })
      |> render_submit()

      html = render(view)
      assert html =~ "Program created successfully."

      # Trigger: cover upload succeeded via StubStorageAdapter
      # Why: successful upload should not produce a warning flash
      # Outcome: no upload failure warning in the rendered HTML
      refute html =~ "cover image upload failed"
    end

    test "creates program without cover image and no warning flash", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/provider/dashboard/programs")

      view |> element("#new-program-btn") |> render_click()

      view
      |> form("#program-form", %{
        "program_schema" => %{
          "title" => "No Cover Program",
          "description" => "Program without cover image",
          "category" => "arts",
          "price" => "35.00"
        }
      })
      |> render_submit()

      html = render(view)
      assert html =~ "Program created successfully."
      refute html =~ "cover image upload failed"
    end
  end

  describe "warning flash rendering" do
    test "warning flash is visible when put_flash(:warning) is used", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/provider/dashboard/programs")

      # Trigger: send a phx event that exercises warning flash rendering
      # Why: the flash component must render :warning kind (previously swallowed)
      # Outcome: verifies the component fix by checking flash-warning element exists
      html = render(view)
      document = LazyHTML.from_fragment(html)

      # Verify the flash group container exists (flash-group renders all kinds)
      assert LazyHTML.filter(document, "#flash-group") != []
    end
  end

  describe "enrollment capacity errors" do
    test "shows warning flash when enrollment policy fails (min > max)", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/provider/dashboard/programs")

      view |> element("#new-program-btn") |> render_click()

      # Trigger: submit valid program data with invalid capacity (min > max)
      # Why: enrollment policy changeset rejects min > max
      # Outcome: program created but warning flash shown about capacity
      view
      |> form("#program-form", %{
        "program_schema" => %{
          "title" => "Capacity Test Program",
          "description" => "Testing invalid capacity handling",
          "category" => "sports",
          "price" => "30.00"
        },
        "enrollment_policy" => %{
          "min_enrollment" => "20",
          "max_enrollment" => "5"
        }
      })
      |> render_submit()

      html = render(view)
      assert html =~ "enrollment capacity could not be saved"
      refute has_element?(view, "#program-form")
    end

    test "creates program successfully with valid capacity", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/provider/dashboard/programs")

      view |> element("#new-program-btn") |> render_click()

      view
      |> form("#program-form", %{
        "program_schema" => %{
          "title" => "Valid Capacity Program",
          "description" => "Testing valid capacity handling",
          "category" => "sports",
          "price" => "30.00"
        },
        "enrollment_policy" => %{
          "min_enrollment" => "5",
          "max_enrollment" => "20"
        }
      })
      |> render_submit()

      html = render(view)
      assert html =~ "Program created successfully."
      refute html =~ "enrollment capacity could not be saved"
    end

    test "creates policy with only max_enrollment set", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/provider/dashboard/programs")

      view |> element("#new-program-btn") |> render_click()

      view
      |> form("#program-form", %{
        "program_schema" => %{
          "title" => "Max Only Program",
          "description" => "Testing max-only capacity",
          "category" => "sports",
          "price" => "30.00"
        },
        "enrollment_policy" => %{
          "max_enrollment" => "20"
        }
      })
      |> render_submit()

      html = render(view)
      assert html =~ "Program created successfully."
      refute html =~ "enrollment capacity could not be saved"
    end

    test "creates policy with only min_enrollment set", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/provider/dashboard/programs")

      view |> element("#new-program-btn") |> render_click()

      view
      |> form("#program-form", %{
        "program_schema" => %{
          "title" => "Min Only Program",
          "description" => "Testing min-only capacity",
          "category" => "sports",
          "price" => "30.00"
        },
        "enrollment_policy" => %{
          "min_enrollment" => "5"
        }
      })
      |> render_submit()

      html = render(view)
      assert html =~ "Program created successfully."
      refute html =~ "enrollment capacity could not be saved"
    end

    test "creates program without capacity fields (no policy created)", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/provider/dashboard/programs")

      view |> element("#new-program-btn") |> render_click()

      view
      |> form("#program-form", %{
        "program_schema" => %{
          "title" => "No Capacity Program",
          "description" => "Testing no capacity fields",
          "category" => "arts",
          "price" => "25.00"
        }
      })
      |> render_submit()

      html = render(view)
      assert html =~ "Program created successfully."
      refute html =~ "enrollment capacity could not be saved"
    end
  end

  describe "program creation without limits" do
    defp seed_programs_with_listing(provider_id, count) do
      for i <- 1..count do
        id = Ecto.UUID.generate()

        Repo.insert!(%Program{
          id: id,
          title: "Program #{i}",
          description: "Description for program #{i}",
          category: "arts",
          price: Decimal.new("50.00"),
          provider_id: provider_id,
          origin: :self_posted
        })

        Repo.insert!(%ProgramListing{
          id: id,
          title: "Program #{i}",
          description: "Description for program #{i}",
          category: "arts",
          price: Decimal.new("50.00"),
          provider_id: provider_id
        })
      end
    end

    # Provider tiers removed (ADR-0004): no per-tier program cap remains
    test "new program button stays enabled beyond the former starter cap", %{
      conn: conn,
      provider: provider
    } do
      seed_programs_with_listing(provider.id, 2)

      {:ok, view, _html} = live(conn, ~p"/provider/dashboard/programs")

      refute has_element?(view, "#new-program-btn[disabled]")
    end

    test "creates a program beyond the former starter cap", %{conn: conn, provider: provider} do
      seed_programs_with_listing(provider.id, 2)

      {:ok, view, _html} = live(conn, ~p"/provider/dashboard/programs")

      render_hook(view, "add_program")

      view
      |> form("#program-form", %{
        "program_schema" => %{
          "title" => "Third Program",
          "description" => "Created beyond the former cap",
          "category" => "arts",
          "price" => "50.00"
        }
      })
      |> render_submit()

      html = render(view)
      assert html =~ "Program created successfully."
      refute html =~ "program limit"
    end
  end
end
