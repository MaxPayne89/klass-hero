defmodule KlassHero.Provider.Domain.Models.VerificationStepTest do
  @moduledoc """
  Tests for the VerificationStep domain model — one unit of a Vetting Case,
  frozen from a StepDefinition and moving through its status lifecycle.
  """

  use ExUnit.Case, async: true

  alias KlassHero.Provider.Domain.Models.StepDefinition
  alias KlassHero.Provider.Domain.Models.VerificationStep

  defp definition(attrs \\ %{}) do
    %StepDefinition{
      key: Map.get(attrs, :key, :background),
      completed_via: Map.get(attrs, :completed_via, {:document, "background_check"}),
      requires: Map.get(attrs, :requires, []),
      admin_review?: Map.get(attrs, :admin_review?, true)
    }
  end

  describe "from_definition/2" do
    test "freezes the definition's structural fields and starts not_started" do
      case_id = Ecto.UUID.generate()
      step = VerificationStep.from_definition(definition(%{requires: [:identity]}), case_id)

      assert step.vetting_case_id == case_id
      assert step.key == :background
      assert step.completed_via == {:document, "background_check"}
      assert step.requires == [:identity]
      assert step.admin_review? == true
      assert step.status == :not_started
    end
  end

  describe "submit/1" do
    test "moves a not_started step to submitted" do
      step = VerificationStep.from_definition(definition(), Ecto.UUID.generate())
      assert {:ok, submitted} = VerificationStep.submit(step)
      assert submitted.status == :submitted
    end
  end

  describe "approve/3" do
    test "approves a submitted step, recording reviewer and evidence" do
      reviewer = Ecto.UUID.generate()
      evidence = Ecto.UUID.generate()
      {:ok, submitted} = VerificationStep.submit(from_step())

      assert {:ok, approved} = VerificationStep.approve(submitted, reviewer, evidence)
      assert approved.status == :approved
      assert approved.reviewed_by_id == reviewer
      assert approved.evidence_ref == evidence
      assert VerificationStep.approved?(approved)
    end

    test "refuses to approve a not_started step" do
      assert {:error, :step_not_submitted} =
               VerificationStep.approve(from_step(), Ecto.UUID.generate(), Ecto.UUID.generate())
    end
  end

  describe "reject/3" do
    test "rejects a submitted step with a reason" do
      {:ok, submitted} = VerificationStep.submit(from_step())
      assert {:ok, rejected} = VerificationStep.reject(submitted, Ecto.UUID.generate(), "blurry scan")
      assert rejected.status == :rejected
      assert rejected.rejection_reason == "blurry scan"
    end
  end

  describe "reset/1" do
    test "returns an approved step to not_started and detaches evidence" do
      {:ok, submitted} = VerificationStep.submit(from_step())
      {:ok, approved} = VerificationStep.approve(submitted, Ecto.UUID.generate(), Ecto.UUID.generate())

      assert {:ok, reset} = VerificationStep.reset(approved)
      assert reset.status == :not_started
      assert reset.evidence_ref == nil
      assert reset.reviewed_by_id == nil
    end
  end

  defp from_step,
    do:
      VerificationStep.from_definition(
        %StepDefinition{key: :background, completed_via: {:document, "background_check"}},
        Ecto.UUID.generate()
      )
end
