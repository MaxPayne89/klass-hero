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

  @tracked_sources ["verification_steps", "vetting_cases"]

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

  describe "save_case/1 query budget" do
    test "persists a transition with zero reads and N+1 writes" do
      provider = ProviderFixtures.provider_profile_fixture()
      admin = AccountsFixtures.user_fixture(%{is_admin: true})
      {:ok, case_} = Vetting.get_case_for_provider(provider.id)
      {:ok, approved} = VettingCase.approve_step(case_, :identity, admin.id, Ecto.UUID.generate())

      {result, verbs} = count_tracked_queries(fn -> Vetting.save_case(approved) end)

      assert {:ok, _} = result

      # `verbs` buckets the SQL run against verification_steps + vetting_cases by
      # leading keyword, e.g. %{"SELECT" => 0, "UPDATE" => 7}. Design A's budget is
      # zero reads and one write per step plus one for the case row. Tie UPDATE to
      # the step count (not a literal) so the test survives a track gaining a step.
      assert Map.get(verbs, "SELECT", 0) == 0
      assert Map.get(verbs, "UPDATE", 0) == length(approved.steps) + 1
    end
  end

  describe "save_case/1 side effects" do
    test "bumps updated_at on the persisted steps" do
      provider = ProviderFixtures.provider_profile_fixture()
      admin = AccountsFixtures.user_fixture(%{is_admin: true})
      {:ok, case_} = Vetting.get_case_for_provider(provider.id)
      before_save = DateTime.utc_now()

      {:ok, approved} = VettingCase.approve_step(case_, :identity, admin.id, Ecto.UUID.generate())
      assert {:ok, _} = Vetting.save_case(approved)

      {:ok, reloaded} = Vetting.get_case_for_provider(provider.id)
      identity = Enum.find(reloaded.steps, &(&1.key == :identity))
      assert DateTime.after?(identity.updated_at, before_save)
    end

    test "returns the in-hand case with steps loaded so verified?/1 holds" do
      provider = ProviderFixtures.provider_profile_fixture()
      admin = AccountsFixtures.user_fixture(%{is_admin: true})
      {:ok, case_} = Vetting.get_case_for_provider(provider.id)

      approved =
        Enum.reduce(case_.steps, case_, fn step, acc ->
          {:ok, next} = VettingCase.approve_step(acc, step.key, admin.id, Ecto.UUID.generate())
          next
        end)

      assert {:ok, saved} = Vetting.save_case(approved)
      assert is_list(saved.steps)
      assert VettingCase.verified?(saved)
    end
  end

  # Buckets queries emitted against @tracked_sources during `fun` by leading SQL
  # keyword, so a test can assert the read/write budget of a persistence path.
  defp count_tracked_queries(fun) do
    ref = make_ref()
    test_pid = self()
    handler_id = {:vetting_query_budget, ref}

    :telemetry.attach(
      handler_id,
      [:klass_hero, :repo, :query],
      fn _event, _measurements, metadata, _config ->
        # Ecto emits query telemetry in the calling process (the test process under
        # the sandbox); gating on self() isolates THIS test from concurrent async ones,
        # since :telemetry handlers are process-global.
        if self() == test_pid and metadata.source in @tracked_sources do
          verb = metadata.query |> String.trim_leading() |> String.split(" ", parts: 2) |> hd() |> String.upcase()
          send(test_pid, {ref, verb})
        end
      end,
      nil
    )

    result = fun.()
    :telemetry.detach(handler_id)
    {result, drain_verbs(ref, %{})}
  end

  defp drain_verbs(ref, acc) do
    receive do
      {^ref, verb} -> drain_verbs(ref, Map.update(acc, verb, 1, &(&1 + 1)))
    after
      0 -> acc
    end
  end
end
