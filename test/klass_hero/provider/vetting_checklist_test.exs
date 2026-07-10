defmodule KlassHero.Provider.VettingChecklistTest do
  @moduledoc """
  Integration tests for the vetting onboarding checklist read model.

  Exercises the full read path: `Vetting.checklist_for_provider/1` -> vetting case + evidence ->
  database -> `VettingChecklist`. The merge that re-surfaces `:rejected` from evidence is the
  behaviour under test.
  """

  use KlassHero.DataCase, async: true

  import KlassHero.ProviderFixtures

  alias KlassHero.Provider.Vetting
  alias KlassHero.Provider.VettingCase
  alias KlassHero.Provider.VettingChecklist
  alias KlassHero.Provider.VettingStepView

  describe "checklist_for_provider/1" do
    test "returns the individual track's steps in order, all not started for a fresh case" do
      provider = provider_profile_fixture()

      checklist = Vetting.checklist_for_provider(provider.id)

      assert %VettingChecklist{
               entity_type: :individual,
               lifecycle: :not_started,
               verified?: false,
               approved_count: 0,
               total_count: 6
             } = checklist

      assert Enum.map(checklist.steps, & &1.key) ==
               [:identity, :experience, :background, :video, :safeguarding, :community_agreement]

      assert Enum.all?(checklist.steps, &match?(%VettingStepView{ui_status: :not_started}, &1))
    end

    test "re-surfaces a rejected document step with its reason from the evidence record" do
      provider = provider_profile_fixture()
      reviewer = KlassHero.AccountsFixtures.user_fixture()

      rejected_verification_document_fixture(%{
        provider_id: provider.id,
        document_type: "experience_validation",
        rejection_reason: "Blurry scan — please re-upload.",
        reviewer_id: reviewer.id
      })

      checklist = Vetting.checklist_for_provider(provider.id)

      experience = Enum.find(checklist.steps, &(&1.key == :experience))

      assert %VettingStepView{
               ui_status: :rejected,
               rejection_reason: "Blurry scan — please re-upload."
             } = experience

      # Other steps are untouched.
      assert checklist.approved_count == 0
      assert checklist.lifecycle == :not_started

      assert checklist.steps
             |> Enum.reject(&(&1.key == :experience))
             |> Enum.all?(&match?(%VettingStepView{ui_status: :not_started}, &1))
    end

    test "re-surfaces a failed identity step with its reason from the evidence record" do
      provider = provider_profile_fixture()

      identity_verification_fixture(%{
        provider_id: provider.id,
        status: :verified,
        outcome: :fail,
        failure_reason: "under_18"
      })

      checklist = Vetting.checklist_for_provider(provider.id)

      assert %VettingStepView{ui_status: :rejected, rejection_reason: "under_18"} =
               Enum.find(checklist.steps, &(&1.key == :identity))
    end

    test "counts an approved step toward the verified total" do
      provider = provider_profile_fixture()
      reviewer = KlassHero.AccountsFixtures.user_fixture()

      # Drive a real step approval through the engine (mirrors the document-review handler).
      {:ok, case_} = Vetting.get_case_for_provider(provider.id)
      {:ok, approved} = VettingCase.approve_step(case_, :experience, reviewer.id, Ecto.UUID.generate())
      {:ok, _} = Vetting.save_case(approved)

      checklist = Vetting.checklist_for_provider(provider.id)

      assert %VettingStepView{ui_status: :approved} =
               Enum.find(checklist.steps, &(&1.key == :experience))

      assert checklist.approved_count == 1
      assert checklist.lifecycle == :in_progress
      refute checklist.verified?
    end
  end
end
