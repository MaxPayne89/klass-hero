defmodule KlassHero.Provider.SignedAgreementTest do
  @moduledoc """
  The SignedAgreement evidence model — typed consent behind an auto-approving agreement step
  (Community Standards Agreement today; business staff attestation later, via `kind`).
  Append-only: a re-agreement is a fresh record, never an update.
  """

  use ExUnit.Case, async: true

  alias KlassHero.Provider.SignedAgreement

  describe "new/1" do
    test "builds a community agreement with a generated id and signed_at timestamp" do
      attrs = %{provider_id: Ecto.UUID.generate(), signed_by_name: "Lena Hartmann", version: "1.0"}

      assert {:ok, agreement} = SignedAgreement.new(attrs)
      assert agreement.provider_id == attrs.provider_id
      assert agreement.signed_by_name == "Lena Hartmann"
      assert agreement.version == "1.0"
      assert agreement.kind == :community_agreement
      assert {:ok, _} = Ecto.UUID.cast(agreement.id)
      assert %DateTime{} = agreement.signed_at
    end

    test "trims surrounding whitespace from the signer name" do
      attrs = %{provider_id: Ecto.UUID.generate(), signed_by_name: "  Lena  ", version: "1.0"}
      assert {:ok, %{signed_by_name: "Lena"}} = SignedAgreement.new(attrs)
    end

    test "defaults kind to :community_agreement but accepts an explicit kind" do
      base = %{provider_id: Ecto.UUID.generate(), signed_by_name: "X", version: "1.0"}

      assert {:ok, %{kind: :community_agreement}} = SignedAgreement.new(base)

      assert {:ok, %{kind: :staff_attestation}} =
               SignedAgreement.new(Map.put(base, :kind, :staff_attestation))
    end

    test "rejects a missing or blank required field, one error keyed per field" do
      base = %{provider_id: Ecto.UUID.generate(), signed_by_name: "Lena", version: "1.0"}

      for field <- [:provider_id, :signed_by_name, :version] do
        assert {:error, errors} = SignedAgreement.new(Map.put(base, field, "  ")),
               "blank #{field} should be rejected"

        assert Keyword.has_key?(errors, field)
      end
    end
  end
end
