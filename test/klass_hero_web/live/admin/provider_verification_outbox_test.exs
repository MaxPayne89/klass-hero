defmodule KlassHeroWeb.Admin.ProviderVerificationOutboxTest do
  @moduledoc """
  Regression coverage for #1210: verifying a provider from the Backpex admin
  must reach the ProgramListings projection, so the provider's programs become
  visible.

  Before the fix this LiveView built the event itself and published it to
  `integration:provider:provider_verified` — a topic nothing has subscribed to
  since #1207 moved projections to job-invoked delivery. The provider row
  changed and the listings never heard.

  `async: false`: the outbox adapter is swapped for the real one, which every
  other test reads. Under Oban's `:inline` testing mode the delivery job runs
  at insert, so the assertion can be the projection itself rather than a job
  row — which is the thing a user would notice.
  """
  use KlassHeroWeb.ConnCase, async: false

  import KlassHero.Factory
  import KlassHero.ProviderFixtures
  import Phoenix.LiveViewTest

  alias KlassHero.ProgramCatalog.ProgramListing
  alias KlassHero.Repo
  alias KlassHero.Shared.Adapters.Driven.Events.ObanOutbox

  setup :register_and_log_in_admin

  # Scoped to the interaction, not the whole test: under the real adapter Oban
  # delivers at insert, so a fixture's own `user_registered` would be delivered
  # and create the provider profile the fixture is about to insert itself.
  defp toggle_verified(conn, provider, value) do
    original = Application.get_env(:klass_hero, :outbox)
    Application.put_env(:klass_hero, :outbox, module: ObanOutbox)

    try do
      {:ok, view, _html} = live(conn, ~p"/admin/providers/#{provider.id}/edit")

      view
      |> form("#resource-form", %{change: %{verified: value}})
      |> render_submit(%{"save-type" => "save"})
    after
      Application.put_env(:klass_hero, :outbox, original)
    end
  end

  defp listing_verified?(listing_id) do
    Repo.get!(ProgramListing, listing_id).provider_verified
  end

  test "verifying a provider marks its listings verified", %{conn: conn} do
    provider = provider_profile_fixture(business_name: "Verify Me")
    listing = insert(:program_listing_schema, provider_id: provider.id, provider_verified: false)

    toggle_verified(conn, provider, true)

    assert listing_verified?(listing.id)
  end

  test "unverifying a provider marks its listings unverified", %{conn: conn} do
    provider = provider_profile_fixture(business_name: "Unverify Me", verified: true)
    listing = insert(:program_listing_schema, provider_id: provider.id, provider_verified: true)

    toggle_verified(conn, provider, false)

    refute listing_verified?(listing.id)
  end
end
