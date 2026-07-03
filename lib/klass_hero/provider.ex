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

  use KlassHero.Shared.Tracing

  import Ecto.Query, warn: false

  alias KlassHero.Provider.Adapters.Driven.Persistence.Mappers.IncidentReportSummaryMapper
  alias KlassHero.Provider.Adapters.Driven.Persistence.Repositories.SessionStatsRepository
  alias KlassHero.Provider.Adapters.Driven.Persistence.Schemas.ProviderSessionDetailSchema
  alias KlassHero.Provider.Application.Queries.ListProgramSessions
  alias KlassHero.Provider.Application.Queries.ProviderProgramQueries
  alias KlassHero.Provider.Domain.Events.ProviderEvents
  alias KlassHero.Provider.Domain.Events.ProviderIntegrationEvents
  alias KlassHero.Provider.Domain.ReadModels.IncidentReportSummary
  alias KlassHero.Provider.Domain.ReadModels.ProviderProgram
  alias KlassHero.Provider.Domain.ReadModels.SessionDetail
  alias KlassHero.Provider.Domain.ReadModels.StaffMembership
  alias KlassHero.Provider.IncidentReport
  alias KlassHero.Provider.ProgramStaffAssignment
  alias KlassHero.Provider.ProviderProfile
  alias KlassHero.Provider.StaffMember
  alias KlassHero.Provider.SubmitIncidentReport
  alias KlassHero.Provider.VerificationDocument
  alias KlassHero.Repo
  alias KlassHero.Shared.Adapters.Driven.Persistence.EctoErrorHelpers
  alias KlassHero.Shared.CommandResult
  alias KlassHero.Shared.Domain.Events.DomainEvent
  alias KlassHero.Shared.DomainEventBus
  alias KlassHero.Shared.EventDispatchHelper
  alias KlassHero.Shared.IntegrationEventPublishing
  alias KlassHero.Shared.Storage

  require Logger

  # Linkage and invitation state are owned by create_staff_with_invitation/the
  # accept/self-staff flows — never by caller attrs. Stripping them (both atom
  # and string keys) keeps the generic create unable to mint pre-linked or
  # pre-accepted rows even if a future caller forwards raw params.
  @staff_programmatic_keys [
    :user_id,
    "user_id",
    :invitation_status,
    "invitation_status",
    :invitation_token_hash,
    "invitation_token_hash",
    :invitation_sent_at,
    "invitation_sent_at"
  ]

  @staff_updatable_fields ~w(first_name last_name role email bio headshot_url tags qualifications active pay_rate)a

  # Fields a caller may change via update_provider_profile/2 (all other keys stripped).
  @profile_update_fields ~w(description logo_url)a

  # Scalar fields re-cast when persisting a transitioned profile struct. identity_id
  # and id never change, so they stay out; Ecto only stages actual diffs.
  @profile_persist_fields ~w(business_name business_owner_email description phone website address logo_url verified verified_at verified_by_id categories profile_status)a

  @doc """
  Creates a new provider profile.
  """
  def create_provider_profile(attrs) when is_map(attrs) do
    context_span entity: "provider_profile" do
      attrs_with_id = Map.put_new(attrs, :id, Ecto.UUID.generate())

      with {:ok, _validated} <- ProviderProfile.new(attrs_with_id),
           {:ok, persisted} <- insert_provider_profile(attrs_with_id) do
        {:ok, persisted}
      else
        result -> CommandResult.wrap_validation_errors(result)
      end
    end
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
    context_span entity: "provider_profile" do
      attrs = Map.take(attrs, @profile_update_fields)

      with {:ok, existing} <- get_provider_profile(provider_id),
           merged = Map.merge(Map.from_struct(existing), attrs),
           {:ok, _validated} <- ProviderProfile.new(merged),
           updated = struct(existing, attrs),
           {:ok, persisted} <- persist_provider_profile(existing, updated) do
        {:ok, persisted}
      else
        result -> CommandResult.wrap_validation_errors(result)
      end
    end
  end

  @doc """
  Completes a draft provider profile, transitioning `profile_status` from `:draft` to `:active`.
  Returns `{:error, :already_active}` if the profile is not in draft status.
  """
  @spec complete_provider_profile(String.t(), map()) ::
          {:ok, ProviderProfile.t()}
          | {:error, :not_found | :already_active | {:validation_error, list()} | Ecto.Changeset.t()}
  def complete_provider_profile(provider_id, attrs) when is_binary(provider_id) and is_map(attrs) do
    context_span entity: "provider_profile" do
      with {:ok, existing} <- get_provider_profile(provider_id),
           {:ok, completed} <- ProviderProfile.complete_profile(existing, attrs),
           {:ok, persisted} <- persist_provider_profile(existing, completed) do
        {:ok, persisted}
      else
        result -> CommandResult.wrap_validation_errors(result)
      end
    end
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
    context_span entity: "verification_document" do
      with :ok <- validate_verification_submission(params),
           {:ok, file_url} <- upload_verification_file(params) do
        insert_verification_document(params, file_url)
      end
    end
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
    program_direct = list_incidents_program_direct(provider_id, program_id)
    session_linked = list_incidents_session_linked(provider_id, program_id)

    (program_direct ++ session_linked)
    |> Enum.sort_by(& &1.occurred_at, {:desc, DateTime})
    |> Enum.map(&IncidentReportSummaryMapper.from_schema/1)
  end

  @doc "Retrieves a single incident report by ID (used by the notification worker)."
  @spec get_incident_report(String.t()) :: {:ok, IncidentReport.t()} | {:error, :not_found}
  def get_incident_report(id) when is_binary(id) do
    case Repo.get(IncidentReport, id) do
      nil -> {:error, :not_found}
      report -> {:ok, report}
    end
  end

  defp list_incidents_program_direct(provider_id, program_id) do
    IncidentReport
    |> where([r], r.provider_profile_id == ^provider_id and r.program_id == ^program_id)
    |> Repo.all()
  end

  # Session-linked reports match through the provider_session_details projection.
  defp list_incidents_session_linked(provider_id, program_id) do
    from(r in IncidentReport,
      join: s in ProviderSessionDetailSchema,
      on: s.session_id == r.session_id,
      where:
        r.provider_profile_id == ^provider_id and
          s.provider_id == ^provider_id and
          s.program_id == ^program_id,
      select: r
    )
    |> Repo.all()
  end

  @doc "Approves a verification document (admin only)."
  def approve_verification_document(document_id, reviewer_id) do
    context_span entity: "verification_document" do
      with {:ok, doc} <- get_verification_document(document_id),
           {:ok, approved} <- VerificationDocument.approve(doc, reviewer_id),
           {:ok, persisted} <- persist_verification_review(doc, approved) do
        dispatch_verification_event(:verification_document_approved, persisted, reviewer_id)
        {:ok, persisted}
      end
    end
  end

  @doc "Rejects a verification document with reason (admin only)."
  def reject_verification_document(document_id, reviewer_id, reason) do
    context_span entity: "verification_document" do
      with :ok <- validate_rejection_reason(reason),
           {:ok, doc} <- get_verification_document(document_id),
           {:ok, rejected} <- VerificationDocument.reject(doc, reviewer_id, reason),
           {:ok, persisted} <- persist_verification_review(doc, rejected) do
        dispatch_verification_event(:verification_document_rejected, persisted, reviewer_id)
        {:ok, persisted}
      end
    end
  end

  @doc "Verifies a provider (admin only)."
  def verify_provider(provider_id, admin_id) do
    context_span entity: "provider_profile" do
      with {:ok, profile} <- get_provider_profile(provider_id),
           {:ok, verified} <- ProviderProfile.verify(profile, admin_id),
           {:ok, persisted} <- persist_provider_profile(profile, verified),
           :ok <- publish_verification_event(persisted, admin_id, :verified) do
        {:ok, persisted}
      end
    end
  end

  @doc "Unverifies a provider (admin only)."
  def unverify_provider(provider_id, admin_id) do
    context_span entity: "provider_profile" do
      with {:ok, profile} <- get_provider_profile(provider_id),
           {:ok, unverified} <- ProviderProfile.unverify(profile),
           {:ok, persisted} <- persist_provider_profile(profile, unverified),
           :ok <- publish_verification_event(persisted, admin_id, :unverified) do
        {:ok, persisted}
      end
    end
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
    context_span entity: "staff_member" do
      if active_staff_for_provider?(provider_id, user_id) do
        {:error, :already_staffed}
      else
        create_linked_staff_member(provider_id, user_id, attrs)
      end
    end
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
    touch_staff_last_selected(user_id, provider_id)
  end

  @doc "Creates a new staff member for a provider."
  def create_staff_member(attrs) when is_map(attrs) do
    context_span entity: "staff_member" do
      attrs_with_id =
        attrs
        |> Map.drop(@staff_programmatic_keys)
        |> Map.put_new(:id, Ecto.UUID.generate())

      if staff_has_email?(attrs_with_id) do
        create_staff_with_invitation(attrs_with_id)
      else
        create_staff_display_only(attrs_with_id)
      end
    end
  end

  @doc "Updates an existing staff member."
  def update_staff_member(staff_id, attrs) when is_binary(staff_id) and is_map(attrs) do
    context_span entity: "staff_member" do
      attrs = Map.take(attrs, @staff_updatable_fields)

      with {:ok, existing} <- get_staff_member(staff_id),
           merged = Map.merge(Map.from_struct(existing), attrs),
           {:ok, _validated} <- StaffMember.new(merged),
           {:ok, persisted} <- persist_staff_update(existing, attrs) do
        {:ok, persisted}
      else
        result -> CommandResult.wrap_validation_errors(result)
      end
    end
  end

  @doc "Deletes a staff member by ID."
  def delete_staff_member(staff_id) when is_binary(staff_id) do
    context_span entity: "staff_member" do
      case Repo.get(StaffMember, staff_id) do
        nil ->
          {:error, :not_found}

        staff ->
          {:ok, _} = Repo.delete(staff)
          :ok
      end
    end
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
    context_span entity: "staff_member" do
      with {:ok, staff} <- get_staff_member(staff_member_id),
           {:ok, _transitioned} <- StaffMember.transition_invitation(staff, :pending),
           {raw_token, token_hash} = StaffMember.generate_invitation_token(),
           {:ok, persisted} <-
             persist_staff_invitation_fields(staff, %{
               invitation_status: :pending,
               invitation_token_hash: token_hash
             }) do
        emit_or_compensate_staff_invitation(persisted, raw_token)
      end
    end
  end

  @doc """
  Transitions a staff member's invitation status to :expired.
  Called by the invitation LiveView on lazy expiry detection.
  """
  @spec expire_staff_invitation(StaffMember.t() | String.t()) ::
          {:ok, StaffMember.t()} | {:error, term()}
  def expire_staff_invitation(%StaffMember{} = staff) do
    context_span entity: "staff_member" do
      with {:ok, _updated} <- StaffMember.transition_invitation(staff, :expired) do
        persist_staff_invitation_fields(staff, %{invitation_status: :expired})
      end
    end
  end

  def expire_staff_invitation(staff_member_id) when is_binary(staff_member_id) do
    with {:ok, staff} <- get_staff_member(staff_member_id) do
      expire_staff_invitation(staff)
    end
  end

  @doc """
  Links a User to a StaffMember and accepts the invitation (synchronous).

  Used by the one-click accept flow (#967). Idempotent for the same user.
  """
  @spec accept_staff_invitation(StaffMember.t(), String.t()) ::
          {:ok, StaffMember.t()} | {:error, term()}
  def accept_staff_invitation(%StaffMember{id: id}, user_id) when is_binary(user_id) do
    context_span entity: "staff_member" do
      with {:ok, staff} <- get_staff_member(id) do
        accept_staff_invitation_fresh(staff, user_id)
      end
    end
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
  def assign_staff_to_program(attrs) when is_map(attrs) do
    context_span entity: "program_staff_assignment" do
      with {:ok, staff_member} <- get_staff_member(attrs.staff_member_id),
           assignment_attrs = Map.put(attrs, :assigned_at, DateTime.utc_now()),
           {:ok, assignment} <- insert_program_staff_assignment(assignment_attrs) do
        assignment
        |> ProviderEvents.staff_assigned_to_program(staff_member)
        |> dispatch_assignment_event()

        Logger.info("Staff member assigned to program",
          staff_member_id: assignment.staff_member_id,
          program_id: assignment.program_id
        )

        {:ok, assignment}
      end
    end
  end

  @doc """
  Unassigns a staff member from a program.

  Returns:
  - `{:ok, ProgramStaffAssignment.t()}` on success
  - `{:error, :not_found}` if no active assignment exists
  """
  @spec unassign_staff_from_program(String.t(), String.t()) ::
          {:ok, ProgramStaffAssignment.t()} | {:error, :not_found | term()}
  def unassign_staff_from_program(program_id, staff_member_id)
      when is_binary(program_id) and is_binary(staff_member_id) do
    context_span entity: "program_staff_assignment" do
      with {:ok, staff_member} <- get_staff_member(staff_member_id),
           {:ok, assignment} <- unassign_program_staff_assignment(program_id, staff_member_id) do
        assignment
        |> ProviderEvents.staff_unassigned_from_program(staff_member)
        |> dispatch_assignment_event()

        Logger.info("Staff member unassigned from program",
          staff_member_id: staff_member_id,
          program_id: program_id
        )

        {:ok, assignment}
      end
    end
  end

  # Non-critical fire-and-forget fan-out (no critical_event_handlers entry for
  # these topics → PubSub-only, no Oban durability — preserved from the former
  # AssignStaffToProgram/UnassignStaffFromProgram use cases).
  defp dispatch_assignment_event(event), do: DomainEventBus.dispatch(__MODULE__, event)

  defp insert_program_staff_assignment(attrs) do
    %ProgramStaffAssignment{}
    |> ProgramStaffAssignment.create_changeset(attrs)
    |> Repo.insert()
    |> case do
      {:ok, assignment} ->
        {:ok, assignment}

      {:error, %Ecto.Changeset{} = changeset} ->
        if EctoErrorHelpers.any_unique_constraint_violation?(changeset.errors) do
          {:error, :already_assigned}
        else
          {:error, changeset}
        end
    end
  end

  defp unassign_program_staff_assignment(program_id, staff_member_id) do
    ProgramStaffAssignment
    |> where(
      [a],
      a.program_id == ^program_id and a.staff_member_id == ^staff_member_id and
        is_nil(a.unassigned_at)
    )
    |> Repo.one()
    |> case do
      nil ->
        {:error, :not_found}

      assignment ->
        assignment
        |> ProgramStaffAssignment.unassign_changeset()
        |> Repo.update()
    end
  end

  @doc "Retrieves a provider profile by identity ID."
  def get_provider_by_identity(identity_id) when is_binary(identity_id) do
    case Repo.get_by(ProviderProfile, identity_id: identity_id) do
      nil -> {:error, :not_found}
      profile -> {:ok, profile}
    end
  end

  @doc "Returns true if a provider profile exists for the given identity ID."
  def has_provider_profile?(identity_id) when is_binary(identity_id) do
    Repo.exists?(from p in ProviderProfile, where: p.identity_id == ^identity_id)
  end

  @doc "Returns the provider profile by ID."
  @spec get_provider_profile(String.t()) :: {:ok, ProviderProfile.t()} | {:error, :not_found}
  def get_provider_profile(provider_id) when is_binary(provider_id) do
    case Repo.get(ProviderProfile, provider_id) do
      nil -> {:error, :not_found}
      profile -> {:ok, profile}
    end
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
    case get_provider_profile(provider_id) do
      {:ok, %ProviderProfile{identity_id: identity_id}} -> {:ok, identity_id}
      {:error, :not_found} -> {:error, :not_found}
    end
  end

  @doc "Lists all verified provider IDs (used by projections at bootstrap)."
  def list_verified_provider_ids do
    ids = Repo.all(from p in ProviderProfile, where: p.verified == true, select: p.id)
    {:ok, ids}
  end

  @doc "Returns all verification documents for a provider."
  @spec get_provider_verification_documents(String.t()) :: {:ok, [VerificationDocument.t()]}
  def get_provider_verification_documents(provider_profile_id) when is_binary(provider_profile_id) do
    docs =
      VerificationDocument
      |> where([d], d.provider_profile_id == ^provider_profile_id)
      |> order_by([d], desc: d.inserted_at)
      |> Repo.all()

    {:ok, docs}
  end

  @doc "Lists all pending verification documents (admin)."
  @spec list_pending_verification_documents() :: {:ok, [VerificationDocument.t()]}
  def list_pending_verification_documents do
    docs =
      VerificationDocument
      |> where([d], d.status == :pending)
      |> order_by([d], asc: d.inserted_at)
      |> Repo.all()

    {:ok, docs}
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
          {:ok, [VerificationDocument.admin_review_result()]}
  def list_verification_documents_for_admin(status \\ nil) do
    results =
      status
      |> admin_review_query()
      |> Repo.all()
      |> Enum.map(&to_admin_review_result/1)

    {:ok, results}
  end

  @doc "Returns a single verification document with provider info for admin review."
  @spec get_verification_document_for_admin(String.t()) ::
          {:ok, VerificationDocument.admin_review_result()} | {:error, :not_found}
  def get_verification_document_for_admin(document_id) do
    admin_review_base_query()
    |> where([d], d.id == ^document_id)
    |> Repo.one()
    |> case do
      nil -> {:error, :not_found}
      row -> {:ok, to_admin_review_result(row)}
    end
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
    with {:ok, result} <- get_verification_document_for_admin(document_id) do
      signed_url = verified_preview_url(result.document.file_url)
      preview_type = verification_preview_type(result.document.original_filename)
      {:ok, Map.merge(result, %{signed_url: signed_url, preview_type: preview_type})}
    end
  end

  @doc "Returns the list of valid verification document types."
  defdelegate valid_document_types,
    to: VerificationDocument

  # --- Verification document internals ------------------------------------

  @required_verification_fields ~w(provider_profile_id original_filename document_type)a

  defp validate_verification_submission(params) do
    errors =
      Enum.reduce(@required_verification_fields, [], fn field, acc ->
        case params[field] do
          val when is_binary(val) and byte_size(val) > 0 -> acc
          _ -> [{field, "is required"} | acc]
        end
      end)

    errors =
      if is_nil(params[:file_binary]), do: [{:file_binary, "is required"} | errors], else: errors

    case errors do
      [] -> :ok
      _ -> {:error, errors}
    end
  end

  defp upload_verification_file(params) do
    path =
      Storage.build_timestamped_path(
        "verification-docs/providers",
        params[:provider_profile_id],
        params[:original_filename],
        "document.pdf"
      )

    opts =
      [content_type: params[:content_type] || "application/octet-stream"]
      |> Keyword.merge(Map.get(params, :storage_opts, []))

    Storage.upload(:private, path, params[:file_binary], opts)
  end

  defp insert_verification_document(params, file_url) do
    %{
      provider_profile_id: params[:provider_profile_id],
      document_type: params[:document_type],
      file_url: file_url,
      original_filename: params[:original_filename]
    }
    |> VerificationDocument.create_changeset()
    |> Repo.insert()
  end

  defp validate_rejection_reason(reason) when is_binary(reason) and byte_size(reason) > 0, do: :ok
  defp validate_rejection_reason(_), do: {:error, :reason_required}

  defp get_verification_document(id) do
    case Repo.get(VerificationDocument, id) do
      nil -> {:error, :not_found}
      doc -> {:ok, doc}
    end
  end

  # Persists the review decision by casting the transitioned fields onto the
  # original (still-pending) record, so Ecto sees a real status change.
  defp persist_verification_review(%VerificationDocument{} = original, %VerificationDocument{} = updated) do
    attrs = Map.take(updated, [:status, :rejection_reason, :reviewed_by_id, :reviewed_at])

    original
    |> VerificationDocument.review_changeset(attrs)
    |> Repo.update()
  end

  defp dispatch_verification_event(event_name, doc, reviewer_id) do
    DomainEvent.new(
      event_name,
      doc.id,
      :verification_document,
      %{provider_id: doc.provider_profile_id, reviewer_id: reviewer_id}
    )
    |> EventDispatchHelper.dispatch(KlassHero.Provider)
  end

  defp admin_review_base_query do
    from d in VerificationDocument,
      join: p in ProviderProfile,
      on: d.provider_profile_id == p.id,
      select: {d, p.business_name}
  end

  # Persists a create by validating at the domain boundary, then mapping the
  # unique-identity violation back to the frozen :duplicate_resource contract
  # (ProviderEventHandler/Accounts depend on that literal atom).
  defp insert_provider_profile(attrs) do
    %ProviderProfile{}
    |> ProviderProfile.changeset(attrs)
    |> Repo.insert()
    |> case do
      {:ok, profile} ->
        {:ok, profile}

      {:error, %Ecto.Changeset{errors: errors} = changeset} ->
        if EctoErrorHelpers.unique_constraint_violation?(errors, :identity_id) do
          {:error, :duplicate_resource}
        else
          {:error, changeset}
        end
    end
  end

  # Persists a transitioned profile by casting the changed scalar fields onto the
  # originally-loaded record, so Ecto sees real changes (and auto-bumps updated_at).
  defp persist_provider_profile(%ProviderProfile{} = original, %ProviderProfile{} = updated) do
    attrs = Map.take(updated, @profile_persist_fields)

    original
    |> ProviderProfile.changeset(attrs)
    |> Repo.update()
  end

  defp publish_verification_event(profile, admin_id, :verified) do
    profile
    |> ProviderEvents.provider_verified(admin_id)
    |> IntegrationEventPublishing.publish()
  end

  defp publish_verification_event(profile, admin_id, :unverified) do
    profile
    |> ProviderEvents.provider_unverified(admin_id)
    |> IntegrationEventPublishing.publish()
  end

  # :pending orders oldest-first (FIFO); nil and other statuses order newest-first.
  defp admin_review_query(nil), do: order_by(admin_review_base_query(), [d], desc: d.inserted_at)

  defp admin_review_query(:pending) do
    admin_review_base_query()
    |> where([d], d.status == :pending)
    |> order_by([d], asc: d.inserted_at)
  end

  defp admin_review_query(status) when is_atom(status) do
    admin_review_base_query()
    |> where([d], d.status == ^status)
    |> order_by([d], desc: d.inserted_at)
  end

  defp to_admin_review_result({%VerificationDocument{} = doc, business_name}) do
    %{document: doc, provider_business_name: business_name}
  end

  # Checks existence before signing: signed_url/3 is URL math and succeeds even
  # for missing files, which would render broken previews.
  defp verified_preview_url(file_url) when is_binary(file_url) do
    with {:ok, true} <- Storage.file_exists?(:private, file_url),
         {:ok, url} <- Storage.signed_url(:private, file_url, 900) do
      url
    else
      {:ok, false} ->
        Logger.warning("[Provider] Verification preview file not found in storage: #{file_url}")
        nil

      {:error, reason} ->
        Logger.error("[Provider] Failed to generate verification preview URL for #{file_url}: #{inspect(reason)}")

        nil
    end
  end

  defp verified_preview_url(_), do: nil

  defp verification_preview_type(filename) when is_binary(filename) do
    filename
    |> String.downcase()
    |> Path.extname()
    |> case do
      ext when ext in ~w(.jpg .jpeg .png .gif .webp) -> :image
      ".pdf" -> :pdf
      _ -> :other
    end
  end

  defp verification_preview_type(_), do: :other

  @doc "Retrieves a single staff member by ID."
  @spec get_staff_member(String.t()) :: {:ok, StaffMember.t()} | {:error, :not_found}
  def get_staff_member(staff_id) when is_binary(staff_id) do
    case Repo.get(StaffMember, staff_id) do
      nil -> {:error, :not_found}
      staff -> {:ok, StaffMember.load_pay_rate(staff)}
    end
  end

  @doc "Lists all staff members for a provider, ordered by insertion date."
  @spec list_staff_members(String.t()) :: {:ok, [StaffMember.t()]}
  def list_staff_members(provider_id) when is_binary(provider_id) do
    members =
      StaffMember
      |> where([s], s.provider_id == ^provider_id)
      |> order_by([s], asc: s.inserted_at)
      |> Repo.all()
      |> Enum.map(&StaffMember.load_pay_rate/1)

    {:ok, members}
  end

  @doc "Lists active staff members for a provider."
  @spec list_active_staff_members(String.t()) :: {:ok, [StaffMember.t()]}
  def list_active_staff_members(provider_id) when is_binary(provider_id) do
    members =
      StaffMember
      |> where([s], s.provider_id == ^provider_id and s.active == true)
      |> order_by([s], asc: s.inserted_at)
      |> Repo.all()
      |> Enum.map(&StaffMember.load_pay_rate/1)

    {:ok, members}
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
    query = from([s, _p] in active_staff_memberships_query(user_id), limit: 1, select: s)

    case Repo.one(query) do
      nil -> {:error, :not_found}
      staff -> {:ok, StaffMember.load_pay_rate(staff)}
    end
  end

  @doc """
  Lists all active employments of a user as `StaffMembership` read models
  (staff row + employing provider's business name), in the same selection
  order scope resolution uses — the head of the list is the employment the
  scope currently carries. Powers the staff-context switcher (#969).
  """
  @spec list_active_staff_memberships(String.t()) :: {:ok, [StaffMembership.t()]}
  def list_active_staff_memberships(user_id) when is_binary(user_id) do
    memberships =
      from([s, p] in active_staff_memberships_query(user_id),
        select: %StaffMembership{
          staff_member_id: type(s.id, :string),
          provider_id: type(s.provider_id, :string),
          business_name: p.business_name
        }
      )
      |> Repo.all()

    {:ok, memberships}
  end

  @doc """
  Returns true if the given user has any active staff_member row for the given provider.

  Use this for permission checks scoped to a specific provider — unlike
  `get_active_staff_member_by_user/1`, this correctly identifies users who are
  active staff at multiple providers.
  """
  @spec active_staff_for_provider?(String.t(), String.t()) :: boolean()
  def active_staff_for_provider?(provider_id, user_id) when is_binary(provider_id) and is_binary(user_id) do
    from(s in StaffMember,
      where: s.provider_id == ^provider_id and s.user_id == ^user_id and s.active == true
    )
    |> Repo.exists?()
  end

  @doc """
  Returns the staff member matching the given invitation token hash,
  only if invitation_status is :sent. Used by the invitation registration flow.
  """
  @spec get_staff_member_by_token_hash(binary()) :: {:ok, StaffMember.t()} | {:error, :not_found}
  def get_staff_member_by_token_hash(token_hash) when is_binary(token_hash) do
    query =
      from s in StaffMember,
        where: s.invitation_token_hash == ^token_hash and s.invitation_status == :sent

    case Repo.one(query) do
      nil -> {:error, :not_found}
      staff -> {:ok, StaffMember.load_pay_rate(staff)}
    end
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
    filter_programs_by_tags(programs, staff_member.tags)
  end

  @doc "Lists all active staff assignments for a program."
  @spec list_active_assignments_for_program(String.t()) :: [
          ProgramStaffAssignment.t()
        ]
  def list_active_assignments_for_program(program_id) when is_binary(program_id) do
    active_assignments_query()
    |> where([a], a.program_id == ^program_id)
    |> Repo.all()
  end

  @doc """
  Lists active staff members assigned to a program.

  Uses a JOIN through `program_staff_assignments` so staff details arrive in a
  single round-trip, ordered by when each assignment was created.
  """
  @spec list_active_staff_for_program(String.t()) :: [StaffMember.t()]
  def list_active_staff_for_program(program_id) when is_binary(program_id) do
    from(s in StaffMember,
      join: a in ProgramStaffAssignment,
      on: a.staff_member_id == s.id and a.provider_id == s.provider_id,
      where: a.program_id == ^program_id and is_nil(a.unassigned_at) and s.active == true,
      order_by: [asc: a.assigned_at],
      select: s
    )
    |> Repo.all()
    |> Enum.map(&StaffMember.load_pay_rate/1)
  end

  @doc "Lists all active staff assignments for a provider."
  @spec list_active_assignments_for_provider(String.t()) :: [
          ProgramStaffAssignment.t()
        ]
  def list_active_assignments_for_provider(provider_id) when is_binary(provider_id) do
    active_assignments_query()
    |> where([a], a.provider_id == ^provider_id)
    |> Repo.all()
  end

  @doc "Lists all active program assignments for a staff member."
  @spec list_active_assignments_for_staff_member(String.t()) :: [
          ProgramStaffAssignment.t()
        ]
  def list_active_assignments_for_staff_member(staff_member_id) when is_binary(staff_member_id) do
    active_assignments_query()
    |> where([a], a.staff_member_id == ^staff_member_id)
    |> Repo.all()
  end

  # Active assignments (never unassigned), oldest-first — shared base for the
  # three list_active_assignments_* reads above.
  defp active_assignments_query do
    from a in ProgramStaffAssignment,
      where: is_nil(a.unassigned_at),
      order_by: [asc: a.assigned_at]
  end

  @doc "Returns the total completed session count across all programs for a provider."
  @spec get_total_session_count(String.t()) :: non_neg_integer()
  def get_total_session_count(provider_id) when is_binary(provider_id) do
    SessionStatsRepository.get_total_count(provider_id)
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
    ProviderProfile.edit_changeset(provider, attrs)
  end

  @doc "Changeset for the profile completion form — casts a broader set of fields than `change_provider_profile/2`."
  @spec change_provider_profile_completion(ProviderProfile.t(), map()) :: Ecto.Changeset.t()
  def change_provider_profile_completion(%ProviderProfile{} = provider, attrs \\ %{}) do
    ProviderProfile.completion_changeset(provider, attrs)
  end

  @doc "Returns a changeset for tracking staff member form changes."
  def change_staff_member(%StaffMember{} = staff, attrs \\ %{}) do
    StaffMember.edit_changeset(staff, attrs)
  end

  @doc "Returns an empty changeset for a new staff member form."
  def new_staff_member_changeset(attrs \\ %{}) do
    StaffMember.edit_changeset(%StaffMember{}, attrs)
  end

  # --- Staff member internals ---------------------------------------------

  defp create_staff_display_only(attrs) do
    with {:ok, _validated} <- StaffMember.new(attrs),
         {:ok, persisted} <- insert_staff_member(attrs) do
      {:ok, persisted}
    else
      result -> CommandResult.wrap_validation_errors(result)
    end
  end

  defp create_staff_with_invitation(attrs) do
    {raw_token, token_hash} = StaffMember.generate_invitation_token()

    attrs_with_invitation =
      attrs
      |> Map.put(:invitation_status, :pending)
      |> Map.put(:invitation_token_hash, token_hash)

    with {:ok, _validated} <- StaffMember.new(attrs_with_invitation),
         {:ok, persisted} <- insert_staff_member(attrs_with_invitation) do
      emit_or_compensate_staff_invitation(persisted, raw_token)
    else
      result -> CommandResult.wrap_validation_errors(result)
    end
  end

  # Founder self-staffing (#969, ADR-0005): sets linkage/accepted state itself,
  # never accepting them from caller attrs. A race loser's unique-constraint
  # violation is normalised to the same :already_staffed atom as the pre-check.
  defp create_linked_staff_member(provider_id, user_id, attrs) do
    domain_attrs =
      attrs
      |> Map.put_new(:id, Ecto.UUID.generate())
      |> Map.put(:provider_id, provider_id)
      |> Map.put(:user_id, user_id)
      |> Map.put(:invitation_status, :accepted)

    with {:ok, _validated} <- StaffMember.new(domain_attrs),
         {:ok, persisted} <- insert_staff_member(domain_attrs) do
      {:ok, persisted}
    else
      {:error, %Ecto.Changeset{errors: errors}} = result ->
        if Keyword.has_key?(errors, :provider_id) and staff_unique_violation?(errors[:provider_id]) do
          {:error, :already_staffed}
        else
          CommandResult.wrap_validation_errors(result)
        end

      result ->
        CommandResult.wrap_validation_errors(result)
    end
  end

  defp staff_unique_violation?({_msg, meta}), do: meta[:constraint] == :unique

  defp insert_staff_member(attrs) do
    %StaffMember{}
    |> StaffMember.create_changeset(attrs)
    |> Repo.insert()
    |> hydrate_staff_result()
  end

  defp persist_staff_update(%StaffMember{} = existing, attrs) do
    existing
    |> StaffMember.edit_changeset(attrs)
    |> Repo.update()
    |> hydrate_staff_result()
  end

  defp persist_staff_invitation_fields(%StaffMember{} = staff, attrs) do
    staff
    |> StaffMember.invitation_changeset(attrs)
    |> Repo.update()
    |> hydrate_staff_result()
  end

  defp hydrate_staff_result({:ok, %StaffMember{} = staff}), do: {:ok, StaffMember.load_pay_rate(staff)}
  defp hydrate_staff_result({:error, _} = error), do: error

  defp accept_staff_invitation_fresh(%StaffMember{invitation_status: :accepted, user_id: user_id} = staff, user_id) do
    {:ok, staff}
  end

  defp accept_staff_invitation_fresh(%StaffMember{} = staff, user_id) do
    with {:ok, _transitioned} <- StaffMember.transition_invitation(staff, :accepted),
         {:ok, linked} <-
           persist_staff_invitation_fields(staff, %{invitation_status: :accepted, user_id: user_id}),
         {:ok, :selected} <- touch_staff_last_selected(user_id, linked.provider_id) do
      {:ok, linked}
    end
  end

  defp emit_or_compensate_staff_invitation(persisted, raw_token) do
    case emit_staff_invitation(persisted, raw_token) do
      :ok -> {:ok, persisted, raw_token}
      {:error, reason} -> compensate_staff_invitation(persisted, reason)
    end
  end

  # Emits the :staff_member_invited integration event (raw token in payload so
  # the Accounts handler can build the invitation URL without token-storage knowledge).
  defp emit_staff_invitation(staff_member, raw_token) do
    with {:ok, provider} <- get_provider_profile(staff_member.provider_id) do
      staff_member.id
      |> ProviderIntegrationEvents.staff_member_invited(%{
        provider_id: staff_member.provider_id,
        email: staff_member.email,
        first_name: staff_member.first_name,
        last_name: staff_member.last_name,
        business_name: provider.business_name,
        raw_token: raw_token
      })
      |> IntegrationEventPublishing.publish_critical("staff_member_invited",
        staff_member_id: staff_member.id,
        provider_id: staff_member.provider_id
      )
    end
  end

  defp compensate_staff_invitation(staff_member, reason) do
    Logger.warning("[Provider] Staff invitation emission failed, compensating",
      staff_member_id: staff_member.id,
      reason: inspect(reason)
    )

    with {:ok, _failed} <- StaffMember.transition_invitation(staff_member, :failed),
         {:ok, _persisted} <- persist_staff_invitation_fields(staff_member, %{invitation_status: :failed}) do
      {:error, :invitation_emission_failed}
    else
      _ ->
        Logger.error("[Provider] Staff invitation compensation failed",
          staff_member_id: staff_member.id
        )

        {:error, :invitation_emission_failed}
    end
  end

  # Selection ordering for the staff-context switcher (#969): last-selected row
  # wins; users who never selected default to an employer row over their own
  # business (a founder reaches their own business via the provider dashboard).
  defp active_staff_memberships_query(user_id) do
    from s in StaffMember,
      join: p in ProviderProfile,
      on: p.id == s.provider_id,
      where: s.user_id == ^user_id and s.active == true,
      order_by: [
        desc_nulls_last: s.last_selected_at,
        asc: p.identity_id == type(^user_id, :binary_id),
        desc: s.inserted_at,
        # Unique tiebreaker: inserted_at is second-precision, so same-second
        # rows would otherwise order nondeterministically across executions.
        desc: s.id
      ]
  end

  # Bumps last_selected_at directly (no changeset — the column is deliberately
  # absent from every cast list). Returns :not_staffed when the user has no
  # active row at the provider, the single authorization gate for switching.
  defp touch_staff_last_selected(user_id, provider_id) when is_binary(user_id) and is_binary(provider_id) do
    query =
      from s in StaffMember,
        where: s.user_id == ^user_id and s.provider_id == ^provider_id and s.active == true

    case Repo.update_all(query, set: [last_selected_at: DateTime.utc_now()]) do
      {0, _} -> {:error, :not_staffed}
      {_count, _} -> {:ok, :selected}
    end
  end

  defp staff_has_email?(attrs) do
    case attrs[:email] || attrs["email"] do
      nil -> false
      "" -> false
      email when is_binary(email) -> String.trim(email) != ""
      _other -> false
    end
  end

  # Empty tags = staff sees all programs; populated tags restrict to matching categories.
  defp filter_programs_by_tags(programs, []), do: programs

  defp filter_programs_by_tags(programs, tags) when is_list(tags) do
    Enum.filter(programs, &(&1.category in tags))
  end
end
