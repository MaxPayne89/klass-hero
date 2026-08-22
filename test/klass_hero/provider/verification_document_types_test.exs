defmodule KlassHero.Provider.VerificationDocumentTypesTest do
  @moduledoc """
  The per-track document-type whitelist is single-sourced from the vetting track catalog,
  so a new document step is offered for upload automatically and no stale hardcoded list can
  drift from the engine.
  """
  use ExUnit.Case, async: true

  alias KlassHero.Provider
  alias KlassHero.Provider.DocumentType
  alias KlassHero.Provider.VerificationDocument

  describe "valid_document_types/1" do
    test "the individual track exposes exactly its document steps, in order" do
      assert Provider.valid_document_types(:individual) ==
               ~w(experience_validation background_check video_screening safeguarding_certificate)
    end

    test "every individual-track type is castable on the write path" do
      for type <- Provider.valid_document_types(:individual) do
        assert {:ok, _} = DocumentType.cast(type)
      end
    end
  end

  describe "generic_document_types/1" do
    # Only steps with no dedicated submission surface belong in the generic picker.
    @cases [
      # video is :widget (dedicated video uploader), so it drops out of the generic picker
      {:individual, ~w(experience_validation background_check safeguarding_certificate)},
      # business_registration is :command, insurance is :widget — both have dedicated surfaces
      {:business, []}
    ]

    test "returns only the non-dedicated document steps, in track order" do
      for {entity_type, expected} <- @cases do
        assert Provider.generic_document_types(entity_type) == expected,
               "generic_document_types(#{inspect(entity_type)}) should be #{inspect(expected)}"
      end
    end
  end

  describe "dedicated_command?/1" do
    @cases [
      {"business_registration", true},
      {"insurance_certificate", false},
      {"video_screening", false},
      {"experience_validation", false},
      {"id_document", false}
    ]

    test "is true only for a type whose step has a dedicated command" do
      for {type, expected} <- @cases do
        assert VerificationDocument.dedicated_command?(type) == expected,
               "dedicated_command?(#{inspect(type)}) should be #{inspect(expected)}"
      end
    end
  end
end
