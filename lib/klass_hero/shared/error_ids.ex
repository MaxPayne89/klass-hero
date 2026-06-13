defmodule KlassHero.Shared.ErrorIds do
  @moduledoc """
  Centralized error IDs for tracking, logging, and support correlation.

  Error IDs use dotted notation: `context.domain.action.type`

  ## Error ID Ranges by Bounded Context

  - `program.*` - Program Catalog context errors
  - `participation.*` - Participation context errors (sessions and records)

  ## Usage

  Error IDs are used in structured logging for correlation and debugging.
  They are NOT displayed to end users in flash messages.

  ### Logging Example

      Logger.warning("Program update conflict",
        error_id: ErrorIds.program_update_stale_entry_error(),
        program_id: program.id
      )

  ## Philosophy

  Only domain-level errors that represent expected business scenarios are tracked.
  Infrastructure errors (connection failures, query errors) should crash and be
  handled by the supervision tree - they don't need explicit error IDs.
  """

  @doc "Program not found when attempting to retrieve by ID."
  def program_not_found, do: "program.catalog.detail.not_found"

  @doc "Invalid cursor format when paginating programs."
  def program_pagination_invalid_cursor, do: "program.catalog.paginate.invalid_cursor"

  @doc "Program update failed due to concurrent modification (optimistic lock conflict)."
  def program_update_stale_entry_error, do: "program.catalog.update.stale_entry_error"

  @doc "Program update failed due to constraint violation."
  def program_update_constraint_violation, do: "program.catalog.update.constraint_violation"

  @doc "Program update failed - program not found."
  def program_update_not_found, do: "program.catalog.update.not_found"

  @doc "Session update failed due to concurrent modification (optimistic lock conflict)."
  def session_update_stale_error, do: "participation.session.update.stale"

  @doc "Session update failed due to constraint violation."
  def session_update_constraint_violation, do: "participation.session.update.constraint_violation"

  @doc "Duplicate session error - session already exists for the same program/date/time."
  def session_duplicate_error, do: "participation.session.create.duplicate"

  @doc "Session validation error - changeset validation failed."
  def session_validation_error, do: "participation.session.validation.error"

  @doc "Session create failed due to changeset errors."
  def session_create_failed(%Ecto.Changeset{} = _changeset), do: "participation.session.create.failed"

  @doc "Session update failed due to changeset errors."
  def session_update_failed(%Ecto.Changeset{} = _changeset), do: "participation.session.update.failed"

  @doc "Participation update failed due to concurrent modification (optimistic lock conflict)."
  def participation_update_stale_error, do: "participation.record.update.stale_entry"

  @doc "Participation update failed due to constraint violation."
  def participation_update_constraint_violation, do: "participation.record.update.constraint_violation"

  @doc "Duplicate participation record error - record already exists for session/child combination."
  def participation_duplicate_error, do: "participation.record.create.duplicate"

  @doc "Participation validation error - changeset validation failed."
  def participation_validation_error, do: "participation.record.validation.error"

  @doc "Participation record create failed due to changeset errors."
  def participation_record_create_failed(%Ecto.Changeset{} = _changeset), do: "participation.record.create.failed"

  @doc "Participation record update failed due to changeset errors."
  def participation_record_update_failed(%Ecto.Changeset{} = _changeset), do: "participation.record.update.failed"

  @doc "Duplicate parent profile - identity already has a parent profile."
  def parent_duplicate_identity, do: "identity.parent.create.duplicate_identity"

  @doc "Duplicate provider profile - identity already has a provider profile."
  def provider_duplicate_identity, do: "identity.provider.create.duplicate_identity"

  @doc "Child validation error - changeset validation failed."
  def child_validation_error, do: "identity.child.validation.error"

  @doc "Consent grant failed due to changeset errors."
  def consent_grant_failed, do: "family.consent.grant.failed"

  @doc "Consent withdrawal failed due to changeset errors."
  def consent_withdraw_failed, do: "family.consent.withdraw.failed"

  @doc "Staff member create failed due to changeset errors."
  def staff_member_create_failed, do: "provider.staff_member.create.failed"

  @doc "Provider profile validation failed during create."
  def provider_profile_validation_failed, do: "provider.profile.create.validation_failed"

  @doc "Program create failed due to changeset errors."
  def program_create_failed, do: "program.catalog.create.failed"

  @doc "Program update failed due to changeset errors."
  def program_update_failed, do: "program.catalog.update.failed"
end
