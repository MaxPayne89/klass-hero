defmodule KlassHero.Enrollment do
  @moduledoc """
  Public API for the Enrollment bounded context.

  This module provides the public interface for managing program enrollments,
  including creating enrollments, tracking booking counts for entitlements,
  and retrieving enrollment history.

  ## Usage

      # Create an enrollment (total = program price, no derived fees)
      {:ok, enrollment} = Enrollment.create_enrollment(%{
        program_id: "program-uuid",
        child_id: "child-uuid",
        parent_id: "parent-uuid",
        payment_method: "card",
        subtotal: Decimal.new("45.00"),
        vat_amount: Decimal.new("0.00"),
        card_fee_amount: Decimal.new("0.00"),
        total_amount: Decimal.new("45.00")
      })

      # Get an enrollment
      {:ok, enrollment} = Enrollment.get_enrollment("enrollment-uuid")

      # List enrollments for a parent
      enrollments = Enrollment.list_parent_enrollments("parent-uuid")

      # Count monthly bookings (for entitlement enforcement)
      count = Enrollment.count_monthly_bookings("parent-uuid")

  ## Architecture

  This context follows the Ports & Adapters architecture:
  - Public API (this module) → delegates to use cases
  - Use cases (application layer) → orchestrate domain operations
  - Repository ports (domain layer) → define persistence contracts
  - Repository implementations (adapter layer) → implement persistence
  """

  use Boundary,
    top_level?: true,
    deps: [
      KlassHero,
      KlassHero.Accounts,
      KlassHero.Family,
      KlassHero.Shared
    ],
    exports: [
      # Pragmatic export: Backpex admin operates directly on Ecto schemas
      Adapters.Driven.Persistence.Schemas.EnrollmentSchema,
      # Public result type for ClaimInvite — callers pattern-match on %ClaimResult{}
      Application.ClaimResult
    ]

  alias KlassHero.Enrollment.Adapters.Driven.Persistence.Schemas.EnrollmentPolicySchema

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

  # ===========================================================================
  # Commands
  # ===========================================================================

  @doc """
  Creates a new enrollment.

  Required parameters:
  - program_id: UUID of the program
  - child_id: UUID of the child
  - parent_id: UUID of the parent

  Optional parameters:
  - status: Enrollment status (defaults to "pending")
  - enrolled_at: DateTime (defaults to now)
  - subtotal, vat_amount, card_fee_amount, total_amount: Fee amounts
  - payment_method: "card" or "transfer"
  - special_requirements: Special needs text

  Returns:
  - `{:ok, Enrollment.t()}` - Enrollment created successfully
  - `{:error, :duplicate_resource}` - Active enrollment already exists for child/program
  - `{:error, term()}` - Validation or persistence failure
  """
  def create_enrollment(params) when is_map(params) do
    CreateEnrollment.execute(params)
  end

  @doc """
  Cancels an enrollment by admin action.

  Enforces domain lifecycle guards (only pending/confirmed can be cancelled),
  persists the status change, and dispatches an enrollment_cancelled domain event.

  ## Parameters

  - `enrollment_id` — UUID of the enrollment
  - `admin_id` — UUID of the admin performing the cancellation
  - `reason` — human-readable cancellation reason

  ## Returns

  - `{:ok, Enrollment.t()}` — cancellation succeeded
  - `{:error, :not_found}` — enrollment does not exist
  - `{:error, :invalid_status_transition}` — enrollment is completed or already cancelled
  - `{:error, :invalid_reason}` — reason is empty
  """
  def cancel_enrollment_by_admin(enrollment_id, admin_id, reason)
      when is_binary(enrollment_id) and is_binary(admin_id) and is_binary(reason) and byte_size(reason) > 0 do
    CancelEnrollmentByAdmin.execute(enrollment_id, admin_id, reason)
  end

  @doc """
  Confirms a pending enrollment when the owning provider approves it.

  ## Parameters

  - `:enrollment_id` — UUID of the enrollment
  - `:provider_id` — UUID of the provider performing the approval

  ## Returns

  - `{:ok, Enrollment.t()}` — confirmation succeeded
  - `{:error, :not_found}` — enrollment does not exist
  - `{:error, :unauthorized}` — provider does not own the program
  - `{:error, :invalid_status_transition}` — enrollment is not pending
  """
  def confirm_enrollment(%{enrollment_id: enrollment_id, provider_id: provider_id} = params)
      when is_binary(enrollment_id) and is_binary(provider_id) do
    ConfirmEnrollment.execute(params)
  end

  @doc """
  Creates or updates enrollment capacity policy for a program.

  ## Parameters
  - attrs: Map with :program_id (required), :min_enrollment, :max_enrollment (at least one required)

  ## Returns
  - `{:ok, EnrollmentPolicy.t()}` on success
  - `{:error, term()}` on validation failure
  """
  def set_enrollment_policy(attrs) when is_map(attrs) do
    UpsertEnrollmentPolicy.execute(attrs)
  end

  @doc """
  Creates or updates a participant eligibility policy for a program.

  Uses upsert semantics -- if a policy already exists for the program_id, it is updated.
  """
  def set_participant_policy(attrs) when is_map(attrs) do
    SetParticipantPolicy.execute(attrs)
  end

  @doc """
  Imports enrollment invites from a CSV file for a provider.

  Parses the CSV, validates each row, checks for duplicates, and persists
  all valid rows as BulkEnrollmentInvite records with status "pending".

  All-or-nothing: if any row fails validation, nothing is persisted.

  Returns:
  - `{:ok, %{created: count}}` on success
  - `{:error, error_report}` with parse_errors, validation_errors, or duplicate_errors
  """
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

  # ===========================================================================
  # Queries
  # ===========================================================================

  @doc """
  Retrieves an enrollment by ID.

  Returns:
  - `{:ok, Enrollment.t()}` - Enrollment found
  - `{:error, :not_found}` - No enrollment exists with the given ID
  """
  def get_enrollment(id) when is_binary(id) do
    GetEnrollment.execute(id)
  end

  @doc """
  Lists all enrollments for a parent.

  Returns list of Enrollment.t(), ordered by enrolled_at descending.
  Returns empty list if no enrollments found.
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
  Counts active enrollments for a parent in the current month.

  This is used by the entitlements system to enforce monthly booking limits.
  Only counts enrollments with status 'pending' or 'confirmed'.

  Parameters:
  - parent_id: The parent's ID
  - month: Optional Date representing the month (defaults to current month)

  Returns non-negative integer count.
  """
  def count_monthly_bookings(parent_id, month \\ nil) when is_binary(parent_id) do
    CountMonthlyBookings.execute(parent_id, month)
  end

  @doc """
  Returns booking usage information for a parent.

  This encapsulates the logic for fetching booking limits, current usage,
  and remaining capacity based on the parent's subscription tier.

  ## Parameters

  - `identity_id` - The user's identity ID (from authentication)

  ## Returns

  - `{:ok, info}` with booking usage map containing:
    - `parent_id` - The parent's UUID
    - `tier` - The subscription tier atom
    - `cap` - The monthly booking cap (integer or :unlimited)
    - `used` - Number of bookings used this month
    - `remaining` - Number of bookings remaining (:unlimited or integer)
  - `{:error, :no_parent_profile}` if no parent profile exists
  """
  def get_booking_usage_info(identity_id) when is_binary(identity_id) do
    GetBookingUsageInfo.execute(identity_id)
  end

  @doc """
  Returns identity IDs of parents with active enrollments in a program.

  Active enrollments are those with status "pending" or "confirmed".
  Used by the Messaging context for program broadcast recipient resolution.

  Returns a distinct list of identity_ids (user IDs).
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

  # ===========================================================================
  # Forms
  # ===========================================================================

  @doc """
  Returns a changeset for enrollment policy form validation.

  Used by the provider dashboard to validate capacity fields inline
  before the program is created.
  """
  def new_policy_changeset(attrs \\ %{}) do
    EnrollmentPolicySchema.changeset(%EnrollmentPolicySchema{}, attrs)
  end

  @doc """
  Returns a changeset for participant policy form validation.

  Used by the provider dashboard to validate eligibility restriction fields
  inline before the program is created.
  """
  def new_participant_policy_changeset(attrs \\ %{}) do
    ParticipantPolicyForm.changeset(%ParticipantPolicyForm{}, attrs)
  end
end
