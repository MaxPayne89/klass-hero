defmodule KlassHero.Provider.CommunityGuidelinesTest do
  @moduledoc """
  Version policy and the re-agreement rule for the Community Guidelines.
  """

  use ExUnit.Case, async: true

  alias KlassHero.Provider.CommunityGuidelines
  alias KlassHero.Provider.SignedAgreement

  defp agreement(version) do
    {:ok, a} =
      SignedAgreement.new(%{provider_id: Ecto.UUID.generate(), signed_by_name: "Lena", version: version})

    a
  end

  test "current_version/0 is the version currently in force" do
    assert CommunityGuidelines.current_version() == "1.0"
  end

  describe "agreement_satisfied?/1" do
    test "a current-version agreement satisfies; an older one or none does not" do
      cases = [
        {agreement(CommunityGuidelines.current_version()), true},
        {agreement("0.9"), false},
        {nil, false}
      ]

      for {input, expected} <- cases do
        assert CommunityGuidelines.agreement_satisfied?(input) == expected,
               "expected #{inspect(input)} -> #{expected}"
      end
    end
  end
end
