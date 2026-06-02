defmodule KlassHero.Enrollment.Adapters.Driven.Persistence.Mappers.BulkEnrollmentInviteMapper do
  @moduledoc """
  Maps between BulkEnrollmentInviteSchema and BulkEnrollmentInvite domain model.

  Routes construction through the domain model's `from_persistence/1`
  to enforce `@enforce_keys` invariants.
  """

  alias KlassHero.Enrollment.Adapters.Driven.Persistence.Schemas.BulkEnrollmentInviteSchema
  alias KlassHero.Enrollment.Domain.Models.BulkEnrollmentInvite
  alias KlassHero.Shared.Adapters.Driven.Persistence.MapperHelpers

  @doc """
  Converts a BulkEnrollmentInviteSchema to a BulkEnrollmentInvite domain entity.

  Raises on corrupted data where required keys are missing.
  """
  def to_domain(%BulkEnrollmentInviteSchema{} = schema) do
    attrs = %{
      id: Ecto.UUID.cast!(schema.id),
      program_id: schema.program_id,
      provider_id: schema.provider_id,
      child_first_name: schema.child_first_name,
      child_last_name: schema.child_last_name,
      child_date_of_birth: schema.child_date_of_birth,
      guardian_email: schema.guardian_email,
      guardian_first_name: schema.guardian_first_name,
      guardian_last_name: schema.guardian_last_name,
      guardian2_email: schema.guardian2_email,
      guardian2_first_name: schema.guardian2_first_name,
      guardian2_last_name: schema.guardian2_last_name,
      school_grade: schema.school_grade,
      school_name: schema.school_name,
      medical_conditions: schema.medical_conditions,
      nut_allergy: schema.nut_allergy,
      consent_photo_marketing: schema.consent_photo_marketing,
      consent_photo_social_media: schema.consent_photo_social_media,
      status: schema.status,
      invite_token: schema.invite_token,
      invite_sent_at: schema.invite_sent_at,
      registered_at: schema.registered_at,
      enrolled_at: schema.enrolled_at,
      enrollment_id: schema.enrollment_id,
      error_details: schema.error_details
    }

    MapperHelpers.from_persistence!(BulkEnrollmentInvite, attrs, schema.id)
  end
end
