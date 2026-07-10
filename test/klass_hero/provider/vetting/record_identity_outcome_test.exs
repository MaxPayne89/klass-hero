defmodule KlassHero.Provider.Vetting.RecordIdentityOutcomeTest do
  use KlassHero.DataCase, async: false

  import ExUnit.CaptureLog

  alias KlassHero.Provider
  alias KlassHero.Provider.IdentityVerification
  alias KlassHero.ProviderFixtures
  alias KlassHero.Repo

  @today ~D[2026-06-18]

  setup do
    provider = ProviderFixtures.provider_profile_fixture()
    seed_processing(provider.id, "vs_live")
    %{provider: provider}
  end

  defp outcome(attrs), do: Map.merge(%{session_id: "vs_live", today: @today}, attrs)

  defp seed_processing(provider_id, session_id) do
    %IdentityVerification{}
    |> IdentityVerification.create_changeset(%{
      id: Ecto.UUID.generate(),
      provider_id: provider_id,
      stripe_session_id: session_id,
      status: :processing
    })
    |> Repo.insert!()
  end

  defp reload(session_id), do: Repo.get_by!(IdentityVerification, stripe_session_id: session_id)

  describe "record_identity_verification_outcome/1 — verified" do
    test "an adult passes the age gate" do
      assert {:ok, iv} =
               Provider.record_identity_verification_outcome(
                 outcome(%{stripe_status: :verified, dob: %{day: 1, month: 1, year: 1990}})
               )

      assert iv.status == :verified
      assert iv.outcome == :pass
    end

    test "a minor fails closed with under_18" do
      assert {:ok, iv} =
               Provider.record_identity_verification_outcome(
                 outcome(%{stripe_status: :verified, dob: %{day: 1, month: 1, year: 2015}})
               )

      assert iv.outcome == :fail
      assert iv.failure_reason == "under_18"
    end

    test "a missing DOB fails closed with age_unverifiable" do
      assert {:ok, iv} =
               Provider.record_identity_verification_outcome(outcome(%{stripe_status: :verified, dob: nil}))

      assert iv.outcome == :fail
      assert iv.failure_reason == "age_unverifiable"
    end
  end

  describe "record_identity_verification_outcome/1 — non-verified terminal outcomes" do
    test "requires_input is a failed outcome" do
      assert {:ok, iv} = Provider.record_identity_verification_outcome(outcome(%{stripe_status: :requires_input}))
      assert iv.status == :requires_input
      assert iv.outcome == :fail
    end

    test "canceled is a failed outcome" do
      assert {:ok, iv} = Provider.record_identity_verification_outcome(outcome(%{stripe_status: :canceled}))
      assert iv.status == :canceled
      assert iv.outcome == :fail
    end
  end

  describe "record_identity_verification_outcome/1 — unexpected stripe_status (fail-closed)" do
    test "an unmapped status is a no-op (no DB write, no event) and is logged" do
      log =
        capture_log(fn ->
          assert {:ok, :ignored} =
                   Provider.record_identity_verification_outcome(outcome(%{stripe_status: :expired}))
        end)

      assert log =~ "expired"

      iv = reload("vs_live")
      assert iv.status == :processing
      assert iv.outcome == nil
    end
  end

  describe "record_identity_verification_outcome/1 — idempotency" do
    test "an unknown session id is ignored (acked, no-op)" do
      assert {:ok, :ignored} =
               Provider.record_identity_verification_outcome(
                 outcome(%{session_id: "vs_unknown", stripe_status: :canceled})
               )
    end

    test "a duplicate/out-of-order event on an already-terminal record is a no-op" do
      {:ok, _} =
        Provider.record_identity_verification_outcome(
          outcome(%{stripe_status: :verified, dob: %{day: 1, month: 1, year: 1990}})
        )

      assert {:ok, :already_recorded} =
               Provider.record_identity_verification_outcome(outcome(%{stripe_status: :requires_input}))

      assert reload("vs_live").outcome == :pass
    end
  end
end
