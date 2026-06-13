defmodule KlassHero.Provider.Adapters.Driven.Persistence.Schemas.VerificationDocumentSchema do
  @moduledoc """
  Ecto schema for the verification_documents table.

  This is an infrastructure adapter that maps database records to Ecto structs.
  Use VerificationDocumentMapper to convert between VerificationDocumentSchema
  and domain VerificationDocument entities.

  ## Field Name Mapping

  The database uses `provider_id` to reference the `providers` table.
  The domain model uses `provider_profile_id` for semantic clarity.
  The mapper handles this translation.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias KlassHero.Accounts.User
  alias KlassHero.Provider.Adapters.Driven.Persistence.Schemas.ProviderProfileSchema

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "verification_documents" do
    field :document_type, :string
    field :file_url, :string
    field :original_filename, :string
    field :status, :string, default: "pending"
    field :rejection_reason, :string
    field :reviewed_at, :utc_datetime_usec

    belongs_to :provider, ProviderProfileSchema

    belongs_to :reviewed_by, User

    timestamps(type: :utc_datetime_usec)
  end

  @required_fields [:provider_id, :document_type, :file_url, :original_filename]
  # Note: :id is included to allow client-provided UUIDs (common in DDD for domain identity)
  @optional_fields [:id, :status, :rejection_reason, :reviewed_by_id, :reviewed_at]

  @valid_statuses ["pending", "approved", "rejected"]
  @valid_document_types [
    "business_registration",
    "insurance_certificate",
    "id_document",
    "tax_certificate",
    "other"
  ]

  @doc "Changeset for inserting or updating a verification document."
  def changeset(schema, attrs) do
    schema
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_inclusion(:status, @valid_statuses)
    |> validate_inclusion(:document_type, @valid_document_types)
    |> foreign_key_constraint(:provider_id)
    |> foreign_key_constraint(:reviewed_by_id)
  end
end
