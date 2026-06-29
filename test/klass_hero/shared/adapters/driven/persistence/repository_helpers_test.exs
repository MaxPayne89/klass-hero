defmodule KlassHero.Shared.Adapters.Driven.Persistence.RepositoryHelpersTest do
  use KlassHero.DataCase, async: true

  import Ecto.Query
  import ExUnit.CaptureLog

  # Exercised against a still-DDD context (Provider) that pairs an Ecto schema
  # with a mapper — RepositoryHelpers is generic infra, the choice of schema is
  # incidental. (Accounts was flattened to conventional Phoenix and no longer
  # ships a mapper.)
  alias KlassHero.Provider.Adapters.Driven.Persistence.Mappers.ProviderProfileMapper
  alias KlassHero.Provider.Adapters.Driven.Persistence.Schemas.ProviderProfileSchema
  alias KlassHero.Shared.Adapters.Driven.Persistence.RepositoryHelpers

  describe "get_by_id/3" do
    test "returns {:ok, domain_struct} when record exists" do
      profile = KlassHero.ProviderFixtures.provider_profile_fixture()

      assert {:ok, domain} = RepositoryHelpers.get_by_id(ProviderProfileSchema, profile.id, ProviderProfileMapper)
      assert domain.id == profile.id
      assert domain.business_name == profile.business_name
    end

    test "returns {:error, :not_found} when record does not exist" do
      assert {:error, :not_found} =
               RepositoryHelpers.get_by_id(ProviderProfileSchema, Ecto.UUID.generate(), ProviderProfileMapper)
    end
  end

  describe "get_schema_by_uuid/2" do
    test "returns {:ok, schema} when record exists" do
      profile = KlassHero.ProviderFixtures.provider_profile_fixture()

      assert {:ok, schema} = RepositoryHelpers.get_schema_by_uuid(ProviderProfileSchema, profile.id)
      assert to_string(schema.id) == profile.id
    end

    test "returns {:error, :not_found} when the UUID is well-formed but absent" do
      assert {:error, :not_found} =
               RepositoryHelpers.get_schema_by_uuid(ProviderProfileSchema, Ecto.UUID.generate())
    end

    test "returns {:error, :not_found} for a malformed UUID instead of crashing" do
      assert {:error, :not_found} = RepositoryHelpers.get_schema_by_uuid(ProviderProfileSchema, "not-a-uuid")
    end
  end

  describe "get_by_uuid/3" do
    test "returns {:ok, domain_struct} when record exists" do
      profile = KlassHero.ProviderFixtures.provider_profile_fixture()

      assert {:ok, domain} = RepositoryHelpers.get_by_uuid(ProviderProfileSchema, profile.id, ProviderProfileMapper)
      assert domain.id == profile.id
    end

    test "returns {:error, :not_found} for a malformed UUID instead of crashing" do
      assert {:error, :not_found} =
               RepositoryHelpers.get_by_uuid(ProviderProfileSchema, "not-a-uuid", ProviderProfileMapper)
    end
  end

  describe "fetch_one/2" do
    test "returns {:ok, domain_struct} for a query that matches one record" do
      profile = KlassHero.ProviderFixtures.provider_profile_fixture()
      query = from(p in ProviderProfileSchema, where: p.id == ^profile.id)

      assert {:ok, domain} = RepositoryHelpers.fetch_one(query, ProviderProfileMapper)
      assert domain.id == profile.id
    end

    test "returns {:error, :not_found} when the query matches nothing" do
      query = from(p in ProviderProfileSchema, where: p.id == ^Ecto.UUID.generate())

      assert {:error, :not_found} = RepositoryHelpers.fetch_one(query, ProviderProfileMapper)
    end
  end

  describe "log_validation_error/2" do
    test "logs a warning and returns :ok" do
      changeset =
        %ProviderProfileSchema{}
        |> Ecto.Changeset.change()
        |> Ecto.Changeset.add_error(:business_name, "is invalid")

      log =
        capture_log(fn ->
          assert :ok = RepositoryHelpers.log_validation_error(changeset, "provider_update_failed")
        end)

      assert log =~ "Repository validation failed"
    end
  end
end
