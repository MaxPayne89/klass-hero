defmodule KlassHero.Provider.Adapters.Driven.Persistence.Repositories.IdentityVerificationRepositoryTest do
  use KlassHero.DataCase, async: true

  alias KlassHero.Provider.Adapters.Driven.Persistence.Repositories.IdentityVerificationRepository
  alias KlassHero.Provider.Adapters.Driven.Persistence.Schemas.ProviderProfileSchema
  alias KlassHero.Provider.Domain.Models.IdentityVerification
  alias KlassHero.Repo

  defp provider_id do
    {:ok, schema} =
      %ProviderProfileSchema{}
      |> ProviderProfileSchema.changeset(%{
        identity_id: KlassHero.AccountsFixtures.unconfirmed_user_fixture(intended_roles: [:provider]).id,
        business_name: "IdV Repo Test #{System.unique_integer([:positive])}"
      })
      |> Repo.insert()

    to_string(schema.id)
  end

  describe "create/1 + get_by_session_id/1" do
    test "round-trips a processing record, preserving status and outcome" do
      iv = IdentityVerification.new(%{provider_id: provider_id(), stripe_session_id: "vs_abc"})

      assert {:ok, created} = IdentityVerificationRepository.create(iv)
      assert created.stripe_session_id == "vs_abc"
      assert created.status == :processing
      assert created.outcome == nil

      assert {:ok, fetched} = IdentityVerificationRepository.get_by_session_id("vs_abc")
      assert fetched.id == created.id
      assert fetched.status == :processing
    end

    test "round-trips a verified+pass outcome with its verified_at" do
      iv =
        %{provider_id: provider_id(), stripe_session_id: "vs_pass"}
        |> IdentityVerification.new()
        |> IdentityVerification.mark_verified(%{day: 1, month: 1, year: 1990}, ~D[2026-06-18])

      assert {:ok, _} = IdentityVerificationRepository.create(iv)
      assert {:ok, fetched} = IdentityVerificationRepository.get_by_session_id("vs_pass")
      assert fetched.status == :verified
      assert fetched.outcome == :pass
      assert %DateTime{} = fetched.verified_at
    end

    test "round-trips a failed outcome with its reason" do
      iv =
        %{provider_id: provider_id(), stripe_session_id: "vs_minor"}
        |> IdentityVerification.new()
        |> IdentityVerification.mark_verified(%{day: 1, month: 1, year: 2015}, ~D[2026-06-18])

      assert {:ok, _} = IdentityVerificationRepository.create(iv)
      assert {:ok, fetched} = IdentityVerificationRepository.get_by_session_id("vs_minor")
      assert fetched.outcome == :fail
      assert fetched.failure_reason == "under_18"
    end

    test "returns :not_found for an unknown session id" do
      assert {:error, :not_found} = IdentityVerificationRepository.get_by_session_id("vs_nope")
    end
  end

  describe "get_latest_by_provider/1" do
    test "returns the most recently created record for the provider (retries append)" do
      pid = provider_id()

      {:ok, _first} =
        %{provider_id: pid, stripe_session_id: "vs_old"}
        |> IdentityVerification.new()
        |> IdentityVerification.mark_requires_input()
        |> IdentityVerificationRepository.create()

      {:ok, latest} =
        %{provider_id: pid, stripe_session_id: "vs_new"}
        |> IdentityVerification.new()
        |> IdentityVerificationRepository.create()

      assert {:ok, fetched} = IdentityVerificationRepository.get_latest_by_provider(pid)
      assert fetched.id == latest.id
      assert fetched.stripe_session_id == "vs_new"
    end

    test "returns :not_found when the provider has no identity verifications" do
      assert {:error, :not_found} = IdentityVerificationRepository.get_latest_by_provider(provider_id())
    end
  end

  describe "update/1" do
    test "advances a processing record to a terminal outcome" do
      pid = provider_id()

      {:ok, created} =
        IdentityVerificationRepository.create(
          IdentityVerification.new(%{provider_id: pid, stripe_session_id: "vs_upd"})
        )

      updated = IdentityVerification.mark_canceled(created)
      assert {:ok, _} = IdentityVerificationRepository.update(updated)

      assert {:ok, fetched} = IdentityVerificationRepository.get_by_session_id("vs_upd")
      assert fetched.status == :canceled
      assert fetched.outcome == :fail
    end
  end
end
