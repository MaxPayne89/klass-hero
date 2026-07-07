defmodule KlassHeroWeb.Provider.Dashboard.Chrome do
  @moduledoc """
  Shared provider-dashboard header/chrome state for the sub-LiveViews.

  Every dashboard tab renders the same `pv_dashboard_chrome` header (business
  name, verification badge, cross-nav) and the profile-completion banner. Rather
  than each sub-LiveView rebuilding that state in its own `mount/3`, they pipe
  `socket |> Chrome.assign() |> load_own_state()`.

  Depends on `current_scope.provider` and `current_scope` already being populated
  by the `{UserAuth, :require_provider}` on_mount hook that guards every
  `/provider/*` route, so this is safe to call at the top of `mount/3`.

  It assigns a coarse baseline `business.verification_status` (`:verified` for
  verified providers, presenter default otherwise). OverviewLive refines this from
  the provider's verification documents; the other tabs intentionally show the
  baseline, matching the pre-split behaviour.
  """

  import Phoenix.Component, only: [assign: 2]

  alias KlassHero.Accounts.Scope
  alias KlassHero.Provider.ProviderProfile
  alias KlassHeroWeb.Presenters.ProviderPresenter

  @doc """
  Assign the shared chrome state (`:business`, `:profile_draft?`, `:dual_role?`)
  derived from `current_scope`. Returns the socket for piping.
  """
  def assign(socket) do
    provider_profile = socket.assigns.current_scope.provider

    assign(socket,
      business: build_business(provider_profile),
      profile_draft?: ProviderProfile.draft?(provider_profile),
      dual_role?: Scope.dual_role?(socket.assigns.current_scope)
    )
  end

  # Other tabs need a baseline; :overview refines from docs. Verified providers get :verified immediately.
  defp build_business(provider_profile) do
    business = ProviderPresenter.to_business_view(provider_profile)

    if provider_profile.verified do
      %{business | verification_status: :verified}
    else
      business
    end
  end
end
