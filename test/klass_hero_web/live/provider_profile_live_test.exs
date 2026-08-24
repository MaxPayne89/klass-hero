defmodule KlassHeroWeb.ProviderProfileLiveTest do
  use KlassHeroWeb.ConnCase, async: true

  import KlassHero.Factory
  import KlassHero.ProviderFixtures
  import Phoenix.LiveViewTest

  defp active_provider(attrs \\ []) do
    provider_profile_fixture(Keyword.merge([business_name: "Starlight Coaching"], attrs))
  end

  describe "identity" do
    test "renders the full hero variant", %{conn: conn} do
      provider = active_provider(tagline: "Move. Play. Grow.")

      {:ok, view, _html} = live(conn, ~p"/providers/#{provider.id}")

      assert has_element?(view, "#provider-hero[data-variant='full']")
      assert has_element?(view, "#provider-hero h1", "Starlight Coaching")
      assert render(view) =~ "Move. Play. Grow."
    end

    test "renders on the static mount, before the socket connects", %{conn: conn} do
      # The SEO criterion. A live/2 assertion alone passes on a page that renders
      # nothing on the first byte and fills in only after connecting.
      provider = active_provider()

      html = conn |> get(~p"/providers/#{provider.id}") |> html_response(200)

      assert html =~ "Starlight Coaching"
    end

    test "sets the page title from the business name", %{conn: conn} do
      provider = active_provider()

      {:ok, _view, html} = live(conn, ~p"/providers/#{provider.id}")

      assert html =~ "Starlight Coaching"
    end
  end

  describe "fails closed" do
    test "redirects for draft, unknown and malformed ids", %{conn: conn} do
      draft = provider_profile_fixture(profile_status: :draft)

      for id <- [draft.id, Ecto.UUID.generate(), "not-a-uuid"] do
        assert {:error, {:redirect, %{to: "/programs", flash: %{"error" => message}}}} =
                 live(conn, ~p"/providers/#{id}")

        assert message =~ "not"
      end
    end

    test "a malformed id is a redirect, not a 500", %{conn: conn} do
      assert conn |> get(~p"/providers/not-a-uuid") |> redirected_to() == "/programs"
    end
  end

  describe "about" do
    test "renders description and the contact facts that are filled in", %{conn: conn} do
      provider =
        active_provider(
          description: "Empowering kids through play-based learning.",
          address: "123 Main St, Berlin",
          phone: "+49 30 123456",
          website: "https://starlight.example"
        )

      html = render(elem_view(conn, provider))

      assert html =~ "Empowering kids through play-based learning."
      assert html =~ "123 Main St, Berlin"
      assert html =~ "+49 30 123456"
      assert html =~ "https://starlight.example"
    end

    test "omits the about section entirely when nothing is filled in", %{conn: conn} do
      provider = active_provider(description: nil, address: nil, phone: nil, website: nil)

      {:ok, view, _html} = live(conn, ~p"/providers/#{provider.id}")

      refute has_element?(view, "#provider-about")
      assert has_element?(view, "#provider-hero")
    end
  end

  describe "programs" do
    test "lists current programs and excludes ended ones", %{conn: conn} do
      provider = active_provider()
      insert(:program_listing_schema, provider_id: provider.id, title: "Youth Fitness")

      insert(:program_listing_schema,
        provider_id: provider.id,
        title: "Finished Camp",
        end_date: Date.add(Date.utc_today(), -1)
      )

      html = render(elem_view(conn, provider))

      assert html =~ "Youth Fitness"
      refute html =~ "Finished Camp"
    end

    test "shows an empty state rather than a blank section", %{conn: conn} do
      provider = active_provider()

      {:ok, view, _html} = live(conn, ~p"/providers/#{provider.id}")

      assert has_element?(view, "[data-testid='empty-state']")
    end

    test "navigates to a program", %{conn: conn} do
      provider = active_provider()
      program = insert(:program_listing_schema, provider_id: provider.id)

      {:ok, view, _html} = live(conn, ~p"/providers/#{provider.id}")

      view
      |> element("[data-program-id='#{program.id}']")
      |> render_click()

      assert_redirect(view, ~p"/programs/#{program.id}")
    end
  end

  describe "message CTA" do
    test "points at compose for this provider", %{conn: conn} do
      provider = active_provider()

      {:ok, view, _html} = live(conn, ~p"/providers/#{provider.id}")

      assert has_element?(
               view,
               ~s(#provider-message-cta[href="/messages/new?provider_id=#{provider.id}"])
             )
    end

    test "is shown to an anonymous visitor, who is asked to log in on arrival", %{conn: conn} do
      # Hiding the CTA would strip the page's only conversion action from
      # logged-out traffic. Following it is a dead end only if the destination
      # refuses without explanation, so assert the destination's own behaviour.
      provider = active_provider()

      {:ok, view, _html} = live(conn, ~p"/providers/#{provider.id}")
      assert has_element?(view, "#provider-message-cta")

      assert {:error, {:redirect, %{to: "/users/log-in", flash: %{"error" => message}}}} =
               live(conn, ~p"/messages/new?provider_id=#{provider.id}")

      assert message =~ "log in"
    end
  end

  defp elem_view(conn, provider) do
    {:ok, view, _html} = live(conn, ~p"/providers/#{provider.id}")
    view
  end
end
