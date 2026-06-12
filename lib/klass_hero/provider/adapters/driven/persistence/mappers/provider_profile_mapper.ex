defmodule KlassHero.Provider.Adapters.Driven.Persistence.Mappers.ProviderProfileMapper do
  @moduledoc """
  Bidirectional mapping between `ProviderProfile` domain entities and `ProviderProfileSchema` Ecto structs.
  """

  import KlassHero.Shared.Adapters.Driven.Persistence.MapperHelpers,
    only: [maybe_add_id: 2]

  alias KlassHero.Provider.Adapters.Driven.Persistence.Schemas.ProviderProfileSchema
  alias KlassHero.Provider.Domain.Models.ProviderProfile

  @doc """
  Converts an Ecto ProviderProfileSchema to a domain ProviderProfile entity.

  Returns the domain ProviderProfile struct with all fields mapped from the schema.
  UUIDs are converted to strings to maintain domain independence from Ecto types.
  """
  def to_domain(%ProviderProfileSchema{} = schema) do
    %ProviderProfile{
      id: to_string(schema.id),
      identity_id: to_string(schema.identity_id),
      business_name: schema.business_name,
      business_owner_email: schema.business_owner_email,
      description: schema.description,
      phone: schema.phone,
      website: schema.website,
      address: schema.address,
      logo_url: schema.logo_url,
      verified: schema.verified,
      verified_at: schema.verified_at,
      verified_by_id: schema.verified_by_id && to_string(schema.verified_by_id),
      categories: schema.categories,
      profile_status: string_to_profile_status(schema.profile_status),
      inserted_at: schema.inserted_at,
      updated_at: schema.updated_at
    }
  end

  @doc """
  Converts a domain ProviderProfile entity to ProviderProfileSchema attributes map.

  Returns a map suitable for Ecto changeset operations (insert/update).
  This is used when creating or updating provider profiles in the database.
  """
  def to_schema(%ProviderProfile{} = provider_profile) do
    %{
      identity_id: provider_profile.identity_id,
      business_name: provider_profile.business_name,
      business_owner_email: provider_profile.business_owner_email,
      description: provider_profile.description,
      phone: provider_profile.phone,
      website: provider_profile.website,
      address: provider_profile.address,
      logo_url: provider_profile.logo_url,
      verified: provider_profile.verified,
      verified_at: provider_profile.verified_at,
      verified_by_id: provider_profile.verified_by_id,
      categories: provider_profile.categories,
      profile_status: profile_status_to_string(provider_profile.profile_status)
    }
    |> maybe_add_id(provider_profile.id)
  end

  defp string_to_profile_status("draft"), do: :draft
  defp string_to_profile_status("active"), do: :active
  defp string_to_profile_status(_), do: :active

  defp profile_status_to_string(:draft), do: "draft"
  defp profile_status_to_string(_), do: "active"
end
