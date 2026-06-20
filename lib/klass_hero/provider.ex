defmodule KlassHero.Provider do
  @moduledoc """
  Public API for the Provider bounded context.

  Manages provider profiles, verification documents, and staff members.
  Split from the former Identity context to give Provider its own
  bounded context with clear domain boundaries.

  ## Usage

      # Provider Profiles
      {:ok, provider} = Provider.create_provider_profile(%{
        identity_id: "user-uuid",
        business_name: "My Business"
      })
      {:ok, provider} = Provider.get_provider_by_identity("user-uuid")
      true = Provider.has_provider_profile?("user-uuid")

      # Staff Members (email-less: 2-tuple, with email: 3-tuple with raw invitation token)
      {:ok, staff} = Provider.create_staff_member(%{provider_id: "...", first_name: "Bob", last_name: "Smith"})
      {:ok, staff, raw_token} = Provider.create_staff_member(%{provider_id: "...", email: "bob@example.com", ...})
      {:ok, members} = Provider.list_staff_members("provider-uuid")
  """

  use Boundary,
    top_level?: true,
    deps: [KlassHero, KlassHero.Shared],
    exports: [
      Domain.Models.IdentityVerification,
      Domain.Models.IncidentReport,
      Domain.Models.ProviderProfile,
      Domain.Models.StaffMember,
      Domain.Models.PayRate,
      Domain.Models.VerificationDocument,
      Domain.Models.ProgramStaffAssignment,
      Domain.ReadModels.IncidentReportSummary,
      Domain.ReadModels.ProviderProgram,
      Domain.ReadModels.SessionStats,
      Domain.ReadModels.StaffMembership,
      Adapters.Driven.Persistence.Repositories.IncidentReportRepository,
      Adapters.Driven.Persistence.Repositories.ProviderProgramRepository,
      Adapters.Driven.Persistence.Repositories.SessionStatsRepository,
      Adapters.Driven.Persistence.ChangeProviderProfile,
      Adapters.Driven.Persistence.ChangeStaffMember,
      # Pragmatic export: Backpex admin operates directly on Ecto schemas
      Adapters.Driven.Persistence.Schemas.ProviderProfileSchema,
      Adapters.Driven.Persistence.Schemas.StaffMemberSchema
    ]

  alias KlassHero.Provider.Adapters.Driven.Persistence.ChangeProviderProfile
  alias KlassHero.Provider.Adapters.Driven.Persistence.ChangeStaffMember
  alias KlassHero.Provider.Application.Commands.Incident.SubmitIncidentReport
  alias KlassHero.Provider.Application.Commands.Providers.CompleteProviderProfile
  alias KlassHero.Provider.Application.Commands.Providers.CreateProviderProfile
  alias KlassHero.Provider.Application.Commands.Providers.UnverifyProvider
  alias KlassHero.Provider.Application.Commands.Providers.UpdateProviderProfile
  alias KlassHero.Provider.Application.Commands.Providers.VerifyProvider
  alias KlassHero.Provider.Application.Commands.StaffMembers.AcceptStaffInvitation
  alias KlassHero.Provider.Application.Commands.StaffMembers.AssignStaffToProgram
  alias KlassHero.Provider.Application.Commands.StaffMembers.CreateSelfStaffMember
  alias KlassHero.Provider.Application.Commands.StaffMembers.CreateStaffMember
  alias KlassHero.Provider.Application.Commands.StaffMembers.DeleteStaffMember
  alias KlassHero.Provider.Application.Commands.StaffMembers.ExpireStaffInvitation
  alias KlassHero.Provider.Application.Commands.StaffMembers.ResendStaffInvitation
  alias KlassHero.Provider.Application.Commands.StaffMembers.SelectStaffContext
  alias KlassHero.Provider.Application.Commands.StaffMembers.UnassignStaffFromProgram
  alias KlassHero.Provider.Application.Commands.StaffMembers.UpdateStaffMember
  alias KlassHero.Provider.Application.Commands.Verification.ApproveVerificationDocument
  alias KlassHero.Provider.Application.Commands.Verification.CreateIdentityVerificationSession
  alias KlassHero.Provider.Application.Commands.Verification.RecordIdentityVerificationOutcome
  alias KlassHero.Provider.Application.Commands.Verification.RejectVerificationDocument
  alias KlassHero.Provider.Application.Commands.Verification.SubmitVerificationDocument
  alias KlassHero.Provider.Application.Queries.IncidentReportQueries
  alias KlassHero.Provider.Application.Queries.ListProgramSessions
  alias KlassHero.Provider.Application.Queries.ProgramStaffAssignmentQueries
  alias KlassHero.Provider.Application.Queries.ProviderProfileQueries
  alias KlassHero.Provider.Application.Queries.ProviderProgramQueries
  alias KlassHero.Provider.Application.Queries.StaffMemberQueries
  alias KlassHero.Provider.Application.Queries.StaffMembers.ListStaffAssignedPrograms
  alias KlassHero.Provider.Application.Queries.Verification.GetVerificationDocumentPreview
  alias KlassHero.Provider.Application.Queries.VerificationDocumentQueries
  alias KlassHero.Provider.Domain.Models.IdentityVerification
  alias KlassHero.Provider.Domain.Models.ProgramStaffAssignment
  alias KlassHero.Provider.Domain.Models.ProviderProfile
  alias KlassHero.Provider.Domain.Models.StaffMember
  alias KlassHero.Provider.Domain.Models.VerificationDocument
  alias KlassHero.Provider.Domain.Models.VettingCase
  alias KlassHero.Provider.Domain.Ports.ForQueryingIdentityVerifications
  alias KlassHero.Provider.Domain.Ports.ForQueryingVerificationDocuments
  alias KlassHero.Provider.Domain.ReadModels.IncidentReportSummary
  alias KlassHero.Provider.Domain.ReadModels.ProviderProgram
  alias KlassHero.Provider.Domain.ReadModels.SessionDetail
  alias KlassHero.Provider.Domain.ReadModels.StaffMembership

  @doc """
  Creates a new provider profile.
  """
  def create_provider_profile(attrs) when is_map(attrs) do
    CreateProviderProfile.execute(attrs)
  end

  @doc """
  Creates a draft provider profile for a deliberate upgrade (#968, ADR-0005).

  Owns the draft-birth policy: `profile_status: :draft` (the completion flow
  collects real business details). Every post-ADR-0005 provider is a deliberate
  act, so there's no longer a creation origin to record (#970).

  Same returns as `create_provider_profile/1`.
  """
  @spec create_draft_provider_profile(String.t(), String.t() | nil, String.t() | nil) ::
          {:ok, ProviderProfile.t()} | {:error, term()}
  def create_draft_provider_profile(identity_id, business_name, business_owner_email) when is_binary(identity_id) do
    create_provider_profile(%{
      identity_id: identity_id,
      business_name: business_name,
      business_owner_email: business_owner_email,
      profile_status: :draft
    })
  end

  @doc """
  Updates an existing provider profile.
  """
  @spec update_provider_profile(String.t(), map()) ::
          {:ok, ProviderProfile.t()}
          | {:error, :not_found | {:validation_error, list()} | Ecto.Changeset.t()}
  def update_provider_profile(provider_id, attrs) when is_binary(provider_id) and is_map(attrs) do
    UpdateProviderProfile.execute(provider_id, attrs)
  end

  @doc """
  Completes a draft provider profile, transitioning `profile_status` from `:draft` to `:active`.
  Returns `{:error, :already_active}` if the profile is not in draft status.
  """
  @spec complete_provider_profile(String.t(), map()) ::
          {:ok, ProviderProfile.t()}
          | {:error, :not_found | :already_active | {:validation_error, list()} | Ecto.Changeset.t()}
  def complete_provider_profile(provider_id, attrs) when is_binary(provider_id) and is_map(attrs) do
    CompleteProviderProfile.execute(provider_id, attrs)
  end

  @doc """
  Submit a verification document for a provider.

  Accepts a map with:
  - `:provider_profile_id` - Required provider profile ID
  - `:document_type` - Required document type
  - `:file_binary` - Required binary content of the uploaded file
  - `:original_filename` - Required original filename
  - `:content_type` - Optional MIME type
  - `:storage_opts` - Optional keyword list of additional storage adapter options
  """
  def submit_verification_document(params) do
    SubmitVerificationDocument.execute(params)
  end

  @doc """
  Submit an incident report from a provider.

  Accepts a map with:
  - `:provider_profile_id` - Required provider submitting the report
  - `:reporter_user_id` - Required user submitting the report
  - `:program_id` OR `:session_id` - Required, exactly one
  - `:category` - Required (atom from `IncidentReport.valid_categories/0`)
  - `:severity` - Required (atom from `IncidentReport.valid_severities/0`)
  - `:description` - Required (free-text, at least 10 characters)
  - `:occurred_at` - Required (`DateTime.t()`, cannot be in the future)
  - `:file_binary`, `:original_filename`, `:content_type` - Optional photo upload
  """
  def submit_incident_report(params) when is_map(params) do
    SubmitIncidentReport.execute(params)
  end

  @doc """
  Lists incident report summaries for a program owned by the given provider.

  Includes both program-direct and session-linked reports. Ordered by
  `occurred_at` descending. Returns `[]` for unknown or unowned programs.
  """
  @spec list_incident_reports_for_program(String.t(), String.t()) ::
          [IncidentReportSummary.t()]
  def list_incident_reports_for_program(provider_id, program_id)
      when is_binary(provider_id) and is_binary(program_id) do
    IncidentReportQueries.list_for_program(
      provider_id,
      program_id
    )
  end

  @doc "Approves a verification document (admin only)."
  def approve_verification_document(document_id, reviewer_id) do
    ApproveVerificationDocument.execute(%{
      document_id: document_id,
      reviewer_id: reviewer_id
    })
  end

  @doc "Rejects a verification document with reason (admin only)."
  def reject_verification_document(document_id, reviewer_id, reason) do
    RejectVerificationDocument.execute(%{
      document_id: document_id,
      reviewer_id: reviewer_id,
      reason: reason
    })
  end

  @doc "Starts a Stripe Identity verification session for a provider, returning the redirect url."
  def create_identity_verification_session(provider_id, return_url) do
    CreateIdentityVerificationSession.execute(%{provider_id: provider_id, return_url: return_url})
  end

  @doc "Records a Stripe Identity outcome (called by the webhook controller)."
  def record_identity_verification_outcome(outcome) do
    RecordIdentityVerificationOutcome.execute(outcome)
  end

  @doc "Verifies a provider (admin only)."
  def verify_provider(provider_id, admin_id) do
    VerifyProvider.execute(%{
      provider_id: provider_id,
      admin_id: admin_id
    })
  end

  @doc "Unverifies a provider (admin only)."
  def unverify_provider(provider_id, admin_id) do
    UnverifyProvider.execute(%{
      provider_id: provider_id,
      admin_id: admin_id
    })
  end

  @doc """
  Creates the provider's OWN staff row — pre-linked, `:accepted`, no
  invitation token or email (#969, ADR-0005 self-staffing).

  Returns `{:error, :already_staffed}` when an active row already links the
  user to this provider.
  """
  @spec create_self_staff_member(String.t(), String.t(), map()) ::
          {:ok, StaffMember.t()} | {:error, :already_staffed | term()}
  def create_self_staff_member(provider_id, user_id, attrs)
      when is_binary(provider_id) and is_binary(user_id) and is_map(attrs) do
    CreateSelfStaffMember.execute(provider_id, user_id, attrs)
  end

  @doc """
  Marks the user's employment at `provider_id` as their selected staff
  context (#969 staff-context switcher). Scope resolution prefers the
  selected row, remembered across sessions and devices.

  Returns `{:error, :not_staffed}` when the user has no active staff row at
  that provider.
  """
  @spec select_staff_context(String.t(), String.t()) ::
          {:ok, :selected} | {:error, :not_staffed}
  def select_staff_context(user_id, provider_id) when is_binary(user_id) and is_binary(provider_id) do
    SelectStaffContext.execute(user_id, provider_id)
  end

  @doc "Creates a new staff member for a provider."
  def create_staff_member(attrs) when is_map(attrs) do
    CreateStaffMember.execute(attrs)
  end

  @doc "Updates an existing staff member."
  def update_staff_member(staff_id, attrs) when is_binary(staff_id) and is_map(attrs) do
    UpdateStaffMember.execute(staff_id, attrs)
  end

  @doc "Deletes a staff member by ID."
  def delete_staff_member(staff_id) when is_binary(staff_id) do
    DeleteStaffMember.execute(staff_id)
  end

  @doc """
  Resends a staff invitation for a staff member in :failed or :expired status.

  Generates a fresh token, transitions status back to :pending, and re-emits
  :staff_member_invited to restart the invitation saga.

  Returns:
  - `{:ok, StaffMember.t(), raw_token}` on success
  - `{:error, :not_found}` if the staff member does not exist
  - `{:error, :invalid_invitation_transition}` if the current status does not allow resend
  """
  @spec resend_staff_invitation(String.t()) ::
          {:ok, StaffMember.t(), String.t()}
          | {:error, :not_found | :invalid_invitation_transition}
  def resend_staff_invitation(staff_member_id) when is_binary(staff_member_id) do
    ResendStaffInvitation.execute(staff_member_id)
  end

  @doc """
  Transitions a staff member's invitation status to :expired.
  Called by the invitation LiveView on lazy expiry detection.
  """
  @spec expire_staff_invitation(StaffMember.t() | String.t()) ::
          {:ok, StaffMember.t()} | {:error, term()}
  def expire_staff_invitation(%StaffMember{} = staff) do
    ExpireStaffInvitation.execute(staff)
  end

  def expire_staff_invitation(staff_member_id) when is_binary(staff_member_id) do
    ExpireStaffInvitation.execute(staff_member_id)
  end

  @doc """
  Links a User to a StaffMember and accepts the invitation (synchronous).

  Used by the one-click accept flow (#967). Idempotent for the same user.
  """
  @spec accept_staff_invitation(StaffMember.t(), String.t()) ::
          {:ok, StaffMember.t()} | {:error, term()}
  def accept_staff_invitation(%StaffMember{} = staff_member, user_id) when is_binary(user_id) do
    AcceptStaffInvitation.execute(staff_member, user_id)
  end

  @doc """
  Assigns a staff member to a program.

  Returns:
  - `{:ok, ProgramStaffAssignment.t()}` on success
  - `{:error, :already_assigned}` if already assigned
  - `{:error, :not_found}` if staff member does not exist
  """
  @spec assign_staff_to_program(map()) ::
          {:ok, ProgramStaffAssignment.t()}
          | {:error, :already_assigned | :not_found | term()}
  defdelegate assign_staff_to_program(attrs), to: AssignStaffToProgram, as: :execute

  @doc """
  Unassigns a staff member from a program.

  Returns:
  - `{:ok, ProgramStaffAssignment.t()}` on success
  - `{:error, :not_found}` if no active assignment exists
  """
  @spec unassign_staff_from_program(String.t(), String.t()) ::
          {:ok, ProgramStaffAssignment.t()} | {:error, :not_found | term()}
  defdelegate unassign_staff_from_program(program_id, staff_member_id),
    to: UnassignStaffFromProgram,
    as: :execute

  @doc "Retrieves a provider profile by identity ID."
  def get_provider_by_identity(identity_id) when is_binary(identity_id) do
    ProviderProfileQueries.get_by_identity(identity_id)
  end

  @doc "Returns true if a provider profile exists for the given identity ID."
  def has_provider_profile?(identity_id) when is_binary(identity_id) do
    ProviderProfileQueries.has_profile?(identity_id)
  end

  @doc "Returns the provider profile by ID."
  @spec get_provider_profile(String.t()) :: {:ok, ProviderProfile.t()} | {:error, :not_found}
  def get_provider_profile(provider_id) when is_binary(provider_id) do
    ProviderProfileQueries.get_profile(provider_id)
  end

  @doc """
  Gets the user (identity) ID for a provider profile ID.

  Used by cross-context consumers (e.g. Messaging) to resolve
  `conversation.provider_id` (provider profile ID) back to a user ID
  for permission and authorization checks.

  Returns:
  - `{:ok, identity_id}` - The user ID that owns this provider profile
  - `{:error, :not_found}` - No provider profile exists with this ID
  """
  @spec get_identity_id_for_provider(String.t()) :: {:ok, String.t()} | {:error, :not_found}
  def get_identity_id_for_provider(provider_id) when is_binary(provider_id) do
    ProviderProfileQueries.get_identity_id_for_provider(provider_id)
  end

  @doc "Lists all verified provider IDs (used by projections at bootstrap)."
  def list_verified_provider_ids do
    ProviderProfileQueries.list_verified_ids()
  end

  @doc "Returns all verification documents for a provider."
  def get_provider_verification_documents(provider_profile_id) do
    VerificationDocumentQueries.get_by_provider(provider_profile_id)
  end

  @doc "Lists all pending verification documents (admin)."
  def list_pending_verification_documents do
    VerificationDocumentQueries.list_pending()
  end

  @doc """
  List verification documents with provider info for admin review.

  Accepts an optional status filter atom:
  - `nil` - All documents (newest first)
  - `:pending` - Pending documents (oldest first, FIFO)
  - `:approved` - Approved documents (newest first)
  - `:rejected` - Rejected documents (newest first)
  """
  @spec list_verification_documents_for_admin(VerificationDocument.status() | nil) ::
          {:ok, [ForQueryingVerificationDocuments.admin_review_result()]}
  def list_verification_documents_for_admin(status \\ nil) do
    VerificationDocumentQueries.list_for_admin_review(status)
  end

  @doc "Returns a single verification document with provider info for admin review."
  @spec get_verification_document_for_admin(String.t()) ::
          {:ok, ForQueryingVerificationDocuments.admin_review_result()} | {:error, :not_found}
  def get_verification_document_for_admin(document_id) do
    VerificationDocumentQueries.get_for_admin_review(document_id)
  end

  @doc """
  Get a verification document with a verified preview URL for admin review.
  """
  @spec get_verification_document_preview(String.t()) ::
          {:ok,
           %{
             document: VerificationDocument.t(),
             provider_business_name: String.t(),
             signed_url: String.t() | nil,
             preview_type: :image | :pdf | :other
           }}
          | {:error, :not_found}
  def get_verification_document_preview(document_id) do
    GetVerificationDocumentPreview.execute(document_id)
  end

  @doc "Returns the list of valid verification document types."
  defdelegate valid_document_types,
    to: VerificationDocument

  @doc "Retrieves a single staff member by ID."
  def get_staff_member(staff_id) when is_binary(staff_id) do
    StaffMemberQueries.get(staff_id)
  end

  @doc "Lists all staff members for a provider, ordered by insertion date."
  def list_staff_members(provider_id) when is_binary(provider_id) do
    StaffMemberQueries.list_by_provider(provider_id)
  end

  @doc "Lists active staff members for a provider."
  def list_active_staff_members(provider_id) when is_binary(provider_id) do
    StaffMemberQueries.list_active_by_provider(provider_id)
  end

  @doc "Returns the full name of a staff member."
  @spec staff_member_full_name(StaffMember.t()) :: String.t()
  def staff_member_full_name(%StaffMember{} = staff) do
    StaffMember.full_name(staff)
  end

  @doc """
  Returns the active staff member record linked to the given user ID.
  Used by Scope to resolve :staff role.
  """
  @spec get_active_staff_member_by_user(String.t()) ::
          {:ok, StaffMember.t()} | {:error, :not_found}
  def get_active_staff_member_by_user(user_id) when is_binary(user_id) do
    StaffMemberQueries.get_active_by_user(user_id)
  end

  @doc """
  Lists all active employments of a user as `StaffMembership` read models
  (staff row + employing provider's business name), in the same selection
  order scope resolution uses — the head of the list is the employment the
  scope currently carries. Powers the staff-context switcher (#969).
  """
  @spec list_active_staff_memberships(String.t()) :: {:ok, [StaffMembership.t()]}
  def list_active_staff_memberships(user_id) when is_binary(user_id) do
    StaffMemberQueries.list_active_memberships_by_user(user_id)
  end

  @doc """
  Returns true if the given user has any active staff_member row for the given provider.

  Use this for permission checks scoped to a specific provider — unlike
  `get_active_staff_member_by_user/1`, this correctly identifies users who are
  active staff at multiple providers.
  """
  @spec active_staff_for_provider?(String.t(), String.t()) :: boolean()
  def active_staff_for_provider?(provider_id, user_id) when is_binary(provider_id) and is_binary(user_id) do
    StaffMemberQueries.active_for_provider_and_user?(provider_id, user_id)
  end

  @doc """
  Returns the staff member matching the given invitation token hash,
  only if invitation_status is :sent. Used by the invitation registration flow.
  """
  @spec get_staff_member_by_token_hash(binary()) :: {:ok, StaffMember.t()} | {:error, :not_found}
  def get_staff_member_by_token_hash(token_hash) when is_binary(token_hash) do
    StaffMemberQueries.get_by_token_hash(token_hash)
  end

  @doc "Returns true if the staff member's invitation has expired."
  defdelegate invitation_expired?(staff_member), to: StaffMember

  @doc """
  Filters a list of programs to only those assigned to a staff member.

  If the staff member has no tags, returns all programs unchanged.
  If tags are set, returns only programs whose category matches a tag.

  The caller is responsible for fetching the programs list (typically
  from `ProgramCatalog.list_programs_for_provider/1`), keeping the
  Provider context free of cross-context dependencies.
  """
  @spec list_assigned_programs(StaffMember.t(), [map()]) :: [map()]
  def list_assigned_programs(%StaffMember{} = staff_member, programs) when is_list(programs) do
    ListStaffAssignedPrograms.execute(staff_member, programs)
  end

  @doc "Lists all active staff assignments for a program."
  @spec list_active_assignments_for_program(String.t()) :: [
          ProgramStaffAssignment.t()
        ]
  def list_active_assignments_for_program(program_id) when is_binary(program_id) do
    ProgramStaffAssignmentQueries.list_active_for_program(program_id)
  end

  @doc """
  Lists active staff members assigned to a program.

  Uses a JOIN through `program_staff_assignments` so staff details arrive in a
  single round-trip, ordered by when each assignment was created.
  """
  @spec list_active_staff_for_program(String.t()) :: [StaffMember.t()]
  def list_active_staff_for_program(program_id) when is_binary(program_id) do
    {:ok, members} = StaffMemberQueries.list_active_by_program(program_id)
    members
  end

  @doc "Lists all active staff assignments for a provider."
  @spec list_active_assignments_for_provider(String.t()) :: [
          ProgramStaffAssignment.t()
        ]
  def list_active_assignments_for_provider(provider_id) when is_binary(provider_id) do
    ProgramStaffAssignmentQueries.list_active_for_provider(provider_id)
  end

  @doc "Lists all active program assignments for a staff member."
  @spec list_active_assignments_for_staff_member(String.t()) :: [
          ProgramStaffAssignment.t()
        ]
  def list_active_assignments_for_staff_member(staff_member_id) when is_binary(staff_member_id) do
    ProgramStaffAssignmentQueries.list_active_for_staff_member(staff_member_id)
  end

  @session_stats_repo Application.compile_env!(:klass_hero, [:provider, :for_querying_session_stats])

  @doc "Returns the total completed session count across all programs for a provider."
  @spec get_total_session_count(String.t()) :: non_neg_integer()
  def get_total_session_count(provider_id) when is_binary(provider_id) do
    @session_stats_repo.get_total_count(provider_id)
  end

  @identity_query Application.compile_env!(:klass_hero, [:provider, :for_querying_identity_verifications])
  @vetting_query Application.compile_env!(:klass_hero, [:provider, :for_querying_vetting_cases])

  @doc "Returns the most recent Stripe Identity verification for a provider, or `{:error, :not_found}`."
  @spec get_latest_identity_verification(String.t()) ::
          {:ok, IdentityVerification.t()} | {:error, :not_found}
  def get_latest_identity_verification(provider_id) when is_binary(provider_id) do
    @identity_query.get_latest_by_provider(provider_id)
  end

  @doc "Lists all identity verifications with provider business names for admin review (newest first)."
  @spec list_identity_verifications_for_admin() ::
          {:ok, [ForQueryingIdentityVerifications.admin_result()]}
  def list_identity_verifications_for_admin do
    @identity_query.list_for_admin()
  end

  @doc """
  Returns `true` when the provider's Stripe Identity vetting step is approved.

  False for a provider with no vetting case, no identity step, or an identity step not yet approved.
  """
  @spec identity_step_approved?(String.t()) :: boolean()
  def identity_step_approved?(provider_id) when is_binary(provider_id) do
    case @vetting_query.get_by_provider(provider_id) do
      {:ok, case_} -> VettingCase.identity_step_approved?(case_)
      {:error, :not_found} -> false
    end
  end

  @doc """
  Lists per-session detail rows for a provider's program from the
  `provider_session_details` projection. Cross-provider lookups return `[]`.
  """
  @spec list_program_sessions(String.t(), String.t()) :: [
          SessionDetail.t()
        ]
  def list_program_sessions(provider_id, program_id) when is_binary(provider_id) and is_binary(program_id) do
    ListProgramSessions.execute(provider_id, program_id)
  end

  @doc "Returns the provider-owned program by ID from the `provider_programs` projection."
  @spec get_provider_program(String.t()) :: {:ok, ProviderProgram.t()} | {:error, :not_found}
  def get_provider_program(program_id) when is_binary(program_id) do
    ProviderProgramQueries.get_by_id(program_id)
  end

  @doc "Lists all programs owned by the given provider, ordered by name asc."
  @spec list_provider_programs(String.t()) :: [ProviderProgram.t()]
  def list_provider_programs(provider_id) when is_binary(provider_id) do
    ProviderProgramQueries.list_by_provider(provider_id)
  end

  @doc "Returns a changeset for tracking provider profile form changes (for `to_form()` / `phx-change`)."
  @spec change_provider_profile(ProviderProfile.t(), map()) :: Ecto.Changeset.t()
  def change_provider_profile(%ProviderProfile{} = provider, attrs \\ %{}) do
    ChangeProviderProfile.execute(provider, attrs)
  end

  @doc "Changeset for the profile completion form — casts a broader set of fields than `change_provider_profile/2`."
  @spec change_provider_profile_completion(ProviderProfile.t(), map()) :: Ecto.Changeset.t()
  def change_provider_profile_completion(%ProviderProfile{} = provider, attrs \\ %{}) do
    ChangeProviderProfile.completion_changeset(provider, attrs)
  end

  @doc "Returns a changeset for tracking staff member form changes."
  def change_staff_member(%StaffMember{} = staff, attrs \\ %{}) do
    ChangeStaffMember.execute(staff, attrs)
  end

  @doc "Returns an empty changeset for a new staff member form."
  def new_staff_member_changeset(attrs \\ %{}) do
    ChangeStaffMember.new_changeset(attrs)
  end
end
