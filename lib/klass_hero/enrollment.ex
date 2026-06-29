defmodule KlassHero.Enrollment do
  @moduledoc """
  Public API for the Enrollment bounded context.

  Manages program enrollments, capacity policies, participant eligibility, and bulk invite flows.
  Follows Ports & Adapters: this module delegates to use cases in the application layer.
  """

  alias KlassHero.Enrollment.Adapters.Driven.Persistence.Schemas.EnrollmentPolicySchema
  alias KlassHero.Enrollment.Adapters.Driving.Events.EventHandlers.NotifyLiveViews

  alias KlassHero.Enrollment.Application.Commands.{
    CancelEnrollmentByAdmin,
    ClaimInvite,
    ConfirmEnrollment,
    CreateEnrollment,
    DeleteInvite,
    ImportEnrollmentCsv,
    InviteSingleParticipant,
    ResendInvite,
    SetParticipantPolicy,
    UpsertEnrollmentPolicy
  }

  alias KlassHero.Enrollment.Application.ParticipantPolicyForm

  alias KlassHero.Enrollment.Application.Queries.{
    CheckEnrollment,
    CheckParticipantEligibility,
    CountMonthlyBookings,
    CountProgramInvites,
    EnrollmentPolicyQueries,
    GetBookingUsageInfo,
    GetEnrollment,
    GetParticipantPolicy,
    ListEnrolledIdentityIds,
    ListParentEnrollments,
    ListPendingEnrollmentsForProvider,
    ListProgramEnrollments,
    ListProgramInvites
  }

  alias KlassHero.Enrollment.Application.SingleInviteForm
  alias KlassHero.Enrollment.Domain.Services.EnrollmentClassifier

  @doc """
  Creates a new enrollment.

  Returns `{:ok, Enrollment.t()}`, `{:error, :duplicate_resource}` if an active enrollment
  already exists for the child/program, or `{:error, term()}` on validation failure.
  """
  def create_enrollment(params) when is_map(params) do
    CreateEnrollment.execute(params)
  end

  @doc """
  Cancels an enrollment by admin action.

  Only pending/confirmed enrollments may be cancelled. Dispatches `enrollment_cancelled`.

  Returns `{:ok, Enrollment.t()}`, `{:error, :not_found}`, `{:error, :invalid_status_transition}`,
  or `{:error, :invalid_reason}`.
  """
  def cancel_enrollment_by_admin(enrollment_id, admin_id, reason)
      when is_binary(enrollment_id) and is_binary(admin_id) and is_binary(reason) and byte_size(reason) > 0 do
    CancelEnrollmentByAdmin.execute(enrollment_id, admin_id, reason)
  end

  @doc """
  Confirms a pending enrollment when the owning provider approves it.

  Returns `{:ok, Enrollment.t()}`, `{:error, :not_found}`, `{:error, :unauthorized}`,
  or `{:error, :invalid_status_transition}`.
  """
  def confirm_enrollment(%{enrollment_id: enrollment_id, provider_id: provider_id} = params)
      when is_binary(enrollment_id) and is_binary(provider_id) do
    ConfirmEnrollment.execute(params)
  end

  @doc """
  Creates or updates the enrollment capacity policy for a program (upsert).
  """
  def set_enrollment_policy(attrs) when is_map(attrs) do
    UpsertEnrollmentPolicy.execute(attrs)
  end

  @doc """
  Creates or updates the participant eligibility policy for a program (upsert).
  """
  def set_participant_policy(attrs) when is_map(attrs) do
    SetParticipantPolicy.execute(attrs)
  end

  @doc """
  Imports enrollment invites from a CSV binary, returning per-row outcomes.

  Streams the CSV through the parser in chunks of 100 rows (default),
  validates each row, deduplicates against in-batch and existing DB
  entries, and inserts surviving rows one at a time. Whole-file fatals
  (empty CSV, missing headers, no provider programs, title collisions)
  short-circuit and return `{:error, %{parse_errors: [...]}}`.

  Row-level failures NEVER abort the import; they are accumulated in
  the `:failed` list and the use case returns `{:ok, %{created, failed}}`.
  """
  @spec import_enrollment_csv(binary(), binary()) ::
          {:ok, ImportEnrollmentCsv.report()}
          | {:error, %{parse_errors: [{0, String.t()}]}}
  def import_enrollment_csv(provider_id, csv_binary) when is_binary(provider_id) and is_binary(csv_binary) do
    ImportEnrollmentCsv.execute(provider_id, csv_binary)
  end

  @doc """
  Creates a single enrollment invite from the provider's manual form.

  Unlike `import_enrollment_csv/2`, the caller supplies a pre-resolved
  `program_id` (picked from the provider's own catalog). Runs the same
  `:bulk_invites_imported` event path with `count: 1`, so the downstream
  email worker pipeline is reused verbatim.

  Returns:
  - `{:ok, %{invite_id: id}}` on success
  - `{:error, :no_programs}` if the provider has no catalog entries
  - `{:error, :duplicate}` when the same child+email is already invited
  - `{:error, %{validation_errors: [{field, msg}]}}` for form/authorisation errors
  """
  def invite_single_participant(provider_id, attrs) when is_binary(provider_id) and is_map(attrs) do
    InviteSingleParticipant.execute(provider_id, attrs)
  end

  @doc """
  Returns a changeset for the single-invite form. The LiveView is responsible
  for setting `:action` to `:validate` when it wants `<.input>` to render
  errors, matching the Phoenix generator convention.
  """
  def change_single_invite(attrs \\ %{}) do
    SingleInviteForm.changeset(%SingleInviteForm{}, attrs)
  end

  @doc """
  Attaches domain-layer `[{field, msg}]` errors returned by
  `invite_single_participant/2` onto a single-invite changeset so the web
  layer can re-render the form without reaching into context internals.
  """
  def apply_single_invite_domain_errors(%Ecto.Changeset{} = changeset, field_errors) when is_list(field_errors) do
    SingleInviteForm.apply_domain_errors(changeset, field_errors)
  end

  @doc """
  Resets an invite to pending and re-dispatches the email pipeline.

  Verifies the invite belongs to the given provider before resending.

  Returns `{:ok, invite}` on success, `{:error, :not_found}` or `{:error, :not_resendable}`.
  """
  def resend_invite(invite_id, provider_id) when is_binary(invite_id) and is_binary(provider_id) do
    ResendInvite.execute(invite_id, provider_id)
  end

  @doc """
  Deletes a bulk enrollment invite by ID.

  Verifies the invite belongs to the given provider before deleting.

  Returns `:ok` on success, `{:error, :not_found}`, or `{:error, :delete_failed}`.
  """
  def delete_invite(invite_id, provider_id) when is_binary(invite_id) and is_binary(provider_id) do
    DeleteInvite.execute(invite_id, provider_id)
  end

  @doc """
  Claims a bulk enrollment invite by token.

  Validates the token, resolves or creates the user account, and publishes
  the :invite_claimed event to trigger the async saga (child creation → enrollment).

  Returns:
  - `{:ok, %ClaimResult{user_type: :new_user, user: user, invite: invite}}` — new account created
  - `{:ok, %ClaimResult{user_type: :existing_user, user: user, invite: invite}}` — existing account found
  - `{:error, :not_found}` — invalid or expired token
  - `{:error, :already_claimed}` — invite already processed
  """
  def claim_invite(token) when is_binary(token) do
    ClaimInvite.execute(token)
  end

  @doc """
  Retrieves an enrollment by ID. Returns `{:ok, Enrollment.t()}` or `{:error, :not_found}`.
  """
  def get_enrollment(id) when is_binary(id) do
    GetEnrollment.execute(id)
  end

  @doc """
  Lists all enrollments for a parent, ordered by `enrolled_at` descending.
  """
  def list_parent_enrollments(parent_id) when is_binary(parent_id) do
    ListParentEnrollments.execute(parent_id)
  end

  @doc """
  Classifies enrollment+program pairs into active and expired groups.

  Pure domain logic — splits by enrollment status and program end date,
  then sorts active by upcoming start_date and expired by most recent end_date.

  Returns `{active, expired}` where each is a list of `{Enrollment.t(), Program.t()}` tuples.
  """
  def classify_family_programs(enrollment_programs, today) do
    EnrollmentClassifier.classify(enrollment_programs, today)
  end

  @doc """
  Lists enriched enrollment roster entries for a program.

  Returns a list of maps with child_name, enrollment status, and enrolled_at.
  Used by the provider dashboard to display the program roster.
  """
  def list_program_enrollments(program_id) when is_binary(program_id) do
    ListProgramEnrollments.execute(program_id)
  end

  @doc """
  Lists enriched pending enrollment entries across the given program IDs.

  Used by the provider dashboard's "Pending enrollments" inbox card to
  surface enrollments awaiting provider approval.
  """
  def list_pending_enrollments_for_provider(program_ids) when is_list(program_ids) do
    ListPendingEnrollmentsForProvider.execute(program_ids)
  end

  @doc """
  Returns the provider-scoped PubSub topic for an Enrollment domain event.

  Subscribers (e.g. `DashboardLive`) call this to subscribe to the same
  topic the publisher (`Enrollment.NotifyLiveViews`) derives.
  """
  defdelegate provider_scoped_topic(event_type, provider_id), to: NotifyLiveViews

  @doc """
  Counts active (pending/confirmed) enrollments for a parent in the given month (defaults to current month).
  Used by the entitlements system to enforce monthly booking limits.
  """
  def count_monthly_bookings(parent_id, month \\ nil) when is_binary(parent_id) do
    CountMonthlyBookings.execute(parent_id, month)
  end

  @doc """
  Returns `{:ok, info}` with booking usage for a parent's subscription tier
  (`parent_id`, `tier`, `cap`, `used`, `remaining`), or `{:error, :no_parent_profile}`.
  """
  def get_booking_usage_info(identity_id) when is_binary(identity_id) do
    GetBookingUsageInfo.execute(identity_id)
  end

  @doc """
  Returns distinct identity IDs of parents with active (pending/confirmed) enrollments in a program.
  Used by the Messaging context for broadcast recipient resolution.
  """
  @spec list_enrolled_identity_ids(String.t()) :: [String.t()]
  def list_enrolled_identity_ids(program_id) when is_binary(program_id) do
    ListEnrolledIdentityIds.execute(program_id)
  end

  @doc """
  Checks if a parent (identified by identity_id) is actively enrolled in a program.

  Returns true if at least one active enrollment (pending or confirmed) exists.
  """
  @spec enrolled?(String.t(), String.t()) :: boolean()
  def enrolled?(program_id, identity_id) when is_binary(program_id) and is_binary(identity_id) do
    CheckEnrollment.execute(program_id, identity_id)
  end

  @doc """
  Returns the enrollment policy for a program.
  """
  def get_enrollment_policy(program_id) when is_binary(program_id) do
    EnrollmentPolicyQueries.get_enrollment_policy(program_id)
  end

  @doc """
  Returns remaining enrollment capacity for a program.

  Fetches the policy and active count, then delegates calculation to the
  domain model (`EnrollmentPolicy.remaining_capacity/2`).

  - `{:ok, non_neg_integer()}` — remaining spots
  - `{:ok, :unlimited}` — no maximum configured
  """
  def remaining_capacity(program_id) when is_binary(program_id) do
    EnrollmentPolicyQueries.remaining_capacity(program_id)
  end

  @doc """
  Returns remaining capacity for multiple programs in a single batch query.
  Returns a map of `program_id => remaining_count | :unlimited`.
  """
  def get_remaining_capacities(program_ids) when is_list(program_ids) do
    EnrollmentPolicyQueries.get_remaining_capacities(program_ids)
  end

  @doc """
  Returns the count of active (pending/confirmed) enrollments for a program.
  """
  def count_active_enrollments(program_id) when is_binary(program_id) do
    EnrollmentPolicyQueries.count_active_enrollments(program_id)
  end

  @doc """
  Returns counts of active enrollments for multiple programs in a single batch query.
  Returns a map of `program_id => count`.
  """
  def count_active_enrollments_batch(program_ids) when is_list(program_ids) do
    EnrollmentPolicyQueries.count_active_enrollments_batch(program_ids)
  end

  @doc """
  Returns enrollment summary (enrolled count + total capacity) for multiple programs
  using only 2 DB queries. Returns a map of `program_id => %{enrolled: integer, capacity: integer | nil}`.

  Use this instead of calling `get_remaining_capacities/1` and `count_active_enrollments_batch/1`
  separately — doing so would issue 3 DB queries for the same data.
  """
  def get_enrollment_summary_batch(program_ids) when is_list(program_ids) do
    EnrollmentPolicyQueries.get_enrollment_summary_batch(program_ids)
  end

  @doc """
  Checks whether a child is eligible for a program based on participant restrictions.

  Returns `{:ok, :eligible}` when eligible or no policy exists.
  Returns `{:error, :ineligible, reasons}` with human-readable reason list.
  Returns `{:error, :not_found}` when the child does not exist.
  """
  def check_participant_eligibility(program_id, child_id) when is_binary(program_id) and is_binary(child_id) do
    CheckParticipantEligibility.execute(program_id, child_id)
  end

  @doc """
  Returns the participant policy for a program.
  """
  def get_participant_policy(program_id) when is_binary(program_id) do
    GetParticipantPolicy.execute(program_id)
  end

  @doc """
  Lists all bulk enrollment invites for a program, ordered by child last name.

  Returns `{:ok, [invite]}` or `{:ok, []}` if no invites exist.
  """
  def list_program_invites(program_id) when is_binary(program_id) do
    ListProgramInvites.execute(program_id)
  end

  @doc """
  Returns the count of bulk enrollment invites for a program.
  """
  def count_program_invites(program_id) when is_binary(program_id) do
    CountProgramInvites.execute(program_id)
  end

  @doc """
  Returns a changeset for enrollment policy form validation.
  """
  def new_policy_changeset(attrs \\ %{}) do
    EnrollmentPolicySchema.changeset(%EnrollmentPolicySchema{}, attrs)
  end

  @doc """
  Returns a changeset for participant policy form validation.
  """
  def new_participant_policy_changeset(attrs \\ %{}) do
    ParticipantPolicyForm.changeset(%ParticipantPolicyForm{}, attrs)
  end
end
