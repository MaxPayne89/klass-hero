defmodule KlassHero.Shared.Adapters.Driven.Persistence.RepositoryHelpersTest.IdentityMapper do
  @moduledoc """
  Minimal schema→domain mapper for exercising `RepositoryHelpers`' mapper-taking
  variants. Every context is now schema-as-struct (no `to_domain` mappers ship in
  lib), so the "domain" struct is the schema itself — identity is the honest mapping.
  """
  def to_domain(struct), do: struct
end

defmodule KlassHero.Shared.Adapters.Driven.Persistence.RepositoryHelpersTest do
  use KlassHero.DataCase, async: true

  import Ecto.Query
  import ExUnit.CaptureLog

  # RepositoryHelpers is generic infra; the choice of schema is incidental. We use
  # the flattened Provider schema plus a local identity mapper (see IdentityMapper
  # above) since no context ships a to_domain mapper post-flatten.
  alias KlassHero.Provider.ProviderProfile
  alias KlassHero.Shared.Adapters.Driven.Persistence.RepositoryHelpers
  alias KlassHero.Shared.Adapters.Driven.Persistence.RepositoryHelpersTest.IdentityMapper

  @mapper IdentityMapper

  describe "get_by_id/3" do
    test "returns {:ok, domain_struct} when record exists" do
      profile = KlassHero.ProviderFixtures.provider_profile_fixture()

      assert {:ok, domain} = RepositoryHelpers.get_by_id(ProviderProfile, profile.id, @mapper)
      assert domain.id == profile.id
      assert domain.business_name == profile.business_name
    end

    test "returns {:error, :not_found} when record does not exist" do
      assert {:error, :not_found} =
               RepositoryHelpers.get_by_id(ProviderProfile, Ecto.UUID.generate(), @mapper)
    end
  end

  describe "get_schema_by_uuid/2" do
    test "returns {:ok, schema} when record exists" do
      profile = KlassHero.ProviderFixtures.provider_profile_fixture()

      assert {:ok, schema} = RepositoryHelpers.get_schema_by_uuid(ProviderProfile, profile.id)
      assert to_string(schema.id) == profile.id
    end

    test "returns {:error, :not_found} when the UUID is well-formed but absent" do
      assert {:error, :not_found} =
               RepositoryHelpers.get_schema_by_uuid(ProviderProfile, Ecto.UUID.generate())
    end

    test "returns {:error, :not_found} for a malformed UUID instead of crashing" do
      assert {:error, :not_found} = RepositoryHelpers.get_schema_by_uuid(ProviderProfile, "not-a-uuid")
    end
  end

  describe "get_by_uuid/3" do
    test "returns {:ok, domain_struct} when record exists" do
      profile = KlassHero.ProviderFixtures.provider_profile_fixture()

      assert {:ok, domain} = RepositoryHelpers.get_by_uuid(ProviderProfile, profile.id, @mapper)
      assert domain.id == profile.id
    end

    test "returns {:error, :not_found} for a malformed UUID instead of crashing" do
      assert {:error, :not_found} =
               RepositoryHelpers.get_by_uuid(ProviderProfile, "not-a-uuid", @mapper)
    end
  end

  describe "fetch_one/2" do
    test "returns {:ok, domain_struct} for a query that matches one record" do
      profile = KlassHero.ProviderFixtures.provider_profile_fixture()
      query = from(p in ProviderProfile, where: p.id == ^profile.id)

      assert {:ok, domain} = RepositoryHelpers.fetch_one(query, @mapper)
      assert domain.id == profile.id
    end

    test "returns {:error, :not_found} when the query matches nothing" do
      query = from(p in ProviderProfile, where: p.id == ^Ecto.UUID.generate())

      assert {:error, :not_found} = RepositoryHelpers.fetch_one(query, @mapper)
    end
  end

  describe "log_validation_error/2" do
    test "logs a warning and returns :ok" do
      changeset =
        %ProviderProfile{}
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
