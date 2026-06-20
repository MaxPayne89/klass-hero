defmodule KlassHero.Provider.Domain.Services.VettingTest do
  @moduledoc """
  Tests for the Vetting track policy — the ordered, composable set of
  VerificationStep definitions selected by entity_type.
  """

  use ExUnit.Case, async: true

  alias KlassHero.Provider.Domain.Models.StepDefinition
  alias KlassHero.Provider.Domain.Services.Vetting

  describe "track/1 for :individual" do
    test "returns the identity step first, then the document steps in order" do
      assert [%StepDefinition{} | _] = steps = Vetting.track(:individual)
      assert Enum.map(steps, & &1.key) == [:identity, :experience, :background, :safeguarding]
    end

    test "identity is a Stripe step that auto-approves (no admin review, no prerequisites)" do
      [identity | _] = Vetting.track(:individual)

      assert identity.key == :identity
      assert identity.completed_via == {:stripe_identity}
      assert identity.admin_review? == false
      assert identity.requires == []
    end

    test "the document steps require admin review" do
      for %StepDefinition{completed_via: {:document, type}, admin_review?: admin_review?} <-
            Vetting.track(:individual) do
        assert is_binary(type)
        assert admin_review? == true
      end
    end
  end

  describe "track/1 for :business" do
    test "returns the business document steps in order" do
      steps = Vetting.track(:business)
      assert Enum.map(steps, & &1.key) == [:business_registration, :insurance]
    end
  end

  describe "track/1 prerequisite graph" do
    test "no spine step declares an unsatisfiable prerequisite" do
      for entity_type <- [:individual, :business] do
        steps = Vetting.track(entity_type)
        keys = MapSet.new(steps, & &1.key)

        for %StepDefinition{requires: requires} <- steps,
            required_key <- requires do
          assert MapSet.member?(keys, required_key),
                 "#{entity_type} step requires #{required_key}, absent from the track"
        end
      end
    end
  end
end
