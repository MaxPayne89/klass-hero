defmodule KlassHero.Provider.Adapters.Driven.Persistence.Mappers.VerificationStepMapper do
  @moduledoc """
  Bidirectional mapping between `VerificationStep` domain models and `VerificationStepSchema`
  Ecto structs.

  Encodes the domain's typed fields for storage: `key`/`status` atoms ↔ strings, the
  `completed_via` tuple ↔ a `"kind:detail"` string (e.g. `{:document, "background_check"}` ↔
  `"document:background_check"`), and the `requires` atom list ↔ a string array.
  """

  import KlassHero.Shared.Adapters.Driven.Persistence.MapperHelpers, only: [maybe_add_id: 2]

  alias KlassHero.Provider.Adapters.Driven.Persistence.Schemas.VerificationStepSchema
  alias KlassHero.Provider.Domain.Models.VerificationStep

  @doc "Converts a VerificationStepSchema to a domain VerificationStep."
  def to_domain(%VerificationStepSchema{} = schema) do
    %VerificationStep{
      id: schema.id && to_string(schema.id),
      vetting_case_id: to_string(schema.vetting_case_id),
      key: String.to_existing_atom(schema.key),
      status: String.to_existing_atom(schema.status),
      completed_via: decode_completed_via(schema.completed_via),
      requires: Enum.map(schema.requires, &String.to_existing_atom/1),
      admin_review?: schema.admin_review,
      evidence_ref: schema.evidence_ref && to_string(schema.evidence_ref),
      rejection_reason: schema.rejection_reason,
      reviewed_by_id: schema.reviewed_by_id && to_string(schema.reviewed_by_id),
      reviewed_at: schema.reviewed_at,
      submitted_at: schema.submitted_at
    }
  end

  @doc "Converts a domain VerificationStep to a VerificationStepSchema attributes map."
  def to_schema(%VerificationStep{} = step) do
    %{
      vetting_case_id: step.vetting_case_id,
      key: Atom.to_string(step.key),
      status: Atom.to_string(step.status),
      completed_via: encode_completed_via(step.completed_via),
      requires: Enum.map(step.requires, &Atom.to_string/1),
      admin_review: step.admin_review?,
      evidence_ref: step.evidence_ref,
      rejection_reason: step.rejection_reason,
      reviewed_by_id: step.reviewed_by_id,
      reviewed_at: step.reviewed_at,
      submitted_at: step.submitted_at
    }
    |> maybe_add_id(step.id)
  end

  defp encode_completed_via({:document, document_type}), do: "document:" <> document_type

  defp decode_completed_via("document:" <> document_type), do: {:document, document_type}
end
