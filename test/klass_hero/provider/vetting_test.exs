defmodule KlassHero.Provider.VettingTest do
  @moduledoc """
  Tests for the Vetting track policy — the ordered, composable set of
  VerificationStep definitions selected by entity_type.
  """

  use ExUnit.Case, async: true

  alias KlassHero.Provider.StepDefinition
  alias KlassHero.Provider.Vetting

  describe "track/1 for :individual" do
    test "returns the identity step first, then the document steps in order" do
      assert [%StepDefinition{} | _] = steps = Vetting.track(:individual)

      assert Enum.map(steps, & &1.key) == [
               :identity,
               :experience,
               :background,
               :video,
               :safeguarding,
               :community_agreement
             ]
    end

    test "identity is a Stripe step that auto-approves (no admin review, no prerequisites)" do
      [identity | _] = Vetting.track(:individual)

      assert identity.key == :identity
      assert identity.completed_via == {:stripe_identity}
      assert identity.admin_review == false
      assert identity.requires == []
    end

    test "video screening is a document-evidence step reviewed by an admin (Step 4)" do
      video = Enum.find(Vetting.track(:individual), &(&1.key == :video))

      assert video.completed_via == {:document, "video_screening"}
      assert video.admin_review == true
    end

    test "community agreement is the final step: a signed-agreement step that auto-approves" do
      steps = Vetting.track(:individual)
      agreement = List.last(steps)

      assert agreement.key == :community_agreement
      assert agreement.completed_via == {:signed_agreement, :community_agreement}
      assert agreement.admin_review == false
    end

    test "the document steps require admin review" do
      for %StepDefinition{completed_via: {:document, type}, admin_review: admin_review} <-
            Vetting.track(:individual) do
        assert type != ""
        assert admin_review == true
      end
    end
  end

  describe "track/1 for :business" do
    test "returns the five business steps in order: identity, docs, then the two agreements" do
      steps = Vetting.track(:business)

      assert Enum.map(steps, & &1.key) == [
               :responsible_person_identity,
               :business_registration,
               :insurance,
               :community_agreement,
               :staff_attestation
             ]
    end

    test "the responsible-person step is a Stripe step that auto-approves with no prerequisites" do
      identity = Enum.find(Vetting.track(:business), &(&1.key == :responsible_person_identity))

      assert identity.completed_via == {:stripe_identity}
      assert identity.admin_review == false
      assert identity.requires == []
    end

    test "registration and insurance are admin-reviewed document steps with no prerequisites" do
      for key <- [:business_registration, :insurance] do
        step = Enum.find(Vetting.track(:business), &(&1.key == key))

        assert match?({:document, _}, step.completed_via)
        assert step.admin_review == true
        assert step.requires == []
      end
    end

    test "both agreements auto-approve and require the responsible-person identity (ADR-0010)" do
      for kind <- [:community_agreement, :staff_attestation] do
        step = Enum.find(Vetting.track(:business), &(&1.key == kind))

        assert step.completed_via == {:signed_agreement, kind}
        assert step.admin_review == false
        assert step.requires == [:responsible_person_identity]
      end
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
