defmodule KlassHero.Shared.Adapters.Driven.Persistence.RepositoryHelpersTest do
  use KlassHero.DataCase, async: true

  import ExUnit.CaptureLog

  # RepositoryHelpers is generic infra; the choice of schema is incidental. We use
  # the flattened Provider schema for the surviving helpers.
  alias KlassHero.Provider.ProviderProfile
  alias KlassHero.Shared.Adapters.Driven.Persistence.RepositoryHelpers

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
