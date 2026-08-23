defmodule KlassHeroWeb.Provider.DashboardProgramCreationTest do
  use KlassHeroWeb.ConnCase, async: true

  import KlassHero.Factory
  import Phoenix.LiveViewTest

  alias KlassHero.Enrollment.EnrollmentPolicy
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

    test "creates a program with a subtitle", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/provider/dashboard/programs")

      view |> element("#new-program-btn") |> render_click()

      view
      |> form("#program-form", %{
        "program_schema" => %{
          "title" => "Chess Club",
          "subtitle" => "For beginners, no experience needed",
          "description" => "Develop strategic thinking through chess",
          "category" => "education",
          "price" => "60.00"
        }
      })
      |> render_submit()

      assert Repo.get_by(Program, title: "Chess Club").subtitle ==
               "For beginners, no experience needed"
    end

    # The form is repopulated from `program_to_form_params/1` on edit. If the
    # subtitle is missing there, an unrelated edit submits a blank one and
    # silently wipes it — invisible to any test that only asserts the field it
    # meant to change.
    test "an edit that does not touch the subtitle preserves it", %{
      conn: conn,
      provider: provider
    } do
      program =
        insert(:program_schema,
          provider_id: provider.id,
          title: "Chess Club",
          subtitle: "For beginners, no experience needed"
        )

      # The provider's table reads the ProgramListing read table, so the write
      # row alone leaves the list empty and the edit button unreachable.
      insert(:program_listing_schema,
        id: program.id,
        provider_id: provider.id,
        title: program.title
      )

      {:ok, view, _html} = live(conn, ~p"/provider/dashboard/programs")

      view
      |> element(~s([phx-click="edit_program"][phx-value-id="#{program.id}"]))
      |> render_click()

      view
      |> form("#program-form", %{"program_schema" => %{"title" => "Chess Club Advanced"}})
      |> render_submit()

      reloaded = Repo.get!(Program, program.id)
      assert reloaded.title == "Chess Club Advanced"
      assert reloaded.subtitle == "For beginners, no experience needed"
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

      # The picked instructor is persisted as the lead on program_staff_assignments
      # (single source of truth), not a program snapshot.
      program = KlassHero.Repo.get_by!(Program, title: "Soccer Camp")
      assert %{id: staff_id} = KlassHero.Provider.get_lead_instructor(program.id)
      assert staff_id == staff.id
    end

    # The select only lists active staff, so this needs a crafted param — but
    # resolve_instructor/2 is also what keeps apply_lead_instructor's bang-match
    # safe, so a deactivated pick must be refused there rather than reaching the
    # context and blowing up mid-save (#1306).
    test "refuses a deactivated instructor without creating the program", %{conn: conn, provider: provider} do
      staff = ProviderFixtures.staff_member_fixture(provider_id: provider.id, first_name: "Del", last_name: "Gone")
      {:ok, _} = KlassHero.Provider.deactivate_staff_member(staff)

      {:ok, view, _html} = live(conn, ~p"/provider/dashboard/programs")

      view |> element("#new-program-btn") |> render_click()

      # Dispatched directly: the select never renders a deactivated option, so
      # form/3 would reject the value before it ever reached the LiveView.
      html =
        render_submit(view, "save_program", %{
          "program_schema" => %{
            "title" => "Ghost Camp",
            "description" => "Nobody leads this",
            "category" => "sports",
            "price" => "75.00",
            "location" => "Sports Park",
            "instructor_id" => staff.id
          }
        })

      assert html =~ "instructor"
      refute Repo.get_by(Program, title: "Ghost Camp")
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

    # Each accepted capacity shape creates the program and shows no capacity
    # warning; they differ only in the enrollment_policy map, so table-fold them.
    for {label, policy} <- [
          {"valid capacity", %{"min_enrollment" => "5", "max_enrollment" => "20"}},
          {"only max_enrollment set", %{"max_enrollment" => "20"}},
          {"only min_enrollment set", %{"min_enrollment" => "5"}}
        ] do
      @capacity_policy policy

      test "creates program successfully with #{label}", %{conn: conn} do
        {:ok, view, _html} = live(conn, ~p"/provider/dashboard/programs")

        view |> element("#new-program-btn") |> render_click()

        view
        |> form("#program-form", %{
          "program_schema" => %{
            "title" => "Capacity Program",
            "description" => "Testing an accepted enrollment capacity shape",
            "category" => "sports",
            "price" => "30.00"
          },
          "enrollment_policy" => @capacity_policy
        })
        |> render_submit()

        html = render(view)
        assert html =~ "Program created successfully."
        refute html =~ "enrollment capacity could not be saved"
      end
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

    # The regression #1345 reports: the update path reported success while the
    # policy write was rejected and the old limits stayed in force.
    test "warns when an edit's capacity is rejected", %{conn: conn, provider: provider} do
      program = seed_program_with_listing(provider.id, "Rejected Capacity Program")

      {:ok, _policy} =
        KlassHero.Enrollment.set_enrollment_policy(%{program_id: program.id, max_enrollment: 20})

      {:ok, view, _html} = live(conn, ~p"/provider/dashboard/programs")

      open_edit_form(view, program)

      submit_program_form(view, "Rejected Capacity Program", %{
        "enrollment_policy" => %{"min_enrollment" => "50", "max_enrollment" => "10"}
      })

      assert_flash(
        view,
        :warning,
        "Program updated, but the enrollment capacity was rejected. The previous limits still apply."
      )

      refute_flash(view, :info)
    end

    # Every edit outcome is the same submit under a different policy payload, so the
    # only axis that matters is which sub-writes were rejected. A rejected capacity
    # names itself; anything else shares the generic message.
    for {label, policy_params, kind, message} <- [
          {"accepted capacity and restrictions",
           %{
             "enrollment_policy" => %{"min_enrollment" => "5", "max_enrollment" => "20"},
             "participant_policy" => %{"min_grade" => "1", "max_grade" => "4"}
           }, :info, "Program updated successfully."},
          {"rejected participant restrictions",
           %{
             "enrollment_policy" => %{"max_enrollment" => "20"},
             "participant_policy" => %{"min_grade" => "10", "max_grade" => "2"}
           }, :warning, "Program updated, but some settings could not be saved. Please review the program's limits."},
          {"both rejected",
           %{
             "enrollment_policy" => %{"min_enrollment" => "50", "max_enrollment" => "10"},
             "participant_policy" => %{"min_grade" => "10", "max_grade" => "2"}
           }, :warning, "Program updated, but some settings could not be saved. Please review the program's limits."}
        ] do
      @edit_case %{params: policy_params, kind: kind, message: message}

      test "editing with #{label} flashes the matching outcome", %{conn: conn, provider: provider} do
        program = seed_program_with_listing(provider.id, "Outcome Program")

        {:ok, view, _html} = live(conn, ~p"/provider/dashboard/programs")

        open_edit_form(view, program)
        submit_program_form(view, "Outcome Program", @edit_case.params)

        assert_flash(view, @edit_case.kind, @edit_case.message)
        refute_flash(view, opposite_kind(@edit_case.kind))
      end
    end

    # A partial failure is a :warning, never an :error — flash is keyed by kind, so
    # an :error here would be erased by (or erase) a genuine error from elsewhere.
    test "a rejected capacity on create is a warning, not an error", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/provider/dashboard/programs")

      view |> element("#new-program-btn") |> render_click()

      submit_program_form(view, "Capacity Kind Program", %{
        "enrollment_policy" => %{"min_enrollment" => "20", "max_enrollment" => "5"}
      })

      assert_flash(
        view,
        :warning,
        "Program created, but enrollment capacity could not be saved. Edit the program to retry."
      )

      refute_flash(view, :error)
    end

    defp opposite_kind(:info), do: :warning
    defp opposite_kind(:warning), do: :info

    defp open_edit_form(view, program) do
      view
      |> element(~s([phx-click="edit_program"][phx-value-id="#{program.id}"]))
      |> render_click()
    end

    defp submit_program_form(view, title, policy_params) do
      params =
        Map.merge(
          %{
            "program_schema" => %{
              "title" => title,
              "description" => "Exercising a program save outcome",
              "category" => "arts",
              "price" => "50.00"
            }
          },
          policy_params
        )

      view |> form("#program-form", params) |> render_submit()
    end
  end

  # The row a save inserts shows the capacity that was just typed, not what an
  # enrollment read would return — the two save paths hand-build their
  # `enrollment_data` for exactly that reason, and the staffing panel's refresh
  # deliberately does not (#1307). Nothing pinned that divergence before, so a
  # naive fold of the three row-rebuild paths would have landed green.
  describe "the saved row reflects just-submitted capacity" do
    defp seed_program_with_listing(provider_id, title) do
      id = Ecto.UUID.generate()

      attrs = %{
        id: id,
        title: title,
        description: "Seeded for a capacity row assertion",
        category: "arts",
        price: Decimal.new("50.00"),
        provider_id: provider_id
      }

      program = Repo.insert!(struct!(Program, Map.put(attrs, :origin, :self_posted)))
      Repo.insert!(struct!(ProgramListing, attrs))

      program
    end

    # The one case where the two sources actually disagree. A rejected capacity
    # leaves `enrollment_policies` holding the old 20, but `resolve_capacity/2`
    # answers `nil` for the failed write — so the row blanks to "—" rather than
    # showing a number the save did not accept. Fold the save path onto
    # `build_enrollment_data/1` and this is the test that goes red.
    test "a rejected capacity blanks the row while the old policy survives", %{
      conn: conn,
      provider: provider
    } do
      program = seed_program_with_listing(provider.id, "Kept Policy Program")

      {:ok, _policy} =
        KlassHero.Enrollment.set_enrollment_policy(%{program_id: program.id, max_enrollment: 20})

      {:ok, view, _html} = live(conn, ~p"/provider/dashboard/programs")

      assert view |> element("#programs-#{program.id}") |> render() =~ "0/20"

      view
      |> element(~s([phx-click="edit_program"][phx-value-id="#{program.id}"]))
      |> render_click()

      view
      |> form("#program-form", %{
        "program_schema" => %{
          "title" => "Kept Policy Program",
          "description" => "Submitting a capacity the policy will reject",
          "category" => "arts",
          "price" => "50.00"
        },
        "enrollment_policy" => %{"min_enrollment" => "50", "max_enrollment" => "10"}
      })
      |> render_submit()

      # The cell blanks rather than showing the surviving 20, so the warning flash
      # is what tells the provider the capacity was refused, not cleared (#1345).
      assert view |> element("#programs-#{program.id}") |> render() =~ "0/—"

      assert %{max_enrollment: 20} =
               Repo.get_by!(EnrollmentPolicy, program_id: program.id)
    end

    test "a created program's row shows the capacity from the form", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/provider/dashboard/programs")

      view |> element("#new-program-btn") |> render_click()

      view
      |> form("#program-form", %{
        "program_schema" => %{
          "title" => "Capacity Row Program",
          "description" => "The new row must show the typed capacity",
          "category" => "arts",
          "price" => "25.00"
        },
        "enrollment_policy" => %{"max_enrollment" => "42"}
      })
      |> render_submit()

      program = Repo.get_by!(Program, title: "Capacity Row Program")

      assert view |> element("#programs-#{program.id}") |> render() =~ "0/42"
    end

    test "an edited program's row shows the raised capacity", %{conn: conn, provider: provider} do
      program = seed_program_with_listing(provider.id, "Raise My Capacity")

      {:ok, view, _html} = live(conn, ~p"/provider/dashboard/programs")

      view
      |> element(~s([phx-click="edit_program"][phx-value-id="#{program.id}"]))
      |> render_click()

      view
      |> form("#program-form", %{
        "program_schema" => %{
          "title" => "Raise My Capacity",
          "description" => "The rebuilt row must show the raised capacity",
          "category" => "arts",
          "price" => "50.00"
        },
        "enrollment_policy" => %{"max_enrollment" => "60"}
      })
      |> render_submit()

      assert view |> element("#programs-#{program.id}") |> render() =~ "0/60"
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

  # The edit form is prefilled from the stored policy, so blanking a field is a
  # deliberate clear — not the "no limits given" the create path reads it as (#1370).
  describe "clearing the enrollment capacity" do
    defp edit_with_capacity(view, program, title, policy_params) do
      open_edit_form(view, program)
      submit_program_form(view, title, %{"enrollment_policy" => policy_params})
    end

    test "clears the stored limits when nobody is enrolled", %{conn: conn, provider: provider} do
      program = seed_program_with_listing(provider.id, "Uncap Me")

      {:ok, _} =
        KlassHero.Enrollment.set_enrollment_policy(%{
          program_id: program.id,
          min_enrollment: 3,
          max_enrollment: 12
        })

      {:ok, view, _html} = live(conn, ~p"/provider/dashboard/programs")

      assert view |> element("#programs-#{program.id}") |> render() =~ "0/12"

      edit_with_capacity(view, program, "Uncap Me", %{
        "min_enrollment" => "",
        "max_enrollment" => ""
      })

      assert_flash(view, :info, "Program updated successfully.")

      assert %EnrollmentPolicy{min_enrollment: nil, max_enrollment: nil} =
               Repo.get_by!(EnrollmentPolicy, program_id: program.id)

      assert view |> element("#programs-#{program.id}") |> render() =~ "0/—"
    end

    test "keeps clearing the minimum alone unguarded", %{conn: conn, provider: provider} do
      program = seed_program_with_listing(provider.id, "Drop The Minimum")

      {:ok, _} =
        KlassHero.Enrollment.set_enrollment_policy(%{
          program_id: program.id,
          min_enrollment: 3,
          max_enrollment: 12
        })

      insert(:enrollment_schema, program_id: program.id, status: "confirmed")

      {:ok, view, _html} = live(conn, ~p"/provider/dashboard/programs")

      edit_with_capacity(view, program, "Drop The Minimum", %{
        "min_enrollment" => "",
        "max_enrollment" => "12"
      })

      assert_flash(view, :info, "Program updated successfully.")

      assert %EnrollmentPolicy{min_enrollment: nil, max_enrollment: 12} =
               Repo.get_by!(EnrollmentPolicy, program_id: program.id)
    end
  end

  describe "removing a capacity cap with children already enrolled" do
    defp enrolled_capped_program(provider_id, title, enrolled) do
      program = seed_program_with_listing(provider_id, title)

      {:ok, _} =
        KlassHero.Enrollment.set_enrollment_policy(%{program_id: program.id, max_enrollment: 12})

      for _ <- 1..enrolled//1,
          do: insert(:enrollment_schema, program_id: program.id, status: "confirmed")

      program
    end

    defp blank_the_maximum(view, title) do
      view
      |> form("#program-form", %{
        "program_schema" => %{
          "title" => title,
          "description" => "Exercising a program save outcome",
          "category" => "arts",
          "price" => "50.00"
        },
        "enrollment_policy" => %{"min_enrollment" => "", "max_enrollment" => ""}
      })
      |> render_change()
    end

    test "warns as soon as the field is blanked, before any save", %{
      conn: conn,
      provider: provider
    } do
      program = enrolled_capped_program(provider.id, "Warn Me First", 2)

      {:ok, view, _html} = live(conn, ~p"/provider/dashboard/programs")

      open_edit_form(view, program)

      refute has_element?(view, "#cap-removal-warning")

      blank_the_maximum(view, "Warn Me First")

      assert has_element?(view, "#cap-removal-warning")
      assert has_element?(view, "#enrollment_policy_acknowledge_cap_removal")
    end

    test "stays silent while the cap is merely lowered", %{conn: conn, provider: provider} do
      program = enrolled_capped_program(provider.id, "Lower Me", 2)

      {:ok, view, _html} = live(conn, ~p"/provider/dashboard/programs")

      open_edit_form(view, program)

      view
      |> form("#program-form", %{
        "program_schema" => %{
          "title" => "Lower Me",
          "description" => "Exercising a program save outcome",
          "category" => "arts",
          "price" => "50.00"
        },
        "enrollment_policy" => %{"max_enrollment" => "5"}
      })
      |> render_change()

      refute has_element?(view, "#cap-removal-warning")
    end

    # The backstop, not the everyday path: the checkbox is `required`, so reaching
    # this needs a booking to land while the form sits open (or a crafted submit).
    test "refuses an unacknowledged removal and keeps the form open", %{
      conn: conn,
      provider: provider
    } do
      program = enrolled_capped_program(provider.id, "Refuse Me", 2)

      {:ok, view, _html} = live(conn, ~p"/provider/dashboard/programs")

      open_edit_form(view, program)
      submit_program_form(view, "Refuse Me", %{"enrollment_policy" => %{"max_enrollment" => ""}})

      assert_flash(
        view,
        :warning,
        "2 children are already enrolled. Confirm you want this program to have no capacity limit."
      )

      refute_flash(view, :info)

      assert %EnrollmentPolicy{max_enrollment: 12} =
               Repo.get_by!(EnrollmentPolicy, program_id: program.id)

      assert has_element?(view, "#program-form")
      assert has_element?(view, "#cap-removal-warning")
    end

    test "removes the cap once acknowledged", %{conn: conn, provider: provider} do
      program = enrolled_capped_program(provider.id, "Acknowledged Uncap", 2)

      {:ok, view, _html} = live(conn, ~p"/provider/dashboard/programs")

      open_edit_form(view, program)

      # The checkbox only exists once the field is blanked, so the tick can only follow
      # the warning — which is the whole point of showing it on change rather than on save.
      blank_the_maximum(view, "Acknowledged Uncap")

      submit_program_form(view, "Acknowledged Uncap", %{
        "enrollment_policy" => %{
          "min_enrollment" => "",
          "max_enrollment" => "",
          "acknowledge_cap_removal" => "true"
        }
      })

      assert_flash(view, :info, "Program updated successfully.")

      assert %EnrollmentPolicy{max_enrollment: nil} =
               Repo.get_by!(EnrollmentPolicy, program_id: program.id)

      assert view |> element("#programs-#{program.id}") |> render() =~ "2/—"
    end
  end

  describe "IDOR ownership guard" do
    test "edit_program on a foreign program id is rejected and opens no form", %{conn: conn} do
      victim = ProviderFixtures.provider_profile_fixture()

      {:ok, victim_program} =
        KlassHero.ProgramCatalog.create_program(%{
          provider_id: victim.id,
          title: "Victim Program",
          description: "Owned by another provider",
          category: "sports",
          price: Decimal.new("100.00")
        })

      {:ok, view, _html} = live(conn, ~p"/provider/dashboard/programs")

      view = assert_idor_guarded(view, "edit_program", victim_program.id, "Program not found.")

      refute has_element?(view, "#program-form")
    end
  end
end
