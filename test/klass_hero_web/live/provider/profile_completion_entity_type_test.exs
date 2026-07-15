defmodule KlassHeroWeb.Provider.ProfileCompletionEntityTypeTest do
  @moduledoc """
  Slice 0: the profile-completion form lets a provider pick the :business vetting track,
  but ONLY behind the `:business_vetting` feature flag. Async: false because it drives the
  default-named stub feature-flags agent, which the LiveView resolves with no opts.
  """

  use KlassHeroWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias KlassHero.Provider
  alias KlassHero.Shared.Adapters.Driven.FeatureFlags.StubFeatureFlagsAdapter

  setup :register_and_log_in_draft_provider

  # The production call site `FeatureFlags.enabled?(:business_vetting)` (no opts) resolves the
  # stub's default-named agent. Start it here so this test can flip the flag on; without it the
  # stub returns {:ok, false} and the selector stays hidden (the "off" case).
  defp enable_business_vetting(_context) do
    start_supervised!(%{
      id: StubFeatureFlagsAdapter,
      start: {StubFeatureFlagsAdapter, :start_link, [[name: StubFeatureFlagsAdapter]]}
    })

    StubFeatureFlagsAdapter.set_enabled(:business_vetting)
    :ok
  end

  describe "flag OFF (default)" do
    test "no entity-type selector renders", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/provider/complete-profile")

      refute has_element?(view, ~s(input[name="provider_profile_schema[entity_type]"]))
    end

    test "a spoofed entity_type param is ignored — provider stays :individual", %{
      conn: conn,
      provider: provider
    } do
      {:ok, view, _html} = live(conn, ~p"/provider/complete-profile")

      view
      |> element("#profile-completion-form")
      |> render_submit(%{
        provider_profile_schema: %{
          business_name: "Spoof Ltd",
          description: "Trying to flip the track",
          entity_type: "business"
        }
      })

      {:ok, reloaded} = Provider.get_provider_profile(provider.id)
      assert reloaded.entity_type == :individual
    end
  end

  describe "flag ON" do
    setup :enable_business_vetting

    test "the business option renders", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/provider/complete-profile")

      assert has_element?(
               view,
               ~s(input[name="provider_profile_schema[entity_type]"][value="business"])
             )
    end

    test "picking business persists :business on completion", %{conn: conn, provider: provider} do
      {:ok, view, _html} = live(conn, ~p"/provider/complete-profile")

      view
      |> element("#profile-completion-form")
      |> render_submit(%{
        provider_profile_schema: %{
          business_name: "Real Business Ltd",
          description: "A genuine business provider",
          entity_type: "business"
        }
      })

      assert_redirect(view, ~p"/provider/dashboard")

      {:ok, reloaded} = Provider.get_provider_profile(provider.id)
      assert reloaded.entity_type == :business
    end
  end
end
