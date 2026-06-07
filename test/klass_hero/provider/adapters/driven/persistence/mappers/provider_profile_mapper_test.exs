defmodule KlassHero.Provider.Adapters.Driven.Persistence.Mappers.ProviderProfileMapperTest do
  use KlassHero.DataCase, async: true

  alias KlassHero.Provider.Adapters.Driven.Persistence.Mappers.ProviderProfileMapper
  alias KlassHero.Provider.Adapters.Driven.Persistence.Schemas.ProviderProfileSchema
  alias KlassHero.Provider.Domain.Models.ProviderProfile

  describe "originated_from mapping" do
    test "to_domain/1 converts string to atom" do
      schema = %ProviderProfileSchema{
        id: Ecto.UUID.generate(),
        identity_id: Ecto.UUID.generate(),
        business_name: "Test",
        originated_from: "staff_invite",
        categories: [],
        verified: false
      }

      domain = ProviderProfileMapper.to_domain(schema)
      assert domain.originated_from == :staff_invite
    end

    test "to_domain/1 defaults originated_from to :direct" do
      schema = %ProviderProfileSchema{
        id: Ecto.UUID.generate(),
        identity_id: Ecto.UUID.generate(),
        business_name: "Test",
        originated_from: "direct",
        categories: [],
        verified: false
      }

      domain = ProviderProfileMapper.to_domain(schema)
      assert domain.originated_from == :direct
    end

    test "to_schema/1 converts atom to string" do
      domain = %ProviderProfile{
        id: Ecto.UUID.generate(),
        identity_id: Ecto.UUID.generate(),
        business_name: "Test",
        originated_from: :staff_invite
      }

      attrs = ProviderProfileMapper.to_schema(domain)
      assert attrs.originated_from == "staff_invite"
    end
  end
end
