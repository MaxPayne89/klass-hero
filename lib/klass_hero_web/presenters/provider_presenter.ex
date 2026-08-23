defmodule KlassHeroWeb.Presenters.ProviderPresenter do
  @moduledoc """
  Transforms Provider domain models to UI-ready formats.
  """

  use Gettext, backend: KlassHeroWeb.Gettext

  alias KlassHero.Provider
  alias KlassHero.Provider.ProviderProfile
  alias KlassHero.Shared.NameUtils
  alias KlassHero.SocialLinks

  @doc """
  Transforms a Provider domain model to business view format.

  Used for the provider dashboard header and business profile card.

  Returns a map with: id, name, tagline, verified, verification_badges,
  initials, logo_url, verification_status
  """
  @spec to_business_view(ProviderProfile.t()) :: map()
  def to_business_view(%ProviderProfile{} = provider) do
    %{
      id: provider.id,
      name: provider.business_name,
      # NOT ProviderProfile.tagline — this key predates that field (#1302) and
      # still carries the description. The dashboard header and business card
      # render it under this name. Renaming it means touching those shared
      # components, so it is tracked separately rather than done here.
      tagline: provider.description,
      verified: provider.verified || false,
      verification_badges: build_verification_badges(provider),
      initials: NameUtils.initials_from_name(provider.business_name),
      logo_url: provider.logo_url,
      verification_status: :not_started
    }
  end

  @doc """
  Transforms a Provider domain model to a slim, public-facing view.

  Used for surfaces shown to parents (e.g. the program detail page) where
  tier/verification/slot data is not relevant — only the business identity.

  Returns a map with: id, business_name, description, logo_url, initials,
  trust_state, plus the branding fields (tagline, cover_image_url, social_links).

  `social_links` is a list of `{network, label, url}` for the networks the provider
  filled in; the atom is what `kh_social_icon/1` keys on.

  `trust_state` is passed in, not fetched — this module is a pure transform and
  `Provider.get_trust_states/1` is a DB read. It defaults to `:unverified` so an
  unthreaded caller shows no badge rather than one the provider has not earned.
  """
  @spec to_public_view(ProviderProfile.t(), Provider.trust_state()) :: map()
  def to_public_view(%ProviderProfile{} = provider, trust_state \\ :unverified) do
    %{
      id: provider.id,
      business_name: provider.business_name,
      description: provider.description,
      logo_url: provider.logo_url,
      initials: NameUtils.initials_from_name(provider.business_name),
      tagline: provider.tagline,
      cover_image_url: provider.cover_image_url,
      social_links: social_links(provider),
      trust_state: trust_state
    }
  end

  # The entity owns which networks exist; this maps its column to the short atom
  # `kh_social_icon/1` keys on. Spelled out rather than derived by stripping
  # "_url", so a renamed column fails loudly here. Labels live in SocialLinks.
  @social_field_networks %{
    instagram_url: :instagram,
    facebook_url: :facebook,
    tiktok_url: :tiktok,
    youtube_url: :youtube,
    linkedin_url: :linkedin
  }

  @social_networks Enum.map(ProviderProfile.social_link_fields(), fn field ->
                     network = Map.fetch!(@social_field_networks, field)
                     {field, network, SocialLinks.label(network)}
                   end)

  @social_field_labels Enum.map(@social_networks, fn {field, _network, label} ->
                         {field, label}
                       end)

  # Both sources share one `kh_social_icon/1`; a network with no glyph renders an
  # empty `<svg>` with no error and no failing test.
  @provider_network_atoms Enum.map(@social_networks, fn {_f, network, _l} -> network end)

  if Enum.sort(@provider_network_atoms) != Enum.sort(KlassHero.SocialLinks.networks()) do
    raise "provider social networks #{inspect(@provider_network_atoms)} have drifted from " <>
            "KlassHero.SocialLinks.networks() #{inspect(KlassHero.SocialLinks.networks())}"
  end

  @doc """
  Supported social networks as `{schema_field, label}`.

  Labels are brand names and deliberately not run through gettext — translating
  "Instagram" would be wrong in every locale.
  """
  @spec social_networks() :: [{atom(), String.t()}]
  def social_networks, do: @social_field_labels

  defp social_links(%ProviderProfile{} = provider) do
    for {field, network, label} <- @social_networks,
        url = Map.fetch!(provider, field),
        url not in [nil, ""],
        do: {network, label, url}
  end

  @doc """
  Derives the aggregate verification status from a list of verification documents.

  Status priority:
  - `:verified` — provider.verified is true (takes precedence)
  - `:pending` — documents under review OR all approved but provider not yet verified
  - `:rejected` — at least one document is rejected (action required)
  - `:not_started` — no documents submitted
  """
  @spec verification_status_from_docs(boolean(), [map()]) :: atom()
  def verification_status_from_docs(true, _docs), do: :verified

  def verification_status_from_docs(_verified, []), do: :not_started

  def verification_status_from_docs(_verified, docs) do
    # All-approved also maps to :pending — awaiting admin final sign-off.
    cond do
      Enum.any?(docs, &(&1.status == :pending)) -> :pending
      Enum.any?(docs, &(&1.status == :rejected)) -> :rejected
      true -> :pending
    end
  end

  @doc """
  Builds a list of verification badges for display.

  Returns a list of maps with :key and :label for each badge.
  """
  @spec build_verification_badges(ProviderProfile.t()) :: [map()]
  def build_verification_badges(%ProviderProfile{verified: true}) do
    [
      %{key: :business_registration, label: gettext("Business Registration")}
    ]
  end

  def build_verification_badges(_provider), do: []

  @doc """
  Returns a human-readable label for a verification document type atom.
  """
  @spec document_type_label(atom()) :: String.t()
  def document_type_label(:business_registration), do: gettext("Business Registration")
  def document_type_label(:insurance_certificate), do: gettext("Insurance Certificate")
  def document_type_label(:id_document), do: gettext("ID Document")
  def document_type_label(:tax_certificate), do: gettext("Tax Certificate")
  def document_type_label(:other), do: gettext("Other")
  def document_type_label(:experience_validation), do: gettext("Experience validation")
  def document_type_label(:background_check), do: gettext("Background check")
  def document_type_label(:video_screening), do: gettext("Video screening")
  def document_type_label(:safeguarding_certificate), do: gettext("Safeguarding certificate")
  # Legacy/out-of-enum values load as the :unknown sentinel (#1026).
  def document_type_label(:unknown), do: gettext("Unknown")
  def document_type_label(type), do: to_string(type)
end
