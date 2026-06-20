defmodule KlassHero.Provider.Domain.Models.VettingCaseTest do
  @moduledoc """
  Tests for the VettingCase aggregate — owns a Provider's ordered VerificationSteps
  and the vetting lifecycle.
  """

  use ExUnit.Case, async: true

  alias KlassHero.Provider.Domain.Models.VettingCase

  defp provider_id, do: Ecto.UUID.generate()
  defp reviewer_id, do: Ecto.UUID.generate()
  defp evidence_ref, do: Ecto.UUID.generate()

  describe "new_for_track/2" do
    test "builds a case with the track's steps, lifecycle :not_started" do
      case_ = VettingCase.new_for_track(provider_id(), :individual)

      assert case_.entity_type == :individual
      assert case_.lifecycle == :not_started
      assert Enum.map(case_.steps, & &1.key) == [:identity, :experience, :background, :safeguarding]
      assert Enum.all?(case_.steps, &(&1.status == :not_started))
      assert Enum.all?(case_.steps, &(&1.vetting_case_id == case_.id))
    end
  end

  describe "step_key_for_identity/1" do
    test "finds the Stripe identity step in the individual track" do
      case_ = VettingCase.new_for_track(provider_id(), :individual)
      assert VettingCase.step_key_for_identity(case_) == :identity
    end

    test "returns nil when the track has no Stripe identity step" do
      case_ = VettingCase.new_for_track(provider_id(), :business)
      assert VettingCase.step_key_for_identity(case_) == nil
    end
  end

  describe "submit_step/2" do
    test "moves a not_started step to :submitted and the case to :in_progress" do
      case0 = VettingCase.new_for_track(provider_id(), :individual)

      assert {:ok, case1} = VettingCase.submit_step(case0, :identity)
      identity = Enum.find(case1.steps, &(&1.key == :identity))
      assert identity.status == :submitted
      assert case1.lifecycle == :in_progress
    end

    test "errors for an unknown step key" do
      case0 = VettingCase.new_for_track(provider_id(), :individual)
      assert {:error, :step_not_found} = VettingCase.submit_step(case0, :nope)
    end
  end

  describe "verified?/1" do
    test "false for a fresh case" do
      refute VettingCase.verified?(VettingCase.new_for_track(provider_id(), :individual))
    end

    test "true once every step is approved" do
      case_ = approve_all(VettingCase.new_for_track(provider_id(), :individual))
      assert VettingCase.verified?(case_)
    end
  end

  describe "approve_step/4 + lifecycle" do
    test "first approval moves the case to :in_progress, last to :verified" do
      case0 = VettingCase.new_for_track(provider_id(), :individual)

      assert {:ok, case1} = VettingCase.approve_step(case0, :experience, reviewer_id(), evidence_ref())
      assert case1.lifecycle == :in_progress
      refute VettingCase.verified?(case1)

      case_done = approve_all(case1)
      assert case_done.lifecycle == :verified
      assert VettingCase.verified?(case_done)
    end

    test "approving an unknown step key errors" do
      case0 = VettingCase.new_for_track(provider_id(), :individual)
      assert {:error, :step_not_found} = VettingCase.approve_step(case0, :nope, reviewer_id(), evidence_ref())
    end
  end

  defp approve_all(case_) do
    Enum.reduce(case_.steps, case_, fn step, acc ->
      {:ok, advanced} = VettingCase.approve_step(acc, step.key, reviewer_id(), evidence_ref())
      advanced
    end)
  end
end
