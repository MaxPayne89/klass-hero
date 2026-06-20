defmodule KlassHero.Provider.Adapters.Driven.Persistence.Repositories.VettingCaseRepositoryTest do
  use KlassHero.DataCase, async: true

  import Ecto.Query

  alias KlassHero.Provider.Adapters.Driven.Persistence.Repositories.VettingCaseRepository
  alias KlassHero.Provider.Adapters.Driven.Persistence.Schemas.ProviderProfileSchema
  alias KlassHero.Provider.Adapters.Driven.Persistence.Schemas.VettingCaseSchema
  alias KlassHero.Provider.Domain.Models.VettingCase
  alias KlassHero.Repo

  defp provider_id(attrs \\ %{}) do
    base = %{
      identity_id: KlassHero.AccountsFixtures.unconfirmed_user_fixture(intended_roles: [:provider]).id,
      business_name: "Repo Test #{System.unique_integer([:positive])}"
    }

    {:ok, schema} =
      %ProviderProfileSchema{}
      |> ProviderProfileSchema.changeset(Map.merge(base, attrs))
      |> Repo.insert()

    to_string(schema.id)
  end

  describe "create/1 + get_by_provider/1" do
    test "persists a case with its steps and reads it back" do
      pid = provider_id()
      case_ = VettingCase.new_for_track(pid, :individual)

      assert {:ok, created} = VettingCaseRepository.create(case_)
      assert created.lifecycle == :not_started
      assert Enum.map(created.steps, & &1.key) == [:identity, :experience, :background, :safeguarding]
      assert Enum.all?(created.steps, &(&1.id != nil))

      assert {:ok, loaded} = VettingCaseRepository.get_by_provider(pid)
      assert loaded.id == created.id
      assert Enum.map(loaded.steps, & &1.key) == [:identity, :experience, :background, :safeguarding]
    end

    test "get_by_provider/1 returns :not_found when the provider itself does not exist" do
      assert {:error, :not_found} = VettingCaseRepository.get_by_provider(Ecto.UUID.generate())
    end
  end

  describe "get_by_provider/1 lazy backfill" do
    test "lazily creates and persists a case for an existing individual provider with none" do
      pid = provider_id(%{entity_type: "individual"})

      assert {:ok, created} = VettingCaseRepository.get_by_provider(pid)
      assert created.entity_type == :individual
      assert Enum.map(created.steps, & &1.key) == [:identity, :experience, :background, :safeguarding]
      assert Enum.all?(created.steps, &(&1.id != nil))

      # Second read returns the same persisted case, not a duplicate.
      assert {:ok, reloaded} = VettingCaseRepository.get_by_provider(pid)
      assert reloaded.id == created.id
      assert Repo.aggregate(from(c in VettingCaseSchema, where: c.provider_id == ^pid), :count) == 1
    end

    test "lazily creates the business track for an existing business provider" do
      pid = provider_id(%{entity_type: "business"})

      assert {:ok, created} = VettingCaseRepository.get_by_provider(pid)
      assert created.entity_type == :business
      assert Enum.map(created.steps, & &1.key) == [:business_registration, :insurance]
    end
  end

  describe "update/1" do
    test "persists step status and lifecycle changes" do
      pid = provider_id()
      reviewer = KlassHero.AccountsFixtures.user_fixture(%{is_admin: true})
      {:ok, created} = VettingCaseRepository.create(VettingCase.new_for_track(pid, :individual))

      {:ok, advanced} = VettingCase.approve_step(created, :experience, reviewer.id, Ecto.UUID.generate())
      assert {:ok, _} = VettingCaseRepository.update(advanced)

      {:ok, loaded} = VettingCaseRepository.get_by_provider(pid)
      assert loaded.lifecycle == :in_progress
      assert Enum.find(loaded.steps, &(&1.key == :experience)).status == :approved
    end
  end
end
