defmodule KlassHero.Provider.Domain.Models.VerificationDocument do
  @moduledoc """
  Domain model for provider verification documents.

  Represents a document submitted by a provider for verification review.
  Documents go through a simple lifecycle: pending -> approved | rejected

  This is a pure domain model with no persistence or infrastructure concerns.
  Validation happens at the domain boundary.

  ## Fields

  - `id` - Unique identifier for the document
  - `provider_profile_id` - Reference to the provider who submitted the document
  - `document_type` - Type of document (business_registration, insurance_certificate, etc.)
  - `file_url` - Storage key for the uploaded file (private bucket path, not a URL)
  - `original_filename` - Original name of the uploaded file
  - `status` - Document status (:pending, :approved, :rejected)
  - `rejection_reason` - Reason for rejection (only when status is :rejected)
  - `reviewed_by_id` - ID of the admin who reviewed the document
  - `reviewed_at` - When the document was reviewed
  - `inserted_at` - When the record was created
  - `updated_at` - When the record was last updated

  ## Note on Field Naming

  The domain model uses `provider_profile_id` for clarity about its semantic meaning.
  The persistence layer (schema/mapper) translates this to `provider_id` which references
  the `providers` database table.
  """

  use KlassHero.Shared.Domain.Models.PersistenceSupport

  @valid_statuses [:pending, :approved, :rejected]
  @valid_document_types ~w(business_registration insurance_certificate id_document tax_certificate other)

  @doc """
  Returns the list of valid document statuses.
  """
  def valid_statuses, do: @valid_statuses

  @doc """
  Returns the list of valid document types.
  """
  def valid_document_types, do: @valid_document_types

  @enforce_keys [:id, :provider_profile_id, :document_type, :file_url, :original_filename]
  defstruct [
    :id,
    :provider_profile_id,
    :document_type,
    :file_url,
    :original_filename,
    :rejection_reason,
    :reviewed_by_id,
    :reviewed_at,
    :inserted_at,
    :updated_at,
    status: :pending
  ]

  @type status :: :pending | :approved | :rejected

  @type t :: %__MODULE__{
          id: String.t(),
          provider_profile_id: String.t(),
          document_type: String.t(),
          file_url: String.t(),
          original_filename: String.t(),
          status: status(),
          rejection_reason: String.t() | nil,
          reviewed_by_id: String.t() | nil,
          reviewed_at: DateTime.t() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  @doc """
  Creates a new VerificationDocument with validation.

  Business Rules:
  - id must be present and non-empty
  - provider_profile_id must be present and non-empty
  - document_type must be one of the valid types
  - file_url must be present and non-empty
  - original_filename must be present and non-empty
  - status is always set to :pending (constructor enforces initial state invariant)

  Returns:
  - `{:ok, document}` if all validations pass
  - `{:error, [keyword_list]}` with validation errors
  """
  def new(attrs) when is_map(attrs) do
    case validate(attrs) do
      [] ->
        now = DateTime.utc_now() |> DateTime.truncate(:second)

        {:ok,
         %__MODULE__{
           id: attrs.id,
           provider_profile_id: attrs.provider_profile_id,
           document_type: attrs.document_type,
           file_url: attrs.file_url,
           original_filename: attrs.original_filename,
           status: :pending,
           inserted_at: now,
           updated_at: now
         }}

      errors ->
        {:error, errors}
    end
  end

  @doc """
  Approve a pending document.

  Sets the document status to :approved and records the reviewer information.

  Returns:
  - `{:ok, document}` with updated status and review info
  - `{:error, :invalid_reviewer}` if reviewer_id is nil, empty, or non-binary
  - `{:error, :document_not_pending}` if document is not in pending status
  """
  def approve(%__MODULE__{status: :pending} = doc, reviewer_id)
      when is_binary(reviewer_id) and byte_size(reviewer_id) > 0 do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    {:ok,
     %{
       doc
       | status: :approved,
         reviewed_by_id: reviewer_id,
         reviewed_at: now,
         updated_at: now
     }}
  end

  # Trigger: pending doc but reviewer_id is nil, empty, or non-binary
  # Why: domain boundary validates caller identity before state transition
  # Outcome: rejects the operation with a specific error
  def approve(%__MODULE__{status: :pending}, _reviewer_id) do
    {:error, :invalid_reviewer}
  end

  def approve(%__MODULE__{}, _reviewer_id) do
    {:error, :document_not_pending}
  end

  @doc """
  Reject a pending document with a reason.

  Sets the document status to :rejected and records the reviewer information
  along with the rejection reason.

  Returns:
  - `{:ok, document}` with updated status, review info, and rejection reason
  - `{:error, :invalid_review_params}` if reviewer_id or reason is nil, empty, or non-binary
  - `{:error, :document_not_pending}` if document is not in pending status
  """
  def reject(%__MODULE__{status: :pending} = doc, reviewer_id, reason)
      when is_binary(reviewer_id) and byte_size(reviewer_id) > 0 and is_binary(reason) and byte_size(reason) > 0 do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    {:ok,
     %{
       doc
       | status: :rejected,
         rejection_reason: reason,
         reviewed_by_id: reviewer_id,
         reviewed_at: now,
         updated_at: now
     }}
  end

  # Trigger: pending doc but reviewer_id or reason is nil, empty, or non-binary
  # Why: domain boundary validates both caller identity and rejection reason
  # Outcome: rejects the operation with a specific error
  def reject(%__MODULE__{status: :pending}, _reviewer_id, _reason) do
    {:error, :invalid_review_params}
  end

  def reject(%__MODULE__{}, _reviewer_id, _reason) do
    {:error, :document_not_pending}
  end

  # Validation functions

  defp validate(attrs) do
    []
    |> validate_required(attrs, :id)
    |> validate_required(attrs, :provider_profile_id)
    |> validate_required(attrs, :document_type)
    |> validate_required(attrs, :file_url)
    |> validate_required(attrs, :original_filename)
    |> validate_document_type(attrs)
  end

  defp validate_required(errors, attrs, key) do
    case Map.get(attrs, key) do
      nil -> [{key, "is required"} | errors]
      "" -> [{key, "is required"} | errors]
      value when is_binary(value) and byte_size(value) > 0 -> errors
      _ -> errors
    end
  end

  defp validate_document_type(errors, attrs) do
    case Map.get(attrs, :document_type) do
      nil ->
        # Already caught by validate_required
        errors

      type when type in @valid_document_types ->
        errors

      _ ->
        [{:document_type, "must be one of: #{inspect(@valid_document_types)}"} | errors]
    end
  end
end
