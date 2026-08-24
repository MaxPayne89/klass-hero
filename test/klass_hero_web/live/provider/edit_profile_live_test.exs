defmodule KlassHeroWeb.Provider.EditProfileLiveTest do
  use KlassHeroWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  setup :register_and_log_in_provider

  describe "edit profile page" do
    test "renders edit profile form", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/provider/dashboard/edit")

      assert has_element?(view, "h1", "Edit Profile")
      assert has_element?(view, "#profile-form")
      assert has_element?(view, "#save-profile-btn")
    end

    test "renders back to dashboard link", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/provider/dashboard/edit")

      assert has_element?(view, "a", "Back to Dashboard")
    end

    test "renders verification documents section", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/provider/dashboard/edit")

      assert has_element?(view, "#verification-docs")
      assert has_element?(view, "#doc-upload-form")
      assert has_element?(view, "#doc-type-select")
    end

    test "renders description textarea with current value", %{conn: conn, provider: provider} do
      {:ok, view, _html} = live(conn, ~p"/provider/dashboard/edit")

      html = render(view)
      assert html =~ provider.description
    end

    test "validates profile on change", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/provider/dashboard/edit")

      view
      |> form("#profile-form", %{provider_profile_schema: %{description: "Updated bio"}})
      |> render_change()

      # Form should still be present (no crash)
      assert has_element?(view, "#profile-form")
    end

    test "saves profile and redirects to dashboard", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/provider/dashboard/edit")

      view
      |> form("#profile-form", %{provider_profile_schema: %{description: "My new description"}})
      |> render_submit()

      assert_redirect(view, ~p"/provider/dashboard")
    end

    test "saves branding fields through the form to the database", %{conn: conn, provider: provider} do
      {:ok, view, _html} = live(conn, ~p"/provider/dashboard/edit")

      # Social rows are added on demand, so an unrevealed network has no input to
      # submit into. This provider has none filled in, hence both clicks.
      view |> element("#add-instagram_url") |> render_click()
      view |> element("#add-linkedin_url") |> render_click()

      view
      |> form("#profile-form", %{
        provider_profile_schema: %{
          description: "A description",
          tagline: "Play-based learning",
          instagram_url: "https://instagram.com/example",
          linkedin_url: "https://linkedin.com/company/example"
        }
      })
      |> render_submit()

      assert_redirect(view, ~p"/provider/dashboard")

      # Reloaded, not the submitted params — four separate allowlists sit between
      # this form and the column, and three of them drop silently (#1481).
      assert {:ok, reloaded} = KlassHero.Provider.get_provider_profile(provider.id)
      assert reloaded.tagline == "Play-based learning"
      assert reloaded.instagram_url == "https://instagram.com/example"
      assert reloaded.linkedin_url == "https://linkedin.com/company/example"
    end

    test "clearing a branding field blanks it rather than failing validation", %{
      conn: conn,
      provider: provider
    } do
      {:ok, _} =
        KlassHero.Provider.update_provider_profile(provider.id, %{tagline: "Old tagline"})

      {:ok, view, _html} = live(conn, ~p"/provider/dashboard/edit")

      view
      |> form("#profile-form", %{
        provider_profile_schema: %{description: "A description", tagline: ""}
      })
      |> render_submit()

      assert_redirect(view, ~p"/provider/dashboard")

      assert {:ok, reloaded} = KlassHero.Provider.get_provider_profile(provider.id)
      assert is_nil(reloaded.tagline)
    end

    test "rejects a social link that is not https", %{conn: conn, provider: provider} do
      {:ok, view, _html} = live(conn, ~p"/provider/dashboard/edit")

      view |> element("#add-instagram_url") |> render_click()

      view
      |> form("#profile-form", %{
        provider_profile_schema: %{
          description: "A description",
          instagram_url: "http://insecure.example.com"
        }
      })
      |> render_submit()

      assert {:ok, reloaded} = KlassHero.Provider.get_provider_profile(provider.id)
      assert is_nil(reloaded.instagram_url)
    end

    test "displays existing verification documents", %{conn: conn, provider: provider} do
      # Create a verification document for this provider
      KlassHero.Factory.insert(:verification_document_schema,
        provider_profile_id: provider.id,
        document_type: :business_registration,
        original_filename: "my_registration.pdf"
      )

      {:ok, view, _html} = live(conn, ~p"/provider/dashboard/edit")

      assert has_element?(view, "#verification-docs")
      html = render(view)
      assert html =~ "my_registration.pdf"
    end

    test "renders document type selector with all valid types", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/provider/dashboard/edit")

      html = render(view)
      assert html =~ "Business Registration"
      assert html =~ "Insurance Certificate"
      assert html =~ "ID Document"
      assert html =~ "Tax Certificate"
    end

    test "renders upload doc button disabled when no file selected", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/provider/dashboard/edit")

      assert has_element?(view, "#upload-doc-btn[disabled]")
    end
  end

  describe "select_doc_type event" do
    test "changes selected document type", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/provider/dashboard/edit")

      view
      |> element("#doc-type-select")
      |> render_change(%{"doc_type" => "insurance_certificate"})

      # Form should still be present (no crash) and selection reflected
      assert has_element?(view, "#doc-type-select")
      assert has_element?(view, "#profile-form")
    end
  end

  describe "save_profile error handling" do
    test "shows error when description exceeds max length", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/provider/dashboard/edit")

      long_desc = String.duplicate("a", 1001)

      view
      |> form("#profile-form", %{provider_profile_schema: %{description: long_desc}})
      |> render_submit()

      # Should stay on edit page with validation error
      assert has_element?(view, "#profile-form")
      assert render(view) =~ "Please fix the errors"
    end

    test "redirects to home when provider deleted between mount and save", %{
      conn: conn,
      provider: provider
    } do
      {:ok, view, _html} = live(conn, ~p"/provider/dashboard/edit")

      # Simulate race: delete provider after mount
      KlassHero.Repo.delete!(provider)

      view
      |> form("#profile-form", %{provider_profile_schema: %{description: "Updated"}})
      |> render_submit()

      flash = assert_redirect(view, ~p"/")
      assert flash["error"] =~ "not found"
    end
  end

  describe "logo upload" do
    test "submitting profile with logo file succeeds and redirects", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/provider/dashboard/edit")

      logo =
        file_input(view, "#profile-form", :logo, [
          %{
            name: "test_logo.png",
            content: <<137, 80, 78, 71, 13, 10, 26, 10>>,
            type: "image/png"
          }
        ])

      render_upload(logo, "test_logo.png")

      view
      |> form("#profile-form", %{provider_profile_schema: %{description: "With logo"}})
      |> render_submit()

      # Trigger: upload succeeded via StubStorageAdapter
      # Why: previously this crashed the LiveView process; now it should complete
      # Outcome: redirects to dashboard on success
      assert_redirect(view, ~p"/provider/dashboard")
    end

    test "every file input on the page stays reachable by keyboard", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/provider/dashboard/edit")

      # `hidden` is `display: none`, which drops the input out of the tab order
      # while the <label> is not focusable either — that combination left every
      # upload on this page unopenable without a mouse.
      #
      # Asserted per-element rather than over the whole page: a substring check
      # passes as soon as ONE input is correct, which is how the first version of
      # this test survived reverting the component to `hidden`.
      tags = Regex.scan(~r/<input[^>]*type="file"[^>]*>/, html) |> List.flatten()

      assert length(tags) == 3

      for tag <- tags do
        classes =
          case Regex.run(~r/class="([^"]*)"/, tag) do
            [_, c] -> String.split(c)
            nil -> []
          end

        refute "hidden" in classes, "a file input is display:none: #{tag}"
        assert "sr-only" in classes, "a file input is not keyboard-reachable: #{tag}"
      end
    end
  end

  describe "navigation" do
    test "navigating from dashboard to edit via link", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/provider/dashboard")

      view |> element("a", "Edit Profile") |> render_click()

      assert_redirect(view, ~p"/provider/dashboard/edit")
    end
  end
end
