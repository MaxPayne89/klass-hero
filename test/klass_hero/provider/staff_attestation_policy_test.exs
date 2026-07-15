defmodule KlassHero.Provider.StaffAttestationPolicyTest do
  @moduledoc """
  Version policy and the re-attestation rule for the Staff Compliance Declaration.
  """

  use ExUnit.Case, async: true

  alias KlassHero.Provider.SignedAgreement
  alias KlassHero.Provider.StaffAttestationPolicy

  defp attestation(version) do
    {:ok, a} =
      SignedAgreement.new(%{
        provider_id: Ecto.UUID.generate(),
        signed_by_name: "Jane Smith",
        kind: :staff_attestation,
        version: version
      })

    a
  end

  test "current_version/0 is provisional until legal sign-off" do
    assert StaffAttestationPolicy.current_version() == "1.0-provisional"
  end

  describe "attestation_satisfied?/1" do
    test "a current-version attestation satisfies; an older one or none does not" do
      cases = [
        {attestation(StaffAttestationPolicy.current_version()), true},
        {attestation("0.9"), false},
        {nil, false}
      ]

      for {input, expected} <- cases do
        assert StaffAttestationPolicy.attestation_satisfied?(input) == expected,
               "expected #{inspect(input)} -> #{expected}"
      end
    end
  end
end
