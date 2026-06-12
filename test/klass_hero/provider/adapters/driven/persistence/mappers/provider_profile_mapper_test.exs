defmodule KlassHero.Provider.Adapters.Driven.Persistence.Mappers.ProviderProfileMapperTest do
  use KlassHero.DataCase, async: true

  alias KlassHero.Provider.Adapters.Driven.Persistence.Mappers.ProviderProfileMapper
  alias KlassHero.Provider.Adapters.Driven.Persistence.Schemas.ProviderProfileSchema
  alias KlassHero.Provider.Domain.Models.ProviderProfile

  describe "profile_status mapping" do
    test "to_domain/1 converts string to atom" do
      schema = %ProviderProfileSchema{
        id: Ecto.UUID.generate(),
        identity_id: Ecto.UUID.generate(),
        business_name: "Test",
        profile_status: "draft",
        categories: [],
        verified: false
      }

      domain = ProviderProfileMapper.to_domain(schema)
      assert domain.profile_status == :draft
    end

    test "to_domain/1 defaults an unknown profile_status to :active" do
      schema = %ProviderProfileSchema{
        id: Ecto.UUID.generate(),
        identity_id: Ecto.UUID.generate(),
        business_name: "Test",
        profile_status: nil,
        categories: [],
        verified: false
      }

      domain = ProviderProfileMapper.to_domain(schema)
      assert domain.profile_status == :active
    end

    test "to_schema/1 converts atom to string" do
      domain = %ProviderProfile{
        id: Ecto.UUID.generate(),
        identity_id: Ecto.UUID.generate(),
        business_name: "Test",
        profile_status: :draft
      }

      attrs = ProviderProfileMapper.to_schema(domain)
      assert attrs.profile_status == "draft"
    end
  end
end
