defmodule KlassHero.Enrollment do
  @moduledoc """
  Public API for the Enrollment bounded context.

  Manages program enrollments, capacity policies, participant eligibility, and bulk invite flows.
  Follows Ports & Adapters: this module delegates to use cases in the application layer.
  """

  use KlassHero.Shared.Tracing

  import Ecto.Query, warn: false

  alias KlassHero.Enrollment.Adapters.Driven.ACL.ChildInfoACL
  alias KlassHero.Enrollment.Adapters.Driven.ACL.ParentInfoACL
  alias KlassHero.Enrollment.Adapters.Driven.ACL.ParticipantDetailsACL
  alias KlassHero.Enrollment.Adapters.Driven.ACL.ProgramCatalogACL
  alias KlassHero.Enrollment.Adapters.Driven.ACL.ProgramScheduleACL
  alias KlassHero.Enrollment.Adapters.Driven.Persistence.Queries.EnrollmentQueries
  alias KlassHero.Enrollment.Adapters.Driving.Events.EventHandlers.NotifyLiveViews
  alias KlassHero.Enrollment.BulkEnrollmentInvite
  alias KlassHero.Enrollment.ClaimInvite
  alias KlassHero.Enrollment.Domain.Events.EnrollmentEvents
  alias KlassHero.Enrollment.Domain.Services.EnrollmentClassifier
  alias KlassHero.Enrollment.Enrollment
  alias KlassHero.Enrollment.EnrollmentPolicy
  alias KlassHero.Enrollment.ImportEnrollmentCsv
  alias KlassHero.Enrollment.InviteSingleParticipant
  alias KlassHero.Enrollment.ParticipantPolicy
  alias KlassHero.Enrollment.ParticipantPolicyForm
  alias KlassHero.Enrollment.SingleInviteForm
  alias KlassHero.Family
  alias KlassHero.Repo
  alias KlassHero.Shared.Adapters.Driven.Persistence.EctoErrorHelpers
  alias KlassHero.Shared.EventDispatchHelper
  alias KlassHero.Shared.Outbox

  @active_statuses ~w(pending confirmed)

  @doc """
  Creates a new enrollment.

  Returns `{:ok, Enrollment.t()}`, `{:error, :duplicate_resource}` if an active enrollment
  already exists for the child/program, or `{:error, term()}` on validation failure.
  """
  def create_enrollment(params) when is_map(params) do
    context_span entity: "enrollment" do
      do_create_enrollment(params)
    end
  end

  defp do_create_enrollment(%{identity_id: identity_id} = params) when is_binary(identity_id) do
    with {:ok, parent} <- fetch_parent(identity_id),
         :ok <- ensure_child_belongs_to_parent(params[:child_id], parent.id),
         {:ok, :eligible} <- ensure_eligible(params[:program_id], params[:child_id]) do
      params
      |> build_enrollment_attrs(parent.id)
      |> persist_and_dispatch(identity_id)
    end
  end

  # No identity_id: the caller is the invite saga, which knows the parent profile but
  # not the user behind it. Resolve it, because `enrollment_created` carries
  # parent_user_id and Messaging's enrolled-children read table requires it — passing
  # the missing key through produced an event that crashed that projection on every
  # invite-claimed enrollment.
  defp do_create_enrollment(params) do
    params
    |> build_enrollment_attrs(params[:parent_id])
    |> persist_and_dispatch(params[:identity_id] || parent_user_id(params[:parent_id]))
  end

  defp parent_user_id(nil), do: nil

  defp parent_user_id(parent_id) do
    case Family.get_parents_by_ids([parent_id]) do
      [%{identity_id: identity_id}] -> identity_id
      [] -> nil
    end
  end

  defp fetch_parent(identity_id) do
    case Family.get_parent_by_identity(identity_id) do
      {:ok, parent} -> {:ok, parent}
      {:error, :not_found} -> {:error, :no_parent_profile}
    end
  end

  # Ownership guard (IDOR): child_id is client-supplied; the FK constraint proves
  # the child exists, not that it belongs to this parent.
  defp ensure_child_belongs_to_parent(child_id, parent_id) when is_binary(child_id) do
    if ChildInfoACL.child_belongs_to_parent?(child_id, parent_id) do
      :ok
    else
      {:error, :not_your_child}
    end
  end

  defp ensure_child_belongs_to_parent(_child_id, _parent_id), do: {:error, :not_your_child}

  # 3-tuple {:error, :ineligible, reasons} bubbles verbatim; 2-tuple lookup failures map to
  # :processing_failed (fail-closed when eligibility cannot be verified).
  defp ensure_eligible(program_id, child_id) do
    case check_participant_eligibility(program_id, child_id) do
      {:ok, :eligible} -> {:ok, :eligible}
      {:error, :ineligible, reasons} -> {:error, :ineligible, reasons}
      {:error, _reason} -> {:error, :processing_failed}
    end
  end

  defp build_enrollment_attrs(params, parent_id) do
    %{
      program_id: params[:program_id],
      child_id: params[:child_id],
      parent_id: parent_id,
      status: params[:status] || :pending,
      enrolled_at: params[:enrolled_at] || DateTime.utc_now(),
      subtotal: params[:subtotal],
      vat_amount: params[:vat_amount],
      card_fee_amount: params[:card_fee_amount],
      total_amount: params[:total_amount],
      payment_method: params[:payment_method],
      special_requirements: params[:special_requirements]
    }
  end

  defp persist_and_dispatch(attrs, identity_id) do
    case create_enrollment_with_capacity_check(attrs, attrs[:program_id], identity_id) do
      {:ok, {enrollment, events}} ->
        # Fire-and-forget — a failed same-context handler must not roll back a
        # successful enrollment. Cross-context delivery committed with it.
        Enum.each(events, &EventDispatchHelper.dispatch(&1, __MODULE__))
        {:ok, enrollment}

      error ->
        error
    end
  end

  defp enrollment_created_event(enrollment, identity_id) do
    EnrollmentEvents.enrollment_created(enrollment.id, %{
      enrollment_id: enrollment.id,
      child_id: enrollment.child_id,
      parent_id: enrollment.parent_id,
      parent_user_id: identity_id,
      program_id: enrollment.program_id,
      status: enrollment.status
    })
  end

  @doc """
  Cancels an enrollment by admin action.

  Only pending/confirmed enrollments may be cancelled. Dispatches `enrollment_cancelled`.

  Returns `{:ok, Enrollment.t()}`, `{:error, :not_found}`, `{:error, :invalid_status_transition}`,
  or `{:error, :invalid_reason}`.
  """
  def cancel_enrollment_by_admin(enrollment_id, admin_id, reason)
      when is_binary(enrollment_id) and is_binary(admin_id) do
    context_span entity: "enrollment" do
      with {:ok, reason} <- Enrollment.ensure_reason_present(reason),
           {:ok, enrollment} <- get_enrollment(enrollment_id),
           {:ok, cancelled} <- Enrollment.cancel(enrollment, reason),
           {:ok, {persisted, events}} <- cancel_with_event(enrollment_id, cancelled, admin_id, reason) do
        Enum.each(events, &EventDispatchHelper.dispatch(&1, __MODULE__))
        {:ok, persisted}
      end
    end
  end

  @doc """
  Confirms a pending enrollment when the owning provider approves it.

  Returns `{:ok, Enrollment.t()}`, `{:error, :not_found}`, `{:error, :unauthorized}`,
  or `{:error, :invalid_status_transition}`.
  """
  def confirm_enrollment(%{enrollment_id: enrollment_id, provider_id: provider_id})
      when is_binary(enrollment_id) and is_binary(provider_id) do
    context_span entity: "enrollment" do
      with {:ok, enrollment_id} <- cast_uuid_or_not_found(enrollment_id),
           {:ok, enrollment} <- get_enrollment(enrollment_id),
           :ok <- authorize_provider(enrollment, provider_id),
           {:ok, confirmed} <- Enrollment.confirm(enrollment),
           {:ok, persisted} <-
             update_enrollment(enrollment_id, %{status: confirmed.status, confirmed_at: confirmed.confirmed_at}) do
        dispatch_confirmation_event(persisted, provider_id)
      end
    end
  end

  # `enrollment_id` arrives from the LiveView `phx-value-id` (DOM-tamperable). Without this
  # guard, `Repo.get/2` raises `Ecto.Query.CastError` on malformed input. `provider_id` is
  # server-trusted (read from `current_scope`).
  defp cast_uuid_or_not_found(id) do
    case Ecto.UUID.cast(id) do
      {:ok, _} -> {:ok, id}
      :error -> {:error, :not_found}
    end
  end

  defp authorize_provider(%Enrollment{program_id: program_id}, provider_id) do
    if ProgramCatalogACL.program_owned_by?(program_id, provider_id) do
      :ok
    else
      {:error, :unauthorized}
    end
  end

  defp dispatch_confirmation_event(%Enrollment{} = persisted, provider_id) do
    dispatch_result =
      persisted.id
      |> EnrollmentEvents.enrollment_confirmed(%{
        enrollment_id: persisted.id,
        program_id: persisted.program_id,
        provider_id: provider_id,
        child_id: persisted.child_id,
        parent_id: persisted.parent_id,
        confirmed_at: persisted.confirmed_at
      })
      |> EventDispatchHelper.dispatch_or_error(__MODULE__)

    case dispatch_result do
      :ok -> {:ok, persisted}
      {:error, _} = err -> err
    end
  end

  @doc """
  Creates or updates the enrollment capacity policy for a program (upsert).
  """
  def set_enrollment_policy(attrs) when is_map(attrs) do
    context_span entity: "enrollment_policy" do
      %EnrollmentPolicy{}
      |> EnrollmentPolicy.changeset(attrs)
      |> Repo.insert(
        on_conflict: {:replace, [:min_enrollment, :max_enrollment, :updated_at]},
        conflict_target: :program_id,
        returning: true
      )
    end
  end

  @doc """
  Creates or updates the participant eligibility policy for a program (upsert).
  """
  def set_participant_policy(attrs) when is_map(attrs) do
    context_span entity: "participant_policy" do
      with {:ok, {policy, events}} <- upsert_policy_with_event(attrs) do
        Enum.each(events, &EventDispatchHelper.dispatch(&1, __MODULE__))
        {:ok, policy}
      end
    end
  end

  defp cancel_with_event(enrollment_id, cancelled, admin_id, reason) do
    Outbox.transact(__MODULE__, fn ->
      fields = %{
        status: cancelled.status,
        cancelled_at: cancelled.cancelled_at,
        cancellation_reason: cancelled.cancellation_reason
      }

      with {:ok, persisted} <- update_enrollment(enrollment_id, fields) do
        event =
          EnrollmentEvents.enrollment_cancelled(persisted.id, %{
            enrollment_id: persisted.id,
            program_id: persisted.program_id,
            child_id: persisted.child_id,
            parent_id: persisted.parent_id,
            admin_id: admin_id,
            reason: reason,
            cancelled_at: persisted.cancelled_at
          })

        {:ok, persisted, [event]}
      end
    end)
  end

  defp upsert_policy_with_event(attrs) do
    Outbox.transact(__MODULE__, fn ->
      with {:ok, policy} <- upsert_participant_policy(attrs) do
        {:ok, policy, [EnrollmentEvents.participant_policy_set(policy.program_id)]}
      end
    end)
  end

  defp upsert_participant_policy(attrs) do
    %ParticipantPolicy{}
    |> ParticipantPolicy.changeset(attrs)
    |> Repo.insert(
      on_conflict:
        {:replace,
         [
           :eligibility_at,
           :min_age_months,
           :max_age_months,
           :allowed_genders,
           :min_grade,
           :max_grade,
           :updated_at
         ]},
      conflict_target: :program_id,
      returning: true
    )
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
    with {:ok, invite} <- get_invite(invite_id),
         {:ok, invite} <- authorize_invite_owner(invite, provider_id),
         {:ok, invite} <- BulkEnrollmentInvite.ensure_resendable(invite),
         {:ok, reset} <- reset_invite_for_resend(invite) do
      # Dedicated event distinguishes single resend from bulk import; EnqueueInviteEmails
      # assigns a fresh token + enqueues the job.
      reset.provider_id
      |> EnrollmentEvents.invite_resend_requested(reset.id, reset.program_id)
      |> EventDispatchHelper.dispatch_or_ok(__MODULE__, reset)
    end
  end

  # Returns :not_found (not :forbidden) on mismatch to avoid leaking invite existence.
  defp authorize_invite_owner(%{provider_id: provider_id} = invite, provider_id), do: {:ok, invite}
  defp authorize_invite_owner(_invite, _provider_id), do: {:error, :not_found}

  @doc """
  Deletes a bulk enrollment invite by ID.

  Verifies the invite belongs to the given provider before deleting.

  Returns `:ok` on success, `{:error, :not_found}`, or `{:error, :delete_failed}`.
  """
  def delete_invite(invite_id, provider_id) when is_binary(invite_id) and is_binary(provider_id) do
    with {:ok, invite} <- get_invite(invite_id),
         {:ok, _invite} <- authorize_invite_owner(invite, provider_id),
         :ok <- delete_invite_record(invite_id) do
      invite.id
      |> EnrollmentEvents.invite_deleted(%{
        invite_id: invite.id,
        program_id: invite.program_id,
        provider_id: invite.provider_id
      })
      |> EventDispatchHelper.dispatch(__MODULE__)

      :ok
    end
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
    case Repo.get(Enrollment, id) do
      nil -> {:error, :not_found}
      enrollment -> {:ok, enrollment}
    end
  end

  @doc """
  Lists all enrollments for a parent, ordered by `enrolled_at` descending.
  """
  def list_parent_enrollments(parent_id) when is_binary(parent_id) do
    EnrollmentQueries.base()
    |> EnrollmentQueries.by_parent(parent_id)
    |> EnrollmentQueries.order_by_enrolled_at_desc()
    |> Repo.all()
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
    case list_active_by_program(program_id) do
      [] ->
        []

      enrollments ->
        child_map = child_map_for(enrollments)
        parent_map = parent_map_for(enrollments)
        Enum.map(enrollments, &build_roster_entry(&1, child_map, parent_map))
    end
  end

  defp list_active_by_program(program_id) do
    EnrollmentQueries.base()
    |> EnrollmentQueries.by_program(program_id)
    |> EnrollmentQueries.active_only()
    |> EnrollmentQueries.order_by_enrolled_at_desc()
    |> Repo.all()
  end

  defp child_map_for(enrollments) do
    enrollments
    |> Enum.map(& &1.child_id)
    |> Enum.uniq()
    |> ChildInfoACL.get_children_by_ids()
    |> Map.new(fn c -> {c.id, c} end)
  end

  defp parent_map_for(enrollments) do
    enrollments
    |> Enum.map(& &1.parent_id)
    |> Enum.uniq()
    |> ParentInfoACL.get_parents_by_ids()
    |> Map.new(fn p -> {p.id, p} end)
  end

  defp build_roster_entry(enrollment, child_map, parent_map) do
    child_name =
      case Map.get(child_map, enrollment.child_id) do
        nil -> "Unknown"
        child -> "#{child.first_name} #{child.last_name}"
      end

    # nil parent_user_id disables the message button in UI (orphaned/deleted parent profile)
    parent_user_id =
      case Map.get(parent_map, enrollment.parent_id) do
        nil -> nil
        parent -> parent.identity_id
      end

    %{
      enrollment_id: enrollment.id,
      child_id: enrollment.child_id,
      child_name: child_name,
      parent_id: enrollment.parent_id,
      parent_user_id: parent_user_id,
      status: enrollment.status,
      enrolled_at: enrollment.enrolled_at
    }
  end

  @doc """
  Lists enriched pending enrollment entries for a provider.

  Accepts either the provider's own id (preferred — resolves the provider's
  programs in the same query) or an explicit list of program IDs (for callers
  that already hold them, e.g. the dashboard's mount).

  Used by the provider dashboard's "Pending enrollments" inbox card to
  surface enrollments awaiting provider approval.
  """
  def list_pending_enrollments_for_provider([]), do: []

  def list_pending_enrollments_for_provider(program_ids) when is_list(program_ids) do
    list_pending(fn query -> where(query, [e], e.program_id in ^program_ids) end)
  end

  def list_pending_enrollments_for_provider(provider_id) when is_binary(provider_id) do
    list_pending(fn query ->
      where(query, [_e, p], p.provider_id == ^Ecto.UUID.dump!(provider_id))
    end)
  end

  # One trip for enrollments + program titles. Querying `programs` directly avoids a
  # ProgramCatalog↔Enrollment dependency cycle (ProgramCatalog already depends on
  # Enrollment for capacity ACL).
  #
  # The two arities filter deliberately different sides of the join: the program_ids
  # arity filters the enrollment's program_id, the provider_id arity the program's
  # provider_id — the only place that link lives.
  defp list_pending(filter_fun) do
    query =
      Enrollment
      |> join(:left, [e], p in "programs", on: type(p.id, :binary_id) == e.program_id)
      |> where([e], e.status == :pending)
      |> select([e, p], {e, p.title})

    query
    |> filter_fun.()
    |> Repo.all()
    |> case do
      [] ->
        []

      rows ->
        child_map = rows |> Enum.map(fn {enrollment, _title} -> enrollment end) |> child_map_for()

        Enum.map(rows, fn {enrollment, title} ->
          build_pending_entry(enrollment, title, child_map)
        end)
    end
  end

  defp build_pending_entry(enrollment, program_title, child_map) do
    child_name =
      case Map.get(child_map, enrollment.child_id) do
        nil -> "Unknown"
        child -> "#{child.first_name} #{child.last_name}"
      end

    %{
      enrollment_id: enrollment.id,
      program_id: enrollment.program_id,
      program_title: program_title,
      child_id: enrollment.child_id,
      child_name: child_name,
      parent_id: enrollment.parent_id,
      enrolled_at: enrollment.enrolled_at
    }
  end

  @doc """
  Returns the provider-scoped PubSub topic for an Enrollment domain event.

  Subscribers (e.g. `DashboardLive`) call this to subscribe to the same
  topic the publisher (`Enrollment.NotifyLiveViews`) derives.
  """
  defdelegate provider_scoped_topic(event_type, provider_id), to: NotifyLiveViews

  @doc """
  Counts active (pending/confirmed) enrollments for a parent in the given month (defaults to current month).
  """
  def count_monthly_bookings(parent_id, month \\ nil) when is_binary(parent_id) do
    date = month || Date.utc_today()
    start_date = Date.beginning_of_month(date)
    end_date = Date.end_of_month(date)

    EnrollmentQueries.base()
    |> EnrollmentQueries.by_parent(parent_id)
    |> EnrollmentQueries.active_only()
    |> EnrollmentQueries.by_date_range(start_date, end_date)
    |> EnrollmentQueries.count()
    |> Repo.one()
  end

  @doc """
  Returns distinct identity IDs of parents with active (pending/confirmed) enrollments in a program.
  Used by the Messaging context for broadcast recipient resolution.
  """
  @spec list_enrolled_identity_ids(String.t()) :: [String.t()]
  def list_enrolled_identity_ids(program_id) when is_binary(program_id) do
    EnrollmentQueries.base()
    |> EnrollmentQueries.by_program(program_id)
    |> EnrollmentQueries.active_only()
    |> select([e], e.parent_id)
    |> distinct(true)
    |> Repo.all()
    |> ParentInfoACL.get_parents_by_ids()
    |> Enum.map(& &1.identity_id)
  end

  @doc """
  Checks if a parent (identified by identity_id) is actively enrolled in a program.

  Returns true if at least one active enrollment (pending or confirmed) exists.
  """
  @spec enrolled?(String.t(), String.t()) :: boolean()
  def enrolled?(program_id, identity_id) when is_binary(program_id) and is_binary(identity_id) do
    case ParentInfoACL.resolve_identity_id(identity_id) do
      nil ->
        false

      parent_id ->
        EnrollmentQueries.base()
        |> EnrollmentQueries.by_program(program_id)
        |> EnrollmentQueries.active_only()
        |> where([e], e.parent_id == ^parent_id)
        |> Repo.exists?()
    end
  end

  # Creates an enrollment with an atomic capacity check. Locks the enrollment policy row
  # (`SELECT FOR UPDATE`) inside a transaction to prevent TOCTOU races where concurrent
  # requests could both pass the capacity check. Falls through to a plain insert when
  # program_id is nil (no policy to lock).
  defp create_enrollment_with_capacity_check(attrs, nil, identity_id) do
    Outbox.transact(__MODULE__, fn ->
      with {:ok, enrollment} <- create_enrollment_record(attrs) do
        {:ok, enrollment, [enrollment_created_event(enrollment, identity_id)]}
      end
    end)
  end

  defp create_enrollment_with_capacity_check(attrs, program_id, identity_id)
       when is_map(attrs) and is_binary(program_id) do
    Ecto.Multi.new()
    |> Ecto.Multi.run(:lock_and_check, fn repo, _changes ->
      query = from(p in EnrollmentPolicy, where: p.program_id == ^program_id, lock: "FOR UPDATE")

      case repo.one(query) do
        nil ->
          {:ok, :unlimited}

        %EnrollmentPolicy{} = policy ->
          active = count_active_enrollments_in_tx(repo, program_id)
          check_capacity(policy, active)
      end
    end)
    |> Ecto.Multi.run(:create, fn _repo, _changes -> create_enrollment_record(attrs) end)
    # Staged in the same Multi as the capacity lock, so an enrollment and the event
    # announcing it cannot disagree about whether it happened.
    |> Ecto.Multi.run(:stage, fn _repo, %{create: enrollment} ->
      event = enrollment_created_event(enrollment, identity_id)
      Outbox.stage(__MODULE__, [event])
      {:ok, [event]}
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{create: enrollment, stage: events}} -> {:ok, {enrollment, events}}
      {:error, :lock_and_check, :program_full, _} -> {:error, :program_full}
      {:error, :create, reason, _} -> {:error, reason}
    end
  end

  defp check_capacity(policy, active) do
    if EnrollmentPolicy.has_capacity?(policy, active) do
      remaining = if policy.max_enrollment, do: policy.max_enrollment - active, else: :unlimited
      {:ok, remaining}
    else
      {:error, :program_full}
    end
  end

  defp count_active_enrollments_in_tx(repo, program_id) do
    from(e in Enrollment,
      where: e.program_id == ^program_id and e.status in ^@active_statuses,
      select: count(e.id)
    )
    |> repo.one()
  end

  defp create_enrollment_record(attrs) do
    %Enrollment{}
    |> Enrollment.create_changeset(attrs)
    |> Repo.insert()
    |> case do
      {:ok, enrollment} ->
        {:ok, enrollment}

      {:error, %Ecto.Changeset{errors: errors} = changeset} ->
        if EctoErrorHelpers.unique_constraint_violation?(errors, :program_id) do
          {:error, :duplicate_resource}
        else
          {:error, changeset}
        end
    end
  end

  defp update_enrollment(id, attrs) do
    case Repo.get(Enrollment, id) do
      nil ->
        {:error, :not_found}

      enrollment ->
        enrollment
        |> Enrollment.update_changeset(attrs)
        |> Repo.update()
    end
  end

  @doc """
  Returns the enrollment policy for a program.
  """
  def get_enrollment_policy(program_id) when is_binary(program_id) do
    case Repo.get_by(EnrollmentPolicy, program_id: program_id) do
      nil -> {:error, :not_found}
      policy -> {:ok, policy}
    end
  end

  @doc """
  Returns remaining enrollment capacity for a program.

  Fetches the policy and active count, then delegates calculation to
  `EnrollmentPolicy.remaining_capacity/2`.

  - `{:ok, non_neg_integer()}` — remaining spots
  - `{:ok, :unlimited}` — no maximum configured
  """
  def remaining_capacity(program_id) when is_binary(program_id) do
    case get_enrollment_policy(program_id) do
      {:error, :not_found} ->
        {:ok, :unlimited}

      {:ok, policy} ->
        {:ok, EnrollmentPolicy.remaining_capacity(policy, count_active_enrollments(program_id))}
    end
  end

  @doc """
  Returns remaining capacity for multiple programs in a single batch query.
  Returns a map of `program_id => remaining_count | :unlimited`.
  """
  def get_remaining_capacities(program_ids) when is_list(program_ids) do
    {policies, active_counts} = fetch_policies_and_active_counts(program_ids)

    Map.new(program_ids, fn id ->
      case Map.get(policies, id) do
        nil -> {id, :unlimited}
        policy -> {id, EnrollmentPolicy.remaining_capacity(policy, Map.get(active_counts, id, 0))}
      end
    end)
  end

  @doc """
  Returns the count of active (pending/confirmed) enrollments for a program.
  """
  def count_active_enrollments(program_id) when is_binary(program_id) do
    from(e in Enrollment,
      where: e.program_id == ^program_id and e.status in ^@active_statuses,
      select: count(e.id)
    )
    |> Repo.one()
  end

  @doc """
  Returns counts of active enrollments for multiple programs in a single batch query.
  Returns a map of `program_id => count`.
  """
  def count_active_enrollments_batch([]), do: %{}

  def count_active_enrollments_batch(program_ids) when is_list(program_ids) do
    counts =
      from(e in Enrollment,
        where: e.program_id in ^program_ids and e.status in ^@active_statuses,
        group_by: e.program_id,
        select: {e.program_id, count(e.id)}
      )
      |> Repo.all()
      |> Map.new()

    # Programs with no enrollments are absent from the GROUP BY result; default to 0.
    Map.new(program_ids, fn id -> {id, Map.get(counts, id, 0)} end)
  end

  @doc """
  Returns enrollment summary (enrolled count + total capacity) for multiple programs
  using only 2 DB queries. Returns a map of `program_id => %{enrolled: integer, capacity: integer | nil}`.

  Use this instead of calling `get_remaining_capacities/1` and `count_active_enrollments_batch/1`
  separately — doing so would issue 3 DB queries for the same data.
  """
  def get_enrollment_summary_batch(program_ids) when is_list(program_ids) do
    {policies, active_counts} = fetch_policies_and_active_counts(program_ids)

    Map.new(program_ids, fn id ->
      active = Map.get(active_counts, id, 0)
      capacity = calculate_capacity(Map.get(policies, id), active)
      {id, %{enrolled: active, capacity: capacity}}
    end)
  end

  defp calculate_capacity(nil, _active), do: nil

  defp calculate_capacity(policy, active) do
    case EnrollmentPolicy.remaining_capacity(policy, active) do
      :unlimited -> nil
      remaining -> active + remaining
    end
  end

  # Shared by get_remaining_capacities/1 and get_enrollment_summary_batch/1 to prevent query drift.
  defp fetch_policies_and_active_counts(program_ids) do
    policies =
      from(p in EnrollmentPolicy, where: p.program_id in ^program_ids)
      |> Repo.all()
      |> Map.new(fn policy -> {to_string(policy.program_id), policy} end)

    {policies, count_active_enrollments_batch(program_ids)}
  end

  @doc """
  Checks whether a child is eligible for a program based on participant restrictions.

  Returns `{:ok, :eligible}` when eligible or no policy exists.
  Returns `{:error, :ineligible, reasons}` with human-readable reason list.
  Returns `{:error, :not_found}` when the child does not exist.
  """
  def check_participant_eligibility(program_id, child_id) when is_binary(program_id) and is_binary(child_id) do
    case get_participant_policy(program_id) do
      {:error, :not_found} ->
        {:ok, :eligible}

      {:ok, %ParticipantPolicy{} = policy} ->
        check_eligibility(policy, program_id, child_id)
    end
  end

  defp check_eligibility(policy, program_id, child_id) do
    with {:ok, details} <- ParticipantDetailsACL.get_participant_details(child_id),
         {:ok, reference_date} <- resolve_reference_date(policy, program_id) do
      participant = %{
        age_months: ParticipantPolicy.age_in_months(details.date_of_birth, reference_date),
        gender: details.gender,
        grade: details.school_grade
      }

      # Map domain {:error, reasons} → public 3-tuple {:error, :ineligible, reasons}.
      case ParticipantPolicy.eligible?(policy, participant) do
        {:ok, :eligible} -> {:ok, :eligible}
        {:error, reasons} -> {:error, :ineligible, reasons}
      end
    end
  end

  # Some programs (e.g. summer camps) evaluate age at program start, not at registration.
  defp resolve_reference_date(%ParticipantPolicy{eligibility_at: "program_start"}, program_id) do
    case ProgramScheduleACL.get_program_start_date(program_id) do
      {:ok, nil} -> {:ok, Date.utc_today()}
      {:ok, date} -> {:ok, date}
      {:error, _} -> {:ok, Date.utc_today()}
    end
  end

  defp resolve_reference_date(%ParticipantPolicy{}, _program_id) do
    {:ok, Date.utc_today()}
  end

  @doc """
  Returns the participant policy for a program.
  """
  def get_participant_policy(program_id) when is_binary(program_id) do
    case Repo.get_by(ParticipantPolicy, program_id: program_id) do
      nil -> {:error, :not_found}
      policy -> {:ok, policy}
    end
  end

  @doc """
  Lists all bulk enrollment invites for a program, ordered by child last name.

  Returns `{:ok, [invite]}` or `{:ok, []}` if no invites exist.
  """
  def list_program_invites(program_id) when is_binary(program_id) do
    invites =
      BulkEnrollmentInvite
      |> where([i], i.program_id == ^program_id)
      |> order_by([i], asc: i.child_last_name, asc: i.child_first_name)
      |> Repo.all()

    {:ok, invites}
  end

  @doc """
  Returns the count of bulk enrollment invites for a program.
  """
  def count_program_invites(program_id) when is_binary(program_id) do
    BulkEnrollmentInvite
    |> where([i], i.program_id == ^program_id)
    |> Repo.aggregate(:count)
  end

  # === Bulk enrollment invite persistence (used by the invite orchestrators,
  # workers, and integration event handlers, all internal to this context) ===

  @doc "Fetches an invite by id. Returns `{:ok, invite}` or `{:error, :not_found}`."
  def get_invite(id) when is_binary(id) do
    case Repo.get(BulkEnrollmentInvite, id) do
      nil -> {:error, :not_found}
      invite -> {:ok, invite}
    end
  end

  @doc "Fetches an invite by token. Returns `{:ok, invite}` or `{:error, :not_found}`."
  def get_invite_by_token(nil), do: {:error, :not_found}

  def get_invite_by_token(token) when is_binary(token) do
    case Repo.get_by(BulkEnrollmentInvite, invite_token: token) do
      nil -> {:error, :not_found}
      invite -> {:ok, invite}
    end
  end

  @doc "Inserts a single invite from CSV/form import data via `import_changeset/2`."
  def create_invite(attrs) when is_map(attrs) do
    %BulkEnrollmentInvite{}
    |> BulkEnrollmentInvite.import_changeset(attrs)
    |> Repo.insert()
  end

  @doc "Applies a validated status transition to an invite (refetched by id)."
  def transition_invite(%{id: id}, attrs) when is_map(attrs) do
    case Repo.get(BulkEnrollmentInvite, id) do
      nil ->
        {:error, :not_found}

      invite ->
        invite
        |> BulkEnrollmentInvite.transition_changeset(attrs)
        |> Repo.update()
    end
  end

  @doc """
  Resets a resendable invite to pending, clearing its token and sent metadata.
  Bypasses `transition_changeset` intentionally — this is a reverse reset.
  """
  def reset_invite_for_resend(%{id: id, status: status}) when status in [:pending, :invite_sent, :failed] do
    case Repo.get(BulkEnrollmentInvite, id) do
      nil ->
        {:error, :not_found}

      invite ->
        invite
        |> Ecto.Changeset.change(%{status: :pending, invite_token: nil, invite_sent_at: nil, error_details: nil})
        |> Repo.update()
    end
  end

  def reset_invite_for_resend(%{id: _id}), do: {:error, :not_resendable}

  defp delete_invite_record(id) do
    case Repo.get(BulkEnrollmentInvite, id) do
      nil ->
        {:error, :not_found}

      invite ->
        case Repo.delete(invite) do
          {:ok, _deleted} -> :ok
          {:error, _changeset} -> {:error, :delete_failed}
        end
    end
  end

  @doc "Lists pending invites in the given programs that have no token yet."
  def list_pending_invites_without_token([]), do: []

  def list_pending_invites_without_token(program_ids) when is_list(program_ids) do
    BulkEnrollmentInvite
    |> where([i], i.program_id in ^program_ids and i.status == :pending and is_nil(i.invite_token))
    |> Repo.all()
  end

  @doc "Bulk-assigns tokens to invites in one round-trip. Returns `{:ok, count}`."
  def bulk_assign_invite_tokens([]), do: {:ok, 0}

  # sobelow_skip ["SQL.Query"] — static heredoc; ids/tokens/now bound via $1/$2/$3, no interpolation
  def bulk_assign_invite_tokens(id_token_pairs) when is_list(id_token_pairs) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    {ids, tokens} = Enum.unzip(id_token_pairs)

    sql = """
    UPDATE bulk_enrollment_invites AS b
    SET invite_token = v.token, updated_at = $3::timestamp
    FROM unnest($1::text[], $2::text[]) AS v(id, token)
    WHERE b.id = v.id::uuid
    """

    case Repo.query(sql, [ids, tokens, now]) do
      {:ok, %{num_rows: count}} -> {:ok, count}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc "Returns true if an invite already exists for the case-insensitive natural key."
  def invite_exists?(program_id, guardian_email, child_first_name, child_last_name)
      when is_binary(program_id) and is_binary(guardian_email) and is_binary(child_first_name) and
             is_binary(child_last_name) do
    email_down = String.downcase(guardian_email)
    first_down = String.downcase(child_first_name)
    last_down = String.downcase(child_last_name)

    BulkEnrollmentInvite
    |> where([i], i.program_id == ^program_id)
    |> where([i], fragment("lower(?)", i.guardian_email) == ^email_down)
    |> where([i], fragment("lower(?)", i.child_first_name) == ^first_down)
    |> where([i], fragment("lower(?)", i.child_last_name) == ^last_down)
    |> Repo.exists?()
  end

  @doc "Returns a MapSet of dedup keys for all invites in the given programs."
  def list_existing_invite_keys([]), do: MapSet.new()

  def list_existing_invite_keys(program_ids) when is_list(program_ids) do
    BulkEnrollmentInvite
    |> where([i], i.program_id in ^program_ids)
    |> select([i], {i.program_id, i.guardian_email, i.child_first_name, i.child_last_name})
    |> Repo.all()
    |> MapSet.new(fn {pid, email, first, last} ->
      BulkEnrollmentInvite.dedup_key(pid, email, first, last)
    end)
  end

  @doc """
  Returns a changeset for enrollment policy form validation.
  """
  def new_policy_changeset(attrs \\ %{}) do
    EnrollmentPolicy.changeset(%EnrollmentPolicy{}, attrs)
  end

  @doc """
  Returns a changeset for participant policy form validation.
  """
  def new_participant_policy_changeset(attrs \\ %{}) do
    ParticipantPolicyForm.changeset(%ParticipantPolicyForm{}, attrs)
  end
end
