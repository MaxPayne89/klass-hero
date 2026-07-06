defmodule KlassHero.Provider.Verification.OutOfEnumDocumentTypeTest do
  @moduledoc """
  Regression for #1026: a `verification_documents` row whose `document_type` is
  outside the current enum (legacy data from a narrowed enum) must not 500 the
  read path. Loads must degrade to an `:unknown` sentinel instead of raising.
  """
  use KlassHero.DataCase, async: true

  alias KlassHero.Provider
  alias KlassHero.ProviderFixtures

  describe "get_provider_verification_documents/1 with an out-of-enum document_type" do
    setup do
      provider = ProviderFixtures.provider_profile_fixture()

      # Bypass the app's write path (create_changeset -> Ecto cast rejects this):
      # a raw INSERT reproduces the unguarded stale row that caused the crash.
      Repo.query!(
        """
        INSERT INTO verification_documents
          (id, provider_id, document_type, file_url, original_filename, status, inserted_at, updated_at)
        VALUES
          (gen_random_uuid(), $1, 'safeguarding_certificate', 'verification-docs/legacy.pdf',
           'legacy.pdf', 'pending', now(), now())
        """,
        [Ecto.UUID.dump!(provider.id)]
      )

      %{provider: provider}
    end

    test "returns the row as :unknown instead of raising", %{provider: provider} do
      assert {:ok, [doc]} = Provider.get_provider_verification_documents(provider.id)
      assert doc.document_type == :unknown
    end
  end
end
