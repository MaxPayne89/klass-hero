defmodule KlassHeroWeb.ProgramCardTrustMarkTest do
  @moduledoc """
  The provider trust mark on both program cards, across all three states (#1195, #1224).

  Two cards, two densities, one mark. `/programs` and the parent dashboard render
  `<.program_card>`, whose provider row carries an avatar, the name and a location.
  The home page renders `mk_program_card`, a sparser marketing card that shows the
  name and mark as plain text under the title and nothing else — the compact
  variant, with the shorter in-progress label that keeps it on one line at 375px.
  """
  use KlassHeroWeb.ConnCase, async: true

  import KlassHero.Factory
  import KlassHero.ProviderFixtures
  import Phoenix.LiveViewTest

  alias KlassHero.Provider.VettingCase
  alias KlassHero.Repo

  defp card_html(conn, path, program_id) do
    {:ok, view, _html} = live(conn, path)
    selector = "[data-program-id='#{program_id}']"

    if has_element?(view, selector), do: view |> element(selector) |> render()
  end

  defp provider_with(trust) do
    provider = provider_profile_fixture(business_name: "Acme Activities", verified: trust == :verified)

    if trust == :in_progress do
      case_ = vetting_case_fixture(provider_id: provider.id)

      VettingCase
      |> Repo.get!(case_.id)
      |> Ecto.Changeset.change(lifecycle: :in_progress)
      |> Repo.update!()
    end

    provider
  end

  describe "programs listing" do
    for {trust, expected} <- [verified: "verified", in_progress: "in_progress"] do
      test "renders the #{trust} trust mark", %{conn: conn} do
        provider = provider_with(unquote(trust))
        program = insert(:program_listing_schema, provider_id: provider.id)

        html = card_html(conn, ~p"/programs", program.id)

        assert html =~ ~s(data-testid="provider-trust-mark")
        assert html =~ ~s(data-trust-state="#{unquote(expected)}")
      end
    end

    test "renders the provider name but no trust mark when unverified", %{conn: conn} do
      provider = provider_with(:unverified)
      program = insert(:program_listing_schema, provider_id: provider.id)

      html = card_html(conn, ~p"/programs", program.id)

      assert html =~ "Acme Activities"
      refute html =~ ~s(data-testid="provider-trust-mark")
    end

    test "hides the provider row entirely when the provider no longer exists", %{conn: conn} do
      program = insert(:program_listing_schema, provider_id: Ecto.UUID.generate())

      html = card_html(conn, ~p"/programs", program.id)

      refute html =~ ~s(data-testid="provider-trust-mark")
    end
  end

  describe "home page featured cards" do
    for {trust, expected} <- [verified: "verified", in_progress: "in_progress"] do
      test "renders the #{trust} trust mark beside the provider name", %{conn: conn} do
        provider = provider_with(unquote(trust))
        program = insert(:program_listing_schema, provider_id: provider.id)

        html = card_html(conn, ~p"/", program.id)

        assert html =~ ~s(data-testid="provider-trust-mark")
        assert html =~ ~s(data-trust-state="#{unquote(expected)}")
        assert html =~ "Acme Activities"
      end
    end

    test "uses the short in-progress label, not the listing page's long one", %{conn: conn} do
      provider = provider_with(:in_progress)
      program = insert(:program_listing_schema, provider_id: provider.id)

      html = card_html(conn, ~p"/", program.id)

      assert html =~ "Verifying"
      refute html =~ "Verification in progress"
    end

    test "renders the provider name but no trust mark when unverified", %{conn: conn} do
      provider = provider_with(:unverified)
      program = insert(:program_listing_schema, provider_id: provider.id)

      html = card_html(conn, ~p"/", program.id)

      assert html =~ "Acme Activities"
      refute html =~ ~s(data-testid="provider-trust-mark")
    end

    test "omits the provider entirely when the provider no longer exists", %{conn: conn} do
      program = insert(:program_listing_schema, provider_id: Ecto.UUID.generate())

      html = card_html(conn, ~p"/", program.id)

      refute html =~ ~s(data-testid="provider-trust-mark")
    end
  end
end
