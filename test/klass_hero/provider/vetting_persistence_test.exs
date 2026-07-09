defmodule KlassHero.Provider.VettingPersistenceTest do
  @moduledoc """
  DB-backed tests for the `Provider.Vetting` persistence shell: lazy backfill,
  seed, and save round-trip of the VettingCase aggregate.
  """

  use KlassHero.DataCase, async: true

  alias KlassHero.AccountsFixtures
  alias KlassHero.Provider.Vetting
  alias KlassHero.Provider.VettingCase
  alias KlassHero.ProviderFixtures

  describe "get_case_for_provider/1" do
    test "lazily backfills a case on first read for an existing provider" do
      provider = ProviderFixtures.provider_profile_fixture()

      assert {:ok, case_} = Vetting.get_case_for_provider(provider.id)
      assert case_.provider_id == provider.id
      assert case_.entity_type == :individual
      assert case_.lifecycle == :not_started

      assert Enum.map(case_.steps, & &1.key) == [
               :identity,
               :experience,
               :background,
               :video,
               :safeguarding,
               :community_agreement
             ]
    end

    test "returns the same case on subsequent reads (no duplicate)" do
      provider = ProviderFixtures.provider_profile_fixture()
      {:ok, first} = Vetting.get_case_for_provider(provider.id)
      {:ok, second} = Vetting.get_case_for_provider(provider.id)
      assert first.id == second.id
    end

    test "returns :not_found for an unknown provider" do
      assert {:error, :not_found} = Vetting.get_case_for_provider(Ecto.UUID.generate())
    end
  end

  describe "save_case/1 round-trip" do
    test "persists step approvals and the recomputed lifecycle" do
      provider = ProviderFixtures.provider_profile_fixture()
      admin = AccountsFixtures.user_fixture(%{is_admin: true})
      {:ok, case_} = Vetting.get_case_for_provider(provider.id)

      {:ok, approved} = VettingCase.approve_step(case_, :identity, admin.id, Ecto.UUID.generate())
      assert {:ok, _} = Vetting.save_case(approved)

      {:ok, reloaded} = Vetting.get_case_for_provider(provider.id)
      identity = Enum.find(reloaded.steps, &(&1.key == :identity))
      assert identity.status == :approved
      assert reloaded.lifecycle == :in_progress
    end
  end
end
