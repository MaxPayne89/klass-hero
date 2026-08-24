defmodule KlassHeroWeb.Provider.ProfileCompletionLiveTest do
  use KlassHeroWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  describe "draft provider profile completion" do
    setup :register_and_log_in_draft_provider

    test "renders completion form with expected fields", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/provider/complete-profile")

      assert has_element?(view, "#profile-completion-form")
      assert has_element?(view, ~s(input[name="provider_profile_schema[business_name]"]))
      assert has_element?(view, ~s(textarea[name="provider_profile_schema[description]"]))
    end

    test "renders the shared branding section", %{conn: conn} do
      # This form had no branding coverage at all, which is how it kept a
      # hand-rolled copy of the dropzone and a raw-grey palette while its sibling
      # moved on.
      {:ok, view, _html} = live(conn, ~p"/provider/complete-profile")

      assert has_element?(view, "#social-links")
      assert has_element?(view, ~s(input[name="provider_profile_schema[tagline]"]))
      assert has_element?(view, "#add-instagram_url")
      assert has_element?(view, "#logo-upload")
    end

    test "has no cover upload — that field belongs to the edit form", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/provider/complete-profile")

      refute has_element?(view, "#cover-upload")
    end

    test "saves branding fields, prepending https:// to a scheme-less link", %{
      conn: conn,
      provider: provider
    } do
      {:ok, view, _html} = live(conn, ~p"/provider/complete-profile")

      view |> element("#add-instagram_url") |> render_click()

      view
      |> form("#profile-completion-form", %{
        provider_profile_schema: %{
          business_name: "Starlight Coaching",
          description: "Sports for kids",
          tagline: "Move. Play. Grow.",
          instagram_url: "instagram.com/starlight"
        }
      })
      |> render_submit()

      assert {:ok, reloaded} = KlassHero.Provider.get_provider_profile(provider.id)
      assert reloaded.tagline == "Move. Play. Grow."
      assert reloaded.instagram_url == "https://instagram.com/starlight"
    end

    test "pre-fills description from staff member bio", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/provider/complete-profile")

      assert has_element?(
               view,
               ~s(textarea[name="provider_profile_schema[description]"])
             )

      # Verify the description field contains the staff member's bio
      html = render(view)
      assert html =~ "Experienced youth sports coach"
    end

    test "validates on change and shows errors", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/provider/complete-profile")

      view
      |> form("#profile-completion-form", %{
        provider_profile_schema: %{business_name: "", description: ""}
      })
      |> render_change()

      assert has_element?(view, "#profile-completion-form")
    end

    test "submits successfully and redirects to dashboard", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/provider/complete-profile")

      view
      |> form("#profile-completion-form", %{
        provider_profile_schema: %{
          business_name: "Youth Sports Academy",
          description: "Premier youth sports training",
          phone: "+1234567890"
        }
      })
      |> render_submit()

      assert_redirect(view, ~p"/provider/dashboard")
    end

    test "shows validation errors for empty required fields", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/provider/complete-profile")

      view
      |> form("#profile-completion-form", %{
        provider_profile_schema: %{business_name: "", description: ""}
      })
      |> render_submit()

      assert has_element?(view, "#profile-completion-form")
      assert has_element?(view, ~s([phx-feedback-for="provider_profile_schema[business_name]"]))
    end
  end

  describe "active provider visiting completion page" do
    setup :register_and_log_in_provider

    test "redirects to dashboard with info flash", %{conn: conn} do
      {:error, {:redirect, %{to: path, flash: flash}}} =
        live(conn, ~p"/provider/complete-profile")

      assert path == ~p"/provider/dashboard"
      assert flash["info"] =~ "already"
    end
  end
end
