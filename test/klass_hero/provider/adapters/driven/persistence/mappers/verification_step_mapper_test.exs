defmodule KlassHero.Provider.Adapters.Driven.Persistence.Mappers.VerificationStepMapperTest do
  use KlassHero.DataCase, async: true

  alias KlassHero.Provider.Adapters.Driven.Persistence.Mappers.VerificationStepMapper
  alias KlassHero.Provider.Adapters.Driven.Persistence.Schemas.VerificationStepSchema
  alias KlassHero.Provider.Domain.Models.VerificationStep

  describe "round-trip" do
    test "to_schema then to_domain preserves the structural and status fields" do
      case_id = Ecto.UUID.generate()

      domain = %VerificationStep{
        vetting_case_id: case_id,
        key: :background,
        completed_via: {:document, "background_check"},
        requires: [:identity, :agreement],
        admin_review?: true,
        status: :submitted
      }

      attrs = VerificationStepMapper.to_schema(domain)
      assert attrs.key == "background"
      assert attrs.status == "submitted"
      assert attrs.completed_via == "document:background_check"
      assert attrs.requires == ["identity", "agreement"]
      assert attrs.admin_review == true

      restored =
        VerificationStepMapper.to_domain(struct!(VerificationStepSchema, Map.put(attrs, :id, Ecto.UUID.generate())))

      assert restored.key == :background
      assert restored.status == :submitted
      assert restored.completed_via == {:document, "background_check"}
      assert restored.requires == [:identity, :agreement]
      assert restored.admin_review? == true
    end

    test "round-trips a stripe_identity step's completed_via" do
      domain = %VerificationStep{
        vetting_case_id: Ecto.UUID.generate(),
        key: :identity,
        completed_via: {:stripe_identity},
        admin_review?: false
      }

      attrs = VerificationStepMapper.to_schema(domain)
      assert attrs.completed_via == "stripe_identity"

      restored =
        VerificationStepMapper.to_domain(struct!(VerificationStepSchema, Map.put(attrs, :id, Ecto.UUID.generate())))

      assert restored.completed_via == {:stripe_identity}
    end
  end
end
