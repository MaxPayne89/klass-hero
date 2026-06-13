defmodule KlassHero.Provider.Application.Commands.Verification.ApproveVerificationDocument do
  @moduledoc """
  Use case for admin approving a verification document.

  Orchestrates the document approval workflow:
  1. Retrieves the document from the repository
  2. Applies the domain approval logic (which validates the document is pending)
  3. Persists the updated document

  Only documents in :pending status can be approved.
  """

  alias KlassHero.Provider.Domain.Models.VerificationDocument
  alias KlassHero.Shared.Domain.Events.DomainEvent
  alias KlassHero.Shared.EventDispatchHelper

  @query Application.compile_env!(:klass_hero, [
           :provider,
           :for_querying_verification_documents
         ])
  @repository Application.compile_env!(:klass_hero, [
                :provider,
                :for_storing_verification_documents
              ])

  @doc """
  Approves a pending verification document.

  ## Parameters

  - `document_id` - ID of the document to approve
  - `reviewer_id` - ID of the admin performing the review

  ## Returns

  - `{:ok, VerificationDocument.t()}` on success with updated status
  - `{:error, :not_found}` if document doesn't exist
  - `{:error, :document_not_pending}` if document is not in pending status
  """
  def execute(%{document_id: document_id, reviewer_id: reviewer_id}) do
    with {:ok, document} <- @query.get(document_id),
         {:ok, approved} <- VerificationDocument.approve(document, reviewer_id),
         {:ok, persisted} <- @repository.update(approved) do
      dispatch_event(persisted, reviewer_id)
      {:ok, persisted}
    end
  end

  defp dispatch_event(doc, reviewer_id) do
    DomainEvent.new(
      :verification_document_approved,
      doc.id,
      :verification_document,
      %{provider_id: doc.provider_profile_id, reviewer_id: reviewer_id}
    )
    |> EventDispatchHelper.dispatch(KlassHero.Provider)
  end
end
