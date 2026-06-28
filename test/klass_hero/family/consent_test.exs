defmodule KlassHero.Family.ConsentTest do
  @moduledoc """
  Unit tests for the Consent schema: changeset validation and pure helpers.
  """

  use ExUnit.Case, async: true

  alias KlassHero.Family.Consent

  @valid_attrs %{
    parent_id: Ecto.UUID.generate(),
    child_id: Ecto.UUID.generate(),
    consent_type: "photo_marketing",
    granted_at: ~U[2025-06-15 10:00:00Z]
  }

  defp errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, _opts} -> msg end)
  end

  describe "valid_consent_types/0" do
    test "lists the known types" do
      types = Consent.valid_consent_types()

      assert "provider_data_sharing" in types
      assert "photo_marketing" in types
      refute "photo" in types
    end
  end

  describe "changeset/2 - valid input" do
    test "accepts every valid consent type" do
      for type <- Consent.valid_consent_types() do
        assert Consent.changeset(%Consent{}, %{@valid_attrs | consent_type: type}).valid?,
               "expected consent_type #{inspect(type)} to be valid"
      end
    end
  end

  describe "changeset/2 - validation errors" do
    for field <- [:parent_id, :child_id, :consent_type, :granted_at] do
      test "is invalid without #{field}" do
        changeset = Consent.changeset(%Consent{}, Map.delete(@valid_attrs, unquote(field)))

        refute changeset.valid?
        assert %{unquote(field) => ["can't be blank"]} = errors_on(changeset)
      end
    end

    test "rejects an unknown consent_type" do
      changeset = Consent.changeset(%Consent{}, %{@valid_attrs | consent_type: "typo_consent"})

      refute changeset.valid?
      assert %{consent_type: [_]} = errors_on(changeset)
    end
  end

  describe "active?/1" do
    test "true when withdrawn_at is nil" do
      assert Consent.active?(%Consent{withdrawn_at: nil})
    end

    test "false when withdrawn_at is set" do
      refute Consent.active?(%Consent{withdrawn_at: ~U[2025-07-01 12:00:00Z]})
    end
  end
end
