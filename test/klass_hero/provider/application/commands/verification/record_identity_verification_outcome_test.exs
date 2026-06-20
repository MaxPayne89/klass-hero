defmodule KlassHero.Provider.Application.Commands.Verification.RecordIdentityVerificationOutcomeTest do
  use KlassHero.DataCase, async: false

  alias KlassHero.Provider.Adapters.Driven.Persistence.Repositories.IdentityVerificationRepository
  alias KlassHero.Provider.Application.Commands.Verification.RecordIdentityVerificationOutcome
  alias KlassHero.Provider.Domain.Models.IdentityVerification
  alias KlassHero.ProviderFixtures

  @today ~D[2026-06-18]

  setup do
    provider = ProviderFixtures.provider_profile_fixture()

    {:ok, _iv} =
      IdentityVerificationRepository.create(
        IdentityVerification.new(%{provider_id: provider.id, stripe_session_id: "vs_live"})
      )

    %{provider: provider}
  end

  defp outcome(attrs), do: Map.merge(%{session_id: "vs_live", today: @today}, attrs)

  describe "execute/1 — verified" do
    test "an adult passes the age gate" do
      assert {:ok, iv} =
               RecordIdentityVerificationOutcome.execute(
                 outcome(%{stripe_status: :verified, dob: %{day: 1, month: 1, year: 1990}})
               )

      assert iv.status == :verified
      assert iv.outcome == :pass
    end

    test "a minor fails closed with under_18" do
      assert {:ok, iv} =
               RecordIdentityVerificationOutcome.execute(
                 outcome(%{stripe_status: :verified, dob: %{day: 1, month: 1, year: 2015}})
               )

      assert iv.outcome == :fail
      assert iv.failure_reason == "under_18"
    end

    test "a missing DOB fails closed with age_unverifiable" do
      assert {:ok, iv} =
               RecordIdentityVerificationOutcome.execute(outcome(%{stripe_status: :verified, dob: nil}))

      assert iv.outcome == :fail
      assert iv.failure_reason == "age_unverifiable"
    end
  end

  describe "execute/1 — non-verified terminal outcomes" do
    test "requires_input is a failed outcome" do
      assert {:ok, iv} = RecordIdentityVerificationOutcome.execute(outcome(%{stripe_status: :requires_input}))
      assert iv.status == :requires_input
      assert iv.outcome == :fail
    end

    test "canceled is a failed outcome" do
      assert {:ok, iv} = RecordIdentityVerificationOutcome.execute(outcome(%{stripe_status: :canceled}))
      assert iv.status == :canceled
      assert iv.outcome == :fail
    end
  end

  describe "execute/1 — idempotency" do
    test "an unknown session id is ignored (acked, no-op)" do
      assert {:ok, :ignored} =
               RecordIdentityVerificationOutcome.execute(outcome(%{session_id: "vs_unknown", stripe_status: :canceled}))
    end

    test "a duplicate/out-of-order event on an already-terminal record is a no-op" do
      {:ok, _} =
        RecordIdentityVerificationOutcome.execute(
          outcome(%{stripe_status: :verified, dob: %{day: 1, month: 1, year: 1990}})
        )

      assert {:ok, :already_recorded} =
               RecordIdentityVerificationOutcome.execute(outcome(%{stripe_status: :requires_input}))

      # The earlier pass is untouched.
      {:ok, iv} = IdentityVerificationRepository.get_by_session_id("vs_live")
      assert iv.outcome == :pass
    end
  end
end
