defmodule KlassHero.Provider.Verification.DocumentReviewTest do
  use KlassHero.DataCase, async: false

  alias KlassHero.AccountsFixtures
  alias KlassHero.Provider.VerificationDocument
  alias KlassHero.Provider.Vetting
  alias KlassHero.ProviderFixtures

  setup do
    provider = ProviderFixtures.provider_profile_fixture()
    admin = AccountsFixtures.user_fixture(%{is_admin: true})
    doc = ProviderFixtures.verification_document_fixture(provider_id: provider.id)
    %{provider: provider, admin: admin, document: doc}
  end

  # The refresh nudge is sent after the review commits, never before and never without
  # one. `VerificationLive` refetches when it arrives, so a nudge for a review that did
  # not land would show the reviewer stale state and imply their click did nothing.
  describe "refresh broadcast" do
    setup %{provider: provider} do
      Phoenix.PubSub.subscribe(KlassHero.PubSub, "provider:#{provider.id}:verification_updated")
      :ok
    end

    test "a committed review nudges the provider's open page", %{admin: admin, document: doc} do
      assert {:ok, _approved} = KlassHero.Provider.approve_verification_document(doc.id, admin.id)

      assert_receive :verification_updated
    end

    test "a rejected-outright review nudges nobody", %{admin: admin, document: doc} do
      assert {:ok, _approved} = KlassHero.Provider.approve_verification_document(doc.id, admin.id)
      assert_receive :verification_updated

      # Already approved — the review never happens, so nothing changed to announce.
      assert {:error, _} = KlassHero.Provider.approve_verification_document(doc.id, admin.id)

      refute_receive :verification_updated, 100
    end
  end

  describe "ApproveVerificationDocument.execute/1" do
    test "approves pending document", %{admin: admin, document: doc} do
      assert {:ok, approved} = KlassHero.Provider.approve_verification_document(doc.id, admin.id)
      assert approved.status == :approved
      assert approved.reviewed_by_id == admin.id
      assert %DateTime{} = approved.reviewed_at
    end

    test "persists approved document to database", %{admin: admin, document: doc} do
      assert {:ok, _approved} = KlassHero.Provider.approve_verification_document(doc.id, admin.id)

      # Verify the document was persisted
      reloaded = KlassHero.Repo.get(VerificationDocument, doc.id)
      assert reloaded.status == :approved
      assert reloaded.reviewed_by_id == admin.id
    end

    test "fails for non-existent document", %{admin: admin} do
      assert {:error, :not_found} =
               KlassHero.Provider.approve_verification_document(Ecto.UUID.generate(), admin.id)
    end

    test "fails for already approved document", %{admin: admin, document: doc} do
      # First approval
      assert {:ok, _approved} = KlassHero.Provider.approve_verification_document(doc.id, admin.id)

      # Second approval should fail
      assert {:error, :document_not_pending} =
               KlassHero.Provider.approve_verification_document(doc.id, admin.id)
    end

    test "fails for already rejected document", %{admin: admin, document: doc} do
      # First reject
      assert {:ok, _rejected} =
               KlassHero.Provider.reject_verification_document(doc.id, admin.id, "Invalid")

      # Then try to approve should fail
      assert {:error, :document_not_pending} =
               KlassHero.Provider.approve_verification_document(doc.id, admin.id)
    end

    # Asserts the OUTCOME, not the mechanism: approving a document must advance the step
    # that consumes its document_type, in the same transaction. Asserting the event alone
    # passed even while the handler that read it no-opped (#1142).
    test "advances the vetting step that consumes the document type", %{
      provider: provider,
      admin: admin,
      document: doc
    } do
      assert {:ok, _approved} = KlassHero.Provider.approve_verification_document(doc.id, admin.id)

      step = experience_step(provider.id)
      assert step.status == :approved
      assert step.evidence_ref == doc.id
      assert step.reviewed_by_id == admin.id
    end
  end

  describe "RejectVerificationDocument.execute/1" do
    test "rejects pending document with reason", %{admin: admin, document: doc} do
      assert {:ok, rejected} =
               KlassHero.Provider.reject_verification_document(
                 doc.id,
                 admin.id,
                 "Document is expired"
               )

      assert rejected.status == :rejected
      assert rejected.rejection_reason == "Document is expired"
      assert rejected.reviewed_by_id == admin.id
      assert %DateTime{} = rejected.reviewed_at
    end

    test "persists rejected document to database", %{admin: admin, document: doc} do
      assert {:ok, _rejected} =
               KlassHero.Provider.reject_verification_document(doc.id, admin.id, "Unclear image")

      # Verify the document was persisted
      reloaded = KlassHero.Repo.get(VerificationDocument, doc.id)
      assert reloaded.status == :rejected
      assert reloaded.rejection_reason == "Unclear image"
    end

    test "requires rejection reason", %{admin: admin, document: doc} do
      assert {:error, :reason_required} =
               KlassHero.Provider.reject_verification_document(doc.id, admin.id, "")
    end

    test "requires non-nil rejection reason", %{admin: admin, document: doc} do
      assert {:error, :reason_required} =
               KlassHero.Provider.reject_verification_document(doc.id, admin.id, nil)
    end

    test "fails for non-existent document", %{admin: admin} do
      assert {:error, :not_found} =
               KlassHero.Provider.reject_verification_document(
                 Ecto.UUID.generate(),
                 admin.id,
                 "Invalid"
               )
    end

    test "fails for already rejected document", %{admin: admin, document: doc} do
      # First rejection
      assert {:ok, _rejected} =
               KlassHero.Provider.reject_verification_document(
                 doc.id,
                 admin.id,
                 "First rejection"
               )

      # Second rejection should fail
      assert {:error, :document_not_pending} =
               KlassHero.Provider.reject_verification_document(
                 doc.id,
                 admin.id,
                 "Second rejection"
               )
    end

    test "fails for already approved document", %{admin: admin, document: doc} do
      # First approve
      assert {:ok, _approved} = KlassHero.Provider.approve_verification_document(doc.id, admin.id)

      # Then try to reject should fail
      assert {:error, :document_not_pending} =
               KlassHero.Provider.reject_verification_document(doc.id, admin.id, "Too late")
    end

    # The reset is the only step-level outcome of a rejection. Do NOT assert via
    # Vetting.checklist_for_provider/1 — that read derives :rejected from the document
    # evidence, not the step, so it would pass even with the reset gone.
    #
    # Two documents are needed: reject_verification_document/3 requires a :pending document,
    # so the approved one cannot also be the rejected one.
    test "resets the vetting step when a document of an approved type is rejected", %{
      provider: provider,
      admin: admin,
      document: doc
    } do
      assert {:ok, _approved} = KlassHero.Provider.approve_verification_document(doc.id, admin.id)

      # Pin the intermediate state. Without it this test is vacuous: a dead handler leaves the
      # step at its initial :not_started, which is also the post-reset value asserted below.
      assert experience_step(provider.id).status == :approved

      second = ProviderFixtures.verification_document_fixture(provider_id: provider.id)

      assert {:ok, _rejected} =
               KlassHero.Provider.reject_verification_document(second.id, admin.id, "Expired document")

      step = experience_step(provider.id)
      assert step.status == :not_started
      assert step.evidence_ref == nil
      assert step.reviewed_by_id == nil
    end
  end

  # The vetting step fed by this file's default document type ("experience_validation" on the
  # individual track). Re-read from the case each time — the handler writes it out of band.
  defp experience_step(provider_id) do
    assert {:ok, case_} = Vetting.get_case_for_provider(provider_id)
    Enum.find(case_.steps, &(&1.key == :experience))
  end
end
