defmodule KlassHero.Provider do
  @moduledoc """
  Public API for the Provider bounded context.

  Manages provider profiles, verification documents, incident reports, staff
  members, program assignments, and program/session reads. This module is a thin
  facade: every function delegates to a sub-domain module under
  `KlassHero.Provider.*` (`Profiles`, `Verification`, `Incidents`, `Staff`,
  `Assignments`, `Programs`). Consumers call only this module.

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

  alias KlassHero.Provider.Assignments
  alias KlassHero.Provider.Incidents
  alias KlassHero.Provider.Profiles
  alias KlassHero.Provider.Programs
  alias KlassHero.Provider.Staff
  alias KlassHero.Provider.StaffMember
  alias KlassHero.Provider.Verification

  # --- Provider profiles ---------------------------------------------------

  @doc "Creates a new provider profile."
  defdelegate create_provider_profile(attrs), to: Profiles

  @doc "Creates a draft provider profile for a deliberate upgrade (#968, ADR-0005)."
  defdelegate create_draft_provider_profile(identity_id, business_name, business_owner_email),
    to: Profiles

  @doc "Updates an existing provider profile."
  defdelegate update_provider_profile(provider_id, attrs), to: Profiles

  @doc "Completes a draft provider profile (draft → active)."
  defdelegate complete_provider_profile(provider_id, attrs), to: Profiles

  @doc "Verifies a provider (admin only)."
  defdelegate verify_provider(provider_id, admin_id), to: Profiles

  @doc "Unverifies a provider (admin only)."
  defdelegate unverify_provider(provider_id, admin_id), to: Profiles

  @doc "Retrieves a provider profile by identity ID."
  defdelegate get_provider_by_identity(identity_id), to: Profiles

  @doc "Returns true if a provider profile exists for the given identity ID."
  defdelegate has_provider_profile?(identity_id), to: Profiles

  @doc "Returns the provider profile by ID."
  defdelegate get_provider_profile(provider_id), to: Profiles

  @doc "Gets the user (identity) ID that owns a provider profile ID (used by cross-context consumers)."
  defdelegate get_identity_id_for_provider(provider_id), to: Profiles

  @doc "Batch-resolves business names for provider IDs (used by cross-context consumers). Unknown IDs are omitted."
  defdelegate get_business_names(provider_ids), to: Profiles

  @doc "Lists all verified provider IDs (used by projections at bootstrap)."
  defdelegate list_verified_provider_ids, to: Profiles

  @doc "Returns a changeset for tracking provider profile form changes (for `to_form()` / `phx-change`)."
  defdelegate change_provider_profile(provider, attrs \\ %{}), to: Profiles

  @doc "Changeset for the profile completion form — casts a broader set of fields than `change_provider_profile/2`."
  defdelegate change_provider_profile_completion(provider, attrs \\ %{}), to: Profiles

  # --- Verification documents ----------------------------------------------

  @doc "Submits a verification document for a provider."
  defdelegate submit_verification_document(params), to: Verification

  @doc "Approves a verification document (admin only)."
  defdelegate approve_verification_document(document_id, reviewer_id), to: Verification

  @doc "Rejects a verification document with reason (admin only)."
  defdelegate reject_verification_document(document_id, reviewer_id, reason), to: Verification

  @doc "Returns all verification documents for a provider."
  defdelegate get_provider_verification_documents(provider_profile_id), to: Verification

  @doc "Lists all pending verification documents (admin)."
  defdelegate list_pending_verification_documents, to: Verification

  @doc "Lists verification documents with provider info for admin review."
  defdelegate list_verification_documents_for_admin(status \\ nil), to: Verification

  @doc "Returns a single verification document with provider info for admin review."
  defdelegate get_verification_document_for_admin(document_id), to: Verification

  @doc "Returns a verification document with a verified preview URL for admin review."
  defdelegate get_verification_document_preview(document_id), to: Verification

  @doc "Returns the list of valid verification document types."
  defdelegate valid_document_types, to: Verification

  # --- Incident reports ----------------------------------------------------

  @doc "Submits an incident report from a provider."
  defdelegate submit_incident_report(params), to: Incidents

  @doc "Lists incident report summaries for a program owned by the given provider."
  defdelegate list_incident_reports_for_program(provider_id, program_id), to: Incidents

  @doc "Retrieves a single incident report by ID (used by the notification worker)."
  defdelegate get_incident_report(id), to: Incidents

  # --- Staff members -------------------------------------------------------

  @doc "Creates the provider's own staff row (self-staffing, #969/ADR-0005)."
  defdelegate create_self_staff_member(provider_id, user_id, attrs), to: Staff

  @doc "Marks the user's employment at a provider as their selected staff context (#969)."
  defdelegate select_staff_context(user_id, provider_id), to: Staff

  @doc "Creates a new staff member for a provider."
  defdelegate create_staff_member(attrs), to: Staff

  @doc "Updates an existing staff member."
  defdelegate update_staff_member(provider_id, staff_id, attrs), to: Staff

  @doc "Deletes a staff member by ID."
  defdelegate delete_staff_member(staff_id), to: Staff

  @doc "Resends a staff invitation for a staff member in :failed or :expired status."
  defdelegate resend_staff_invitation(staff_member_id), to: Staff

  @doc "Transitions a staff member's invitation status to :expired."
  defdelegate expire_staff_invitation(staff_member_or_id), to: Staff

  @doc "Links a user to a staff member and accepts the invitation (synchronous, #967)."
  defdelegate accept_staff_invitation(staff_member, user_id), to: Staff

  @doc "Retrieves a single staff member by ID."
  defdelegate get_staff_member(staff_id), to: Staff

  @doc "Lists all staff members for a provider, ordered by insertion date."
  defdelegate list_staff_members(provider_id), to: Staff

  @doc "Lists active staff members for a provider."
  defdelegate list_active_staff_members(provider_id), to: Staff

  @doc "Returns the full name of a staff member."
  defdelegate staff_member_full_name(staff), to: Staff

  @doc "Returns the active staff member record linked to the given user ID (Scope :staff resolution)."
  defdelegate get_active_staff_member_by_user(user_id), to: Staff

  @doc "Lists all active employments of a user as StaffMembership read models (#969)."
  defdelegate list_active_staff_memberships(user_id), to: Staff

  @doc "Returns true if the user has any active staff row for the given provider."
  defdelegate active_staff_for_provider?(provider_id, user_id), to: Staff

  @doc "Returns the staff member matching the given invitation token hash (status :sent)."
  defdelegate get_staff_member_by_token_hash(token_hash), to: Staff

  @doc "Returns a changeset for tracking staff member form changes."
  defdelegate change_staff_member(staff, attrs \\ %{}), to: Staff

  @doc "Returns an empty changeset for a new staff member form."
  defdelegate new_staff_member_changeset(attrs \\ %{}), to: Staff

  @doc "Returns true if the staff member's invitation has expired."
  defdelegate invitation_expired?(staff_member), to: StaffMember

  # --- Program ↔ staff assignments -----------------------------------------

  @doc "Assigns a staff member to a program."
  defdelegate assign_staff_to_program(attrs), to: Assignments

  @doc "Unassigns a staff member from a program."
  defdelegate unassign_staff_from_program(program_id, staff_member_id), to: Assignments

  @doc "Filters a list of programs to only those assigned to a staff member."
  defdelegate list_assigned_programs(staff_member, programs), to: Assignments

  @doc "Lists all active staff assignments for a program."
  defdelegate list_active_assignments_for_program(program_id), to: Assignments

  @doc "Lists active staff members assigned to a program."
  defdelegate list_active_staff_for_program(program_id), to: Assignments

  @doc "Lists all active staff assignments for a provider."
  defdelegate list_active_assignments_for_provider(provider_id), to: Assignments

  @doc "Lists all active program assignments for a staff member."
  defdelegate list_active_assignments_for_staff_member(staff_member_id), to: Assignments

  # --- Programs & sessions -------------------------------------------------

  @doc "Returns the total completed session count across all programs for a provider."
  defdelegate get_total_session_count(provider_id), to: Programs

  @doc "Lists per-session detail rows for a provider's program from the projection."
  defdelegate list_program_sessions(provider_id, program_id), to: Programs

  @doc "Returns the provider-owned program by ID from the `provider_programs` projection."
  defdelegate get_provider_program(program_id), to: Programs

  @doc "Lists all programs owned by the given provider, ordered by name asc."
  defdelegate list_provider_programs(provider_id), to: Programs
end
