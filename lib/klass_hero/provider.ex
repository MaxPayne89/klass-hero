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

  alias KlassHero.Provider.Assignments
  alias KlassHero.Provider.Domain.Events.ProviderIntegrationEvents
  alias KlassHero.Provider.Domain.ReadModels.StaffMembership
  alias KlassHero.Provider.Incidents
  alias KlassHero.Provider.Profiles
  alias KlassHero.Provider.Programs
  alias KlassHero.Provider.ProviderProfile
  alias KlassHero.Provider.StaffMember
  alias KlassHero.Provider.Verification
  alias KlassHero.Repo
  alias KlassHero.Shared.CommandResult
  alias KlassHero.Shared.IntegrationEventPublishing

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

  @doc "Creates a new provider profile."
  defdelegate create_provider_profile(attrs), to: Profiles

  @doc "Creates a draft provider profile for a deliberate upgrade (#968, ADR-0005)."
  defdelegate create_draft_provider_profile(identity_id, business_name, business_owner_email),
    to: Profiles

  @doc "Updates an existing provider profile."
  defdelegate update_provider_profile(provider_id, attrs), to: Profiles

  @doc "Completes a draft provider profile (draft → active)."
  defdelegate complete_provider_profile(provider_id, attrs), to: Profiles

  @doc "Submits a verification document for a provider."
  defdelegate submit_verification_document(params), to: Verification

  @doc "Submits an incident report from a provider."
  defdelegate submit_incident_report(params), to: Incidents

  @doc "Lists incident report summaries for a program owned by the given provider."
  defdelegate list_incident_reports_for_program(provider_id, program_id), to: Incidents

  @doc "Retrieves a single incident report by ID (used by the notification worker)."
  defdelegate get_incident_report(id), to: Incidents

  @doc "Approves a verification document (admin only)."
  defdelegate approve_verification_document(document_id, reviewer_id), to: Verification

  @doc "Rejects a verification document with reason (admin only)."
  defdelegate reject_verification_document(document_id, reviewer_id, reason), to: Verification

  @doc "Verifies a provider (admin only)."
  defdelegate verify_provider(provider_id, admin_id), to: Profiles

  @doc "Unverifies a provider (admin only)."
  defdelegate unverify_provider(provider_id, admin_id), to: Profiles

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

  @doc "Assigns a staff member to a program."
  defdelegate assign_staff_to_program(attrs), to: Assignments

  @doc "Unassigns a staff member from a program."
  defdelegate unassign_staff_from_program(program_id, staff_member_id), to: Assignments

  @doc "Retrieves a provider profile by identity ID."
  defdelegate get_provider_by_identity(identity_id), to: Profiles

  @doc "Returns true if a provider profile exists for the given identity ID."
  defdelegate has_provider_profile?(identity_id), to: Profiles

  @doc "Returns the provider profile by ID."
  defdelegate get_provider_profile(provider_id), to: Profiles

  @doc "Gets the user (identity) ID that owns a provider profile ID (used by cross-context consumers)."
  defdelegate get_identity_id_for_provider(provider_id), to: Profiles

  @doc "Lists all verified provider IDs (used by projections at bootstrap)."
  defdelegate list_verified_provider_ids, to: Profiles

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

  @doc "Returns the total completed session count across all programs for a provider."
  defdelegate get_total_session_count(provider_id), to: Programs

  @doc "Lists per-session detail rows for a provider's program from the projection."
  defdelegate list_program_sessions(provider_id, program_id), to: Programs

  @doc "Returns the provider-owned program by ID from the `provider_programs` projection."
  defdelegate get_provider_program(program_id), to: Programs

  @doc "Lists all programs owned by the given provider, ordered by name asc."
  defdelegate list_provider_programs(provider_id), to: Programs

  @doc "Returns a changeset for tracking provider profile form changes (for `to_form()` / `phx-change`)."
  defdelegate change_provider_profile(provider, attrs \\ %{}), to: Profiles

  @doc "Changeset for the profile completion form — casts a broader set of fields than `change_provider_profile/2`."
  defdelegate change_provider_profile_completion(provider, attrs \\ %{}), to: Profiles

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
end
