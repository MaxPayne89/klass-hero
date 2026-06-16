defmodule KlassHero.Provider.Domain.Models.VettingCaseResetTest do
  @moduledoc """
  Tests for VettingCase.reset_step/2 — the reverse-edge `requires` cascade that powers both
  document-rejection recovery and the business responsible-person reset.
  """

  use ExUnit.Case, async: true

  alias KlassHero.Provider.Domain.Models.StepDefinition
  alias KlassHero.Provider.Domain.Models.VerificationStep
  alias KlassHero.Provider.Domain.Models.VettingCase

  # A business-shaped case: agreement and attestation both require identity;
  # registration is independent. Mirrors B1 / B4 / B5 / B2.
  defp business_case do
    defs = [
      %StepDefinition{key: :identity, completed_via: {:document, "id"}},
      %StepDefinition{key: :registration, completed_via: {:document, "biz_reg"}},
      %StepDefinition{key: :agreement, completed_via: {:document, "agreement"}, requires: [:identity]},
      %StepDefinition{key: :attestation, completed_via: {:document, "attestation"}, requires: [:identity]}
    ]

    case_id = Ecto.UUID.generate()
    steps = Enum.map(defs, &VerificationStep.from_definition(&1, case_id))
    %VettingCase{id: case_id, provider_id: Ecto.UUID.generate(), entity_type: :business, steps: steps}
  end

  defp approve_all(case_) do
    Enum.reduce(case_.steps, case_, fn step, acc ->
      {:ok, advanced} = VettingCase.approve_step(acc, step.key, Ecto.UUID.generate(), Ecto.UUID.generate())
      advanced
    end)
  end

  defp status(case_, key), do: Enum.find(case_.steps, &(&1.key == key)).status

  describe "reset_step/2 cascade" do
    test "resets the target step and its direct dependents, leaving independents untouched" do
      case_ = approve_all(business_case())
      assert VettingCase.verified?(case_)

      {:ok, reset} = VettingCase.reset_step(case_, :identity)

      assert status(reset, :identity) == :not_started
      assert status(reset, :agreement) == :not_started
      assert status(reset, :attestation) == :not_started
      assert status(reset, :registration) == :approved
    end

    test "drops a verified case to :in_progress after a cascade" do
      case_ = approve_all(business_case())
      {:ok, reset} = VettingCase.reset_step(case_, :identity)
      assert reset.lifecycle == :in_progress
      refute VettingCase.verified?(reset)
    end

    test "resetting an independent step does not touch others" do
      case_ = approve_all(business_case())
      {:ok, reset} = VettingCase.reset_step(case_, :registration)

      assert status(reset, :registration) == :not_started
      assert status(reset, :identity) == :approved
      assert status(reset, :agreement) == :approved
    end

    test "cascades transitively through a chain" do
      # attestation requires agreement requires identity
      defs = [
        %StepDefinition{key: :identity, completed_via: {:document, "id"}},
        %StepDefinition{key: :agreement, completed_via: {:document, "agreement"}, requires: [:identity]},
        %StepDefinition{key: :attestation, completed_via: {:document, "attestation"}, requires: [:agreement]}
      ]

      case_id = Ecto.UUID.generate()
      steps = Enum.map(defs, &VerificationStep.from_definition(&1, case_id))

      case_ =
        approve_all(%VettingCase{id: case_id, provider_id: Ecto.UUID.generate(), entity_type: :business, steps: steps})

      {:ok, reset} = VettingCase.reset_step(case_, :identity)

      assert status(reset, :identity) == :not_started
      assert status(reset, :agreement) == :not_started
      assert status(reset, :attestation) == :not_started
    end

    test "cascades regardless of step order (dependents listed before prerequisites)" do
      # Reverse topological order: each dependent appears BEFORE the step it requires.
      # A single left-to-right pass would miss the far end of the chain; the closure must not.
      defs = [
        %StepDefinition{key: :attestation, completed_via: {:document, "attestation"}, requires: [:agreement]},
        %StepDefinition{key: :agreement, completed_via: {:document, "agreement"}, requires: [:identity]},
        %StepDefinition{key: :identity, completed_via: {:document, "id"}}
      ]

      case_id = Ecto.UUID.generate()
      steps = Enum.map(defs, &VerificationStep.from_definition(&1, case_id))

      case_ =
        approve_all(%VettingCase{id: case_id, provider_id: Ecto.UUID.generate(), entity_type: :business, steps: steps})

      {:ok, reset} = VettingCase.reset_step(case_, :identity)

      assert status(reset, :identity) == :not_started
      assert status(reset, :agreement) == :not_started
      assert status(reset, :attestation) == :not_started
    end

    test "errors for an unknown step key" do
      assert {:error, :step_not_found} = VettingCase.reset_step(business_case(), :nope)
    end
  end
end
