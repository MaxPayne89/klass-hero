defmodule KlassHero.Provider.Adapters.Driven.Persistence.Repositories.VettingCaseRepositoryTest do
  use KlassHero.DataCase, async: true

  alias KlassHero.Provider.Adapters.Driven.Persistence.Repositories.VettingCaseRepository
  alias KlassHero.Provider.Adapters.Driven.Persistence.Schemas.ProviderProfileSchema
  alias KlassHero.Provider.Domain.Models.VettingCase
  alias KlassHero.Repo

  defp provider_id do
    {:ok, schema} =
      %ProviderProfileSchema{}
      |> ProviderProfileSchema.changeset(%{
        identity_id: KlassHero.AccountsFixtures.unconfirmed_user_fixture(intended_roles: [:provider]).id,
        business_name: "Repo Test #{System.unique_integer([:positive])}"
      })
      |> Repo.insert()

    to_string(schema.id)
  end

  describe "create/1 + get_by_provider/1" do
    test "persists a case with its steps and reads it back" do
      pid = provider_id()
      case_ = VettingCase.new_for_track(pid, :individual)

      assert {:ok, created} = VettingCaseRepository.create(case_)
      assert created.lifecycle == :not_started
      assert Enum.map(created.steps, & &1.key) == [:experience, :background, :safeguarding]
      assert Enum.all?(created.steps, &(&1.id != nil))

      assert {:ok, loaded} = VettingCaseRepository.get_by_provider(pid)
      assert loaded.id == created.id
      assert Enum.map(loaded.steps, & &1.key) == [:experience, :background, :safeguarding]
    end

    test "get_by_provider/1 returns :not_found for a provider with no case" do
      assert {:error, :not_found} = VettingCaseRepository.get_by_provider(Ecto.UUID.generate())
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
