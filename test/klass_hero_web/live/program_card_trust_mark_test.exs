defmodule KlassHeroWeb.ProgramCardTrustMarkTest do
  @moduledoc """
  The provider row on a program card, across all three trust states (#1195).

  Scoped to `/programs`: the home page renders `mk_program_card`, a marketing
  card with no provider row, so verification does not surface there yet.
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
end
