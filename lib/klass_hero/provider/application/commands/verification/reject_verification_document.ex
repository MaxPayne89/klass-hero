defmodule KlassHero.Provider.Application.Commands.Verification.RejectVerificationDocument do
  @moduledoc """
  Use case for admin rejecting a verification document with a reason.

  Orchestrates the document rejection workflow:
  1. Validates that a rejection reason is provided
  2. Retrieves the document from the repository
  3. Applies the domain rejection logic (which validates the document is pending)
  4. Persists the updated document with rejection reason

  Only documents in :pending status can be rejected.
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
  Rejects a pending verification document with a reason.

  ## Parameters

  - `document_id` - ID of the document to reject
  - `reviewer_id` - ID of the admin performing the review
  - `reason` - Explanation for why the document was rejected (required, non-empty)

  ## Returns

  - `{:ok, VerificationDocument.t()}` on success with updated status and rejection reason
  - `{:error, :reason_required}` if reason is empty or nil
  - `{:error, :not_found}` if document doesn't exist
  - `{:error, :document_not_pending}` if document is not in pending status
  """
  def execute(%{document_id: document_id, reviewer_id: reviewer_id, reason: reason}) do
    with :ok <- validate_reason(reason),
         {:ok, document} <- @query.get(document_id),
         {:ok, rejected} <- VerificationDocument.reject(document, reviewer_id, reason),
         {:ok, persisted} <- @repository.update(rejected) do
      dispatch_event(persisted, reviewer_id)
      {:ok, persisted}
    end
  end

  defp dispatch_event(doc, reviewer_id) do
    DomainEvent.new(
      :verification_document_rejected,
      doc.id,
      :verification_document,
      %{
        provider_id: doc.provider_profile_id,
        reviewer_id: reviewer_id,
        document_type: doc.document_type,
        document_id: doc.id
      }
    )
    |> EventDispatchHelper.dispatch(KlassHero.Provider)
  end

  defp validate_reason(reason) when is_binary(reason) and byte_size(reason) > 0, do: :ok
  defp validate_reason(_), do: {:error, :reason_required}
end
