defmodule KlassHero.Provider.Adapters.Driven.Persistence.Mappers.VerificationDocumentMapper do
  @moduledoc """
  Maps between `VerificationDocument` domain model and Ecto schema.

  DB uses `provider_id`; domain uses `provider_profile_id` — this mapper translates.
  `to_schema/1` excludes `id`, `inserted_at`, `updated_at` (Ecto-managed);
  `id` is conditionally included via `maybe_add_id/2`.
  """

  import KlassHero.Shared.Adapters.Driven.Persistence.MapperHelpers,
    only: [maybe_add_id: 2, maybe_to_string: 1]

  alias KlassHero.Provider.Adapters.Driven.Persistence.Schemas.VerificationDocumentSchema
  alias KlassHero.Provider.Domain.Models.VerificationDocument

  # Valid statuses - ensures atoms exist for String.to_existing_atom/1
  @valid_statuses [:pending, :approved, :rejected]

  @doc "Converts an Ecto `VerificationDocumentSchema` to a domain `VerificationDocument`."
  @spec to_domain(VerificationDocumentSchema.t()) :: VerificationDocument.t()
  def to_domain(%VerificationDocumentSchema{} = schema) do
    %VerificationDocument{
      id: to_string(schema.id),
      provider_profile_id: to_string(schema.provider_id),
      document_type: schema.document_type,
      file_url: schema.file_url,
      original_filename: schema.original_filename,
      status: string_to_status(schema.status),
      rejection_reason: schema.rejection_reason,
      reviewed_by_id: maybe_to_string(schema.reviewed_by_id),
      reviewed_at: schema.reviewed_at,
      inserted_at: schema.inserted_at,
      updated_at: schema.updated_at
    }
  end

  @doc "Converts a domain `VerificationDocument` to a map of attributes for Ecto insert/update."
  @spec to_schema(VerificationDocument.t()) :: map()
  def to_schema(%VerificationDocument{} = domain) do
    %{
      provider_id: domain.provider_profile_id,
      document_type: domain.document_type,
      file_url: domain.file_url,
      original_filename: domain.original_filename,
      status: status_to_string(domain.status),
      rejection_reason: domain.rejection_reason,
      reviewed_by_id: domain.reviewed_by_id,
      reviewed_at: domain.reviewed_at
    }
    |> maybe_add_id(domain.id)
  end

  # Raises on unknown status — corrupt data should surface immediately rather than
  # silently downgrading (e.g. approved docs appearing as pending).
  defp string_to_status(nil), do: :pending

  defp string_to_status(status) when is_binary(status) do
    atom = String.to_existing_atom(status)

    if atom in @valid_statuses do
      atom
    else
      raise "Unknown verification document status in database: #{inspect(status)}"
    end
  rescue
    _e in ArgumentError ->
      reraise "Unrecognized verification document status in database: #{inspect(status)}",
              __STACKTRACE__
  end

  defp status_to_string(nil), do: "pending"
  defp status_to_string(status) when is_atom(status), do: Atom.to_string(status)
end
