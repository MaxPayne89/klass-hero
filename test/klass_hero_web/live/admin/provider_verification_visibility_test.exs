defmodule KlassHeroWeb.Admin.ProviderVerificationVisibilityTest do
  @moduledoc """
  Successor to the #1210 outbox regression test: an admin verifying a provider
  must change what a parent sees on that provider's program cards.

  #1210 guarded the same guarantee through the machinery of the day — the admin
  wrote, an event was staged, and the `ProgramListings` projection copied the
  flag onto `program_listings.provider_verified`. #1195 deleted that column and
  had cards read `Provider.get_trust_states/1` per render, so the failure mode
  #1210 caught (a write that never reaches the read side) is now impossible by
  construction rather than by delivery.

  What remains worth pinning is the outcome itself, asserted where a parent would
  see it rather than on an intermediate column — which is also what makes this
  test survive the next change of plumbing.
  """
  use KlassHeroWeb.ConnCase, async: true

  import KlassHero.Factory
  import KlassHero.ProviderFixtures
  import Phoenix.LiveViewTest

  setup :register_and_log_in_admin

  defp toggle_verified(conn, provider, value) do
    {:ok, view, _html} = live(conn, ~p"/admin/providers/#{provider.id}/edit")

    view
    |> form("#resource-form", %{change: %{verified: value}})
    |> render_submit(%{"save-type" => "save"})
  end

  defp trust_mark(conn, program_id) do
    {:ok, view, _html} = live(conn, ~p"/programs")
    selector = "[data-program-id='#{program_id}'] [data-testid='provider-trust-mark']"

    if has_element?(view, selector) do
      view |> element(selector) |> render()
    end
  end

  test "verifying a provider makes the trust mark appear on its program cards", %{conn: conn} do
    provider = provider_profile_fixture(business_name: "Verify Me")
    program = insert(:program_listing_schema, provider_id: provider.id)

    refute trust_mark(conn, program.id)

    toggle_verified(conn, provider, true)

    assert trust_mark(conn, program.id) =~ ~s(data-trust-state="verified")
  end

  test "unverifying a provider removes the trust mark again", %{conn: conn} do
    provider = provider_profile_fixture(business_name: "Unverify Me", verified: true)
    program = insert(:program_listing_schema, provider_id: provider.id)

    assert trust_mark(conn, program.id) =~ ~s(data-trust-state="verified")

    toggle_verified(conn, provider, false)

    refute trust_mark(conn, program.id)
  end
end
