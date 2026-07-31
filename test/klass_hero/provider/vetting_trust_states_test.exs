defmodule KlassHero.Provider.VettingTrustStatesTest do
  @moduledoc """
  Covers `Vetting.get_trust_states/1` — the batch read behind the program-card
  trust mark.

  The rule under test exists because two facts can disagree:
  `providers.verified` is the published boundary fact (an admin can flip it
  straight from Backpex, bypassing the engine entirely), while
  `vetting_cases.lifecycle` is the engine's internal progress. The published
  fact wins in both directions — an admin-verified provider is never shown as
  mid-vetting, and an admin-unverified one is never shown as verified no matter
  how far its case got.
  """
  use KlassHero.DataCase, async: true

  import KlassHero.ProviderFixtures

  alias KlassHero.Provider.Vetting
  alias KlassHero.Provider.VettingCase
  alias KlassHero.Repo

  # {providers.verified, vetting_cases.lifecycle, expected trust state}
  @precedence [
    {true, :not_started, :verified},
    {true, :in_progress, :verified},
    {true, :verified, :verified},
    {false, :in_progress, :in_progress},
    {false, :verified, :unverified},
    {false, :not_started, :unverified}
  ]

  describe "get_trust_states/1 precedence" do
    for {verified, lifecycle, expected} <- @precedence do
      test "verified=#{verified} + lifecycle=#{lifecycle} => #{expected}" do
        verified = unquote(verified)
        lifecycle = unquote(lifecycle)
        expected = unquote(expected)

        provider = provider_profile_fixture(verified: verified)
        put_lifecycle(provider.id, lifecycle)

        assert %{provider.id => expected} == Vetting.get_trust_states([provider.id]),
               "expected verified=#{verified} + lifecycle=#{lifecycle} to read as #{expected}"
      end
    end
  end

  describe "get_trust_states/1 edges" do
    test "returns an empty map for an empty list without querying" do
      assert %{} == Vetting.get_trust_states([])
    end

    test "omits ids that match no provider" do
      assert %{} == Vetting.get_trust_states([Ecto.UUID.generate()])
    end

    test "a provider with no vetting case at all reads as unverified" do
      provider = provider_profile_fixture(verified: false)

      assert %{provider.id => :unverified} == Vetting.get_trust_states([provider.id])
    end

    test "a verified provider with no vetting case still reads as verified" do
      provider = provider_profile_fixture(verified: true)

      assert %{provider.id => :verified} == Vetting.get_trust_states([provider.id])
    end

    test "resolves a mixed batch in one call" do
      verified = provider_profile_fixture(verified: true)
      pending = provider_profile_fixture(verified: false)
      put_lifecycle(pending.id, :in_progress)
      unverified = provider_profile_fixture(verified: false)

      assert %{
               verified.id => :verified,
               pending.id => :in_progress,
               unverified.id => :unverified
             } == Vetting.get_trust_states([verified.id, pending.id, unverified.id])
    end
  end

  # Drives the case straight to the lifecycle under test. The engine recomputes
  # `lifecycle` from its steps, so going through `approve_step` would couple these
  # cases to track composition — this read only cares about the stored value.
  defp put_lifecycle(provider_id, lifecycle) do
    case_ = vetting_case_fixture(provider_id: provider_id)

    VettingCase
    |> Repo.get!(case_.id)
    |> Ecto.Changeset.change(lifecycle: lifecycle)
    |> Repo.update!()
  end
end
