defmodule KlassHero.Provider.Adapters.Driven.Persistence.ChangeProviderProfileTest do
  use ExUnit.Case, async: true

  import Ecto.Changeset

  alias KlassHero.Factory
  alias KlassHero.Provider.Adapters.Driven.Persistence.ChangeProviderProfile

  describe "execute/2" do
    test "returns valid changeset from domain struct" do
      provider = Factory.build(:provider_profile)
      changeset = ChangeProviderProfile.execute(provider)

      assert changeset.valid?
      assert get_field(changeset, :description) == provider.description
      assert get_field(changeset, :business_name) == provider.business_name
    end

    test "tracks description changes" do
      provider = Factory.build(:provider_profile)
      changeset = ChangeProviderProfile.execute(provider, %{description: "New description"})

      assert get_field(changeset, :description) == "New description"
    end

    test "validates description max length" do
      provider = Factory.build(:provider_profile)
      long_desc = String.duplicate("a", 1001)
      changeset = ChangeProviderProfile.execute(provider, %{description: long_desc})

      refute changeset.valid?
      assert errors_on(changeset)[:description] != nil
    end
  end

  # Extracts changeset errors as a map of field => messages
  defp errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
