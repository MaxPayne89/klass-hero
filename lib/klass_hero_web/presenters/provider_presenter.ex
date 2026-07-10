defmodule KlassHeroWeb.Presenters.ProviderPresenter do
  @moduledoc """
  Transforms Provider domain models to UI-ready formats.
  """

  use Gettext, backend: KlassHeroWeb.Gettext

  alias KlassHero.Provider.ProviderProfile
  alias KlassHero.Shared.NameUtils

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

  Returns a map with: id, business_name, description, logo_url, initials.
  """
  @spec to_public_view(ProviderProfile.t()) :: map()
  def to_public_view(%ProviderProfile{} = provider) do
    %{
      id: provider.id,
      business_name: provider.business_name,
      description: provider.description,
      logo_url: provider.logo_url,
      initials: NameUtils.initials_from_name(provider.business_name)
    }
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
