defmodule KlassHero.Provider.VerificationDocumentTypesTest do
  @moduledoc """
  The per-track document-type whitelist is single-sourced from the vetting track catalog,
  so a new document step is offered for upload automatically and no stale hardcoded list can
  drift from the engine.
  """
  use ExUnit.Case, async: true

  alias KlassHero.Provider
  alias KlassHero.Provider.Types.DocumentType

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
end
