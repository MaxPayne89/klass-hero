defmodule KlassHero.Provider.Application.Commands.Verification.DocumentReviewTest do
  use KlassHero.DataCase, async: false

  import KlassHero.EventTestHelper

  alias KlassHero.AccountsFixtures
  alias KlassHero.Provider.VerificationDocument
  alias KlassHero.ProviderFixtures
  alias KlassHero.Shared.Adapters.Driven.Events.TestEventPublisher
  alias KlassHero.Shared.DomainEventBus

  setup do
    setup_test_events()

    # Trigger: EventDispatchHelper dispatches via DomainEventBus, not the publisher port
    # Why: capture events into TestEventPublisher so assert_event_published works
    # Outcome: domain bus events become visible to EventTestHelper assertions
    DomainEventBus.subscribe(KlassHero.Provider, :verification_document_approved, fn event ->
      TestEventPublisher.publish(event)
      :ok
    end)

    DomainEventBus.subscribe(KlassHero.Provider, :verification_document_rejected, fn event ->
      TestEventPublisher.publish(event)
      :ok
    end)

    provider = ProviderFixtures.provider_profile_fixture()
    admin = AccountsFixtures.user_fixture(%{is_admin: true})
    doc = ProviderFixtures.verification_document_fixture(provider_id: provider.id)
    %{provider: provider, admin: admin, document: doc}
  end

  describe "ApproveVerificationDocument.execute/1" do
    test "approves pending document", %{admin: admin, document: doc} do
      assert {:ok, approved} = KlassHero.Provider.approve_verification_document(doc.id, admin.id)
      assert approved.status == :approved
      assert approved.reviewed_by_id == admin.id
      assert approved.reviewed_at != nil
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

    test "dispatches :verification_document_approved domain event", %{admin: admin, document: doc} do
      assert {:ok, approved} = KlassHero.Provider.approve_verification_document(doc.id, admin.id)

      event = assert_event_published(:verification_document_approved)
      assert event.aggregate_id == doc.id
      assert event.payload.provider_id == approved.provider_profile_id
      assert event.payload.reviewer_id == admin.id
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
      assert rejected.reviewed_at != nil
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

    test "dispatches :verification_document_rejected domain event", %{admin: admin, document: doc} do
      assert {:ok, rejected} =
               KlassHero.Provider.reject_verification_document(
                 doc.id,
                 admin.id,
                 "Expired document"
               )

      event = assert_event_published(:verification_document_rejected)
      assert event.aggregate_id == doc.id
      assert event.payload.provider_id == rejected.provider_profile_id
      assert event.payload.reviewer_id == admin.id
    end
  end
end
