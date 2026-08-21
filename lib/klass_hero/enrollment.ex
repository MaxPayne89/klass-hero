defmodule KlassHero.Enrollment do
  @moduledoc """
  Public API for the Enrollment bounded context.

  Manages program enrollments, capacity policies, participant eligibility, and bulk invite flows.

  Conventional Phoenix since the flatten (#986–#1002): this module is the imperative shell
  that other contexts call, over schema-as-struct entities. There is no application layer
  and there are no ports.
  """

  use KlassHero.Shared.Tracing

  import Ecto.Query, warn: false

  alias KlassHero.Enrollment.Adapters.Driven.ACL.ProgramCatalogACL
  alias KlassHero.Enrollment.Adapters.Driven.ACL.ProgramScheduleACL
  alias KlassHero.Enrollment.Adapters.Driven.Persistence.Queries.EnrollmentQueries
  alias KlassHero.Enrollment.BulkEnrollmentInvite
  alias KlassHero.Enrollment.ClaimInvite
  alias KlassHero.Enrollment.Domain.Events.EnrollmentEvents
  alias KlassHero.Enrollment.Domain.ReadModels.OutstandingInvite
  alias KlassHero.Enrollment.Domain.Services.EnrollmentClassifier
  alias KlassHero.Enrollment.EnqueueInviteEmails
  alias KlassHero.Enrollment.Enrollment
  alias KlassHero.Enrollment.EnrollmentPolicy
  alias KlassHero.Enrollment.ImportEnrollmentCsv
  alias KlassHero.Enrollment.InviteSingleParticipant
  alias KlassHero.Enrollment.Notifications
  alias KlassHero.Enrollment.ParticipantPolicy
  alias KlassHero.Enrollment.ParticipantPolicyForm
  alias KlassHero.Enrollment.SingleInviteForm
  alias KlassHero.Enrollment.Waivers
  alias KlassHero.Family
  alias KlassHero.ProgramCatalog
  alias KlassHero.Repo
  alias KlassHero.Shared.Adapters.Driven.Persistence.EctoErrorHelpers
  alias KlassHero.Shared.Outbox

  require Logger

  @active_statuses ~w(pending confirmed)

  @doc """
  Creates a new enrollment.

  `params` must carry a `:waivers` intent — `{:accepted, [waiver_version_id]}` when a parent
  signed at the point of enrolling, or `:deferred` when there is no signer present (the
  invite saga). It has no default: `[]` would mean both "signed nothing" and "don't care",
  so an omitted key would silently skip the gate. `:audit` optionally carries
  `:ip_address` and `:user_agent` for the acceptance record.

  Returns `{:ok, Enrollment.t()}`, `{:error, :duplicate_resource}` if an active enrollment
  already exists for the child/program, `{:error, :waiver_intent_required}` when `:waivers`
  is missing, `{:error, :waivers_unsigned}` when a required waiver was not signed, or
  `{:error, term()}` on validation failure.

  Note that a returned `%Ecto.Changeset{}` is no longer necessarily the enrollment's own —
  since the waiver gate joined this transaction it may belong to a `WaiverAcceptance`.
  Callers that render changeset errors should not assume the enrollment schema.
  """
  def create_enrollment(params) when is_map(params) do
    context_span entity: "enrollment" do
      with {:ok, intent} <- Waivers.validate_intent(params) do
        do_create_enrollment(params, intent)
      end
    end
  end

  defp do_create_enrollment(%{identity_id: identity_id} = params, intent) when is_binary(identity_id) do
    with {:ok, parent} <- fetch_parent(identity_id),
         :ok <- ensure_child_belongs_to_parent(params[:child_id], parent.id),
         {:ok, :eligible} <- ensure_eligible(params[:program_id], params[:child_id]) do
      params
      |> build_enrollment_attrs(parent.id)
      |> persist_enrollment(identity_id, waiver_context(params, intent))
    end
  end

  # No identity_id: the caller is the invite saga, which knows the parent profile but
  # not the user behind it. Resolve it, because `enrollment_created` carries
  # parent_user_id and Messaging's enrolled-children read table requires it — passing
  # the missing key through produced an event that crashed that projection on every
  # invite-claimed enrollment.
  defp do_create_enrollment(params, intent) do
    params
    |> build_enrollment_attrs(params[:parent_id])
    |> persist_enrollment(params[:identity_id] || parent_user_id(params[:parent_id]), waiver_context(params, intent))
  end

  defp waiver_context(params, intent) do
    %{intent: intent, audit: params[:audit] || %{}}
  end

  defp parent_user_id(nil), do: nil

  defp parent_user_id(parent_id) do
    case fetch_parents([parent_id]) do
      [%{identity_id: identity_id}] -> identity_id
      [] -> nil
    end
  end

  # Family owns parents and children; Enrollment reads them straight off the facade
  # (ADR 0015). The `acl_span`s keep the cross-context hop visible in traces.
  defp fetch_parents(parent_ids) do
    acl_span source: "enrollment", target: "family" do
      Family.get_parents_by_ids(parent_ids)
    end
  end

  defp fetch_parent_by_identity(identity_id) do
    acl_span source: "enrollment", target: "family" do
      Family.get_parent_by_identity(identity_id)
    end
  end

  defp fetch_children(child_ids) do
    acl_span source: "enrollment", target: "family" do
      Family.get_children_by_ids(child_ids)
    end
  end

  defp fetch_child(child_id) do
    acl_span source: "enrollment", target: "family" do
      Family.get_child_by_id(child_id)
    end
  end

  # An identity without a parent profile is not an error here — it just cannot be
  # enrolled, so callers want `nil` rather than `{:error, :not_found}`.
  defp resolve_parent_id(identity_id) do
    acl_span source: "enrollment", target: "family" do
      case Family.get_parent_by_identity(identity_id) do
        {:ok, parent} -> parent.id
        {:error, :not_found} -> nil
      end
    end
  end

  # Same hop as resolve_parent_id/1, but the create path wants a named failure it can
  # surface rather than a nil.
  defp fetch_parent(identity_id) do
    acl_span source: "enrollment", target: "family" do
      case Family.get_parent_by_identity(identity_id) do
        {:ok, parent} -> {:ok, parent}
        {:error, :not_found} -> {:error, :no_parent_profile}
      end
    end
  end

  # Ownership guard (IDOR): child_id is client-supplied; the FK constraint proves
  # the child exists, not that it belongs to this parent.
  defp ensure_child_belongs_to_parent(child_id, parent_id) when is_binary(child_id) do
    guardian? =
      acl_span source: "enrollment", target: "family" do
        Family.child_belongs_to_parent?(child_id, parent_id)
      end

    if guardian?, do: :ok, else: {:error, :not_your_child}
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

  defp persist_enrollment(attrs, identity_id, waiver_ctx) do
    create_enrollment_with_capacity_check(attrs, attrs[:program_id], identity_id, waiver_ctx)
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
           {:ok, cancelled} <- Enrollment.cancel(enrollment, reason) do
        cancel_with_event(enrollment_id, cancelled, admin_id, reason)
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
        notify_confirmation(persisted, provider_id)
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

  # Previously gated on `dispatch_or_error`, whose only handler was the LiveView
  # notifier — which swallowed every failure and returned :ok. The gate could not
  # fail, so it is gone rather than reproduced.
  defp notify_confirmation(%Enrollment{} = persisted, provider_id) do
    Notifications.enrollment_confirmed(persisted.id, provider_id)
    {:ok, persisted}
  end

  @doc """
  Creates or updates the enrollment capacity policy for a program (upsert).

  Passing an explicit `nil` clears the corresponding limit — the write carries the nils
  into `on_conflict`, so a stored value is replaced rather than left standing (#1370).

  Removing the cap entirely (`max_enrollment` from a number to `nil`) on a program that
  already has active enrollments is refused with `{:error, {:cap_removal_blocked, count}}`
  unless `attrs` carries `acknowledge_cap_removal: true`. The check runs under a
  `FOR UPDATE` lock on the same policy row `create_enrollment_with_capacity_check/3`
  locks, so a booking landing mid-edit serialises against the removal instead of
  slipping past the count.
  """
  def set_enrollment_policy(attrs) when is_map(attrs) do
    context_span entity: "enrollment_policy" do
      Ecto.Multi.new()
      |> Ecto.Multi.run(:guard, fn repo, _changes ->
        guard_cap_removal(
          repo,
          fetch_attr(attrs, :program_id),
          fetch_attr(attrs, :max_enrollment),
          fetch_attr(attrs, :acknowledge_cap_removal) == true
        )
      end)
      |> Ecto.Multi.run(:upsert, fn repo, _changes -> upsert_enrollment_policy(repo, attrs) end)
      |> Repo.transaction()
      |> case do
        {:ok, %{upsert: policy}} -> {:ok, policy}
        {:error, :guard, reason, _changes} -> {:error, reason}
        {:error, :upsert, reason, _changes} -> {:error, reason}
      end
    end
  end

  @doc """
  Reports whether a pending capacity change would remove the cap consequentially.

  The read the provider's form asks before saving, so the warning it shows and the rule
  `set_enrollment_policy/1` enforces come from one predicate and cannot drift.
  """
  @spec assess_capacity_change(String.t(), integer() | nil) :: :ok | {:cap_removal, pos_integer()}
  def assess_capacity_change(program_id, new_max) when is_binary(program_id) do
    with %EnrollmentPolicy{} = policy <- Repo.get_by(EnrollmentPolicy, program_id: program_id),
         true <- EnrollmentPolicy.cap_removal?(policy, new_max),
         active when active > 0 <- count_active_enrollments(program_id) do
      {:cap_removal, active}
    else
      _no_consequence -> :ok
    end
  end

  # No program_id is a changeset error, not a cap removal — let the changeset report it.
  defp guard_cap_removal(_repo, nil, _new_max, _acknowledged?), do: {:ok, :no_program}
  defp guard_cap_removal(_repo, _program_id, _new_max, true), do: {:ok, :acknowledged}

  defp guard_cap_removal(repo, program_id, new_max, false) do
    existing =
      repo.one(from(p in EnrollmentPolicy, where: p.program_id == ^program_id, lock: "FOR UPDATE"))

    if EnrollmentPolicy.cap_removal?(existing, new_max) do
      case count_active_enrollments_in_tx(repo, program_id) do
        0 -> {:ok, :uncontested}
        active -> {:error, {:cap_removal_blocked, active}}
      end
    else
      {:ok, :permitted}
    end
  end

  defp upsert_enrollment_policy(repo, attrs) do
    %EnrollmentPolicy{}
    |> EnrollmentPolicy.changeset(attrs)
    |> repo.insert(
      on_conflict: {:replace, [:min_enrollment, :max_enrollment, :updated_at]},
      conflict_target: :program_id,
      returning: true
    )
  end

  # Callers pass atom-keyed attrs, but a string-keyed map must not read as an absent
  # max_enrollment — that would look like a cap removal and block a save that isn't one.
  defp fetch_attr(attrs, key) do
    case Map.fetch(attrs, key) do
      {:ok, value} -> value
      :error -> Map.get(attrs, Atom.to_string(key))
    end
  end

  @doc """
  Creates or updates the participant eligibility policy for a program (upsert).
  """
  def set_participant_policy(attrs) when is_map(attrs) do
    context_span entity: "participant_policy" do
      with {:ok, policy} <- upsert_policy_with_event(attrs) do
        Notifications.participant_policy_set(policy.program_id)
        {:ok, policy}
      end
    end
  end

  @doc """
  Creates a program waiver and publishes its first version.

  Returns `{:ok, %{waiver: Waiver.t(), version: WaiverVersion.t()}}` or `{:error, :not_found}`
  when the provider does not own the program.
  """
  defdelegate create_waiver(provider_id, attrs), to: Waivers

  @doc "Appends a new version of a waiver's text, leaving the previous version untouched."
  defdelegate publish_waiver_version(provider_id, waiver_id, body), to: Waivers

  @doc "Retires a waiver from future enrollments. Signed acceptances are unaffected."
  defdelegate archive_waiver(provider_id, waiver_id), to: Waivers

  @doc "Lists a program's active waivers, each paired with its current version."
  defdelegate list_program_waivers(program_id), to: Waivers

  @doc "The current version of every required, active waiver on a program."
  defdelegate list_required_waiver_versions(program_id), to: Waivers

  @doc "The waivers in force for an enrollment's program, each marked signed or not."
  defdelegate list_enrollment_waivers(enrollment_id), to: Waivers

  @doc """
  Records signatures on an existing enrollment (the deferred path).

  Only the enrolling parent may sign; anyone else gets `{:error, :not_found}`.
  """
  defdelegate sign_waivers(enrollment_id, parent_id, version_ids, audit), to: Waivers

  @doc "Waiver status per enrollment (`:signed | :unsigned | :not_required`), for the roster."
  defdelegate waiver_status_for_enrollments(enrollment_ids), to: Waivers

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
  invite-email path, so the downstream
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
         {:ok, invite} <- BulkEnrollmentInvite.ensure_resendable(invite) do
      resend_with_fresh_token(invite)
    end
  end

  # The reset clears the old token, so it must not survive a failure to issue a new
  # one — that would leave an invite whose link is dead and whose email never sends.
  # Previously the reset committed first and only the reporting was gated on what
  # followed, so the caller could be told a resend failed that had already half-happened.
  defp resend_with_fresh_token(invite) do
    Ecto.Multi.new()
    |> Ecto.Multi.run(:reset, fn _repo, _changes -> reset_invite_for_resend(invite) end)
    |> Ecto.Multi.run(:enqueue, fn _repo, %{reset: reset} ->
      with :ok <- EnqueueInviteEmails.execute_for_invite(reset.program_id, reset.provider_id, reset.id),
           do: {:ok, :enqueued}
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{reset: reset}} -> {:ok, reset}
      {:error, _step, reason, _changes} -> {:error, reason}
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
         {:ok, _invite} <- authorize_invite_owner(invite, provider_id) do
      delete_invite_record(invite_id)
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
        # A third batched lookup in the shape of the two above — one aggregate query, not
        # one per row.
        waiver_status = Waivers.waiver_status_for_enrollments(Enum.map(enrollments, & &1.id))

        Enum.map(enrollments, &build_roster_entry(&1, child_map, parent_map, waiver_status))
    end
  end

  @doc """
  True when `parent_user_id` has a child holding a confirmed enrollment on the program.

  Answers "may this provider/staff member message that parent?" for a single
  program, the same question the roster UI asks before offering a message button.
  """
  @spec confirmed_enrollment?(String.t(), String.t()) :: boolean()
  def confirmed_enrollment?(program_id, parent_user_id)
      when is_binary(program_id) and is_binary(parent_user_id) do
    case fetch_parent_by_identity(parent_user_id) do
      {:ok, parent} ->
        EnrollmentQueries.base()
        |> EnrollmentQueries.by_program(program_id)
        |> EnrollmentQueries.by_parent(parent.id)
        |> EnrollmentQueries.by_status("confirmed")
        |> Repo.exists?()

      {:error, :not_found} ->
        false
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
    |> fetch_children()
    |> Map.new(fn c -> {c.id, c} end)
  end

  defp parent_map_for(enrollments) do
    enrollments
    |> Enum.map(& &1.parent_id)
    |> Enum.uniq()
    |> fetch_parents()
    |> Map.new(fn p -> {p.id, p} end)
  end

  defp build_roster_entry(enrollment, child_map, parent_map, waiver_status) do
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
      enrolled_at: enrollment.enrolled_at,
      waiver_status: Map.get(waiver_status, enrollment.id, :not_required)
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
  # Enrollment for capacity ACL) — ADR 0015's cycle-breaking case, which is why the
  # join stays here rather than moving behind ProgramCatalogACL: it attaches to
  # Enrollment's own query, so an adapter could only serve it by handing back a
  # composable fragment.
  #
  # The two arities filter deliberately different sides of the join: the program_ids
  # arity filters the enrollment's program_id, the provider_id arity the program's
  # provider_id — the only place that link lives.
  defp list_pending(filter_fun) do
    # Span covers the foreign query alone. Widening it over the rest would nest
    # child_map_for/1's own family-targeted span inside a program_catalog one and
    # bill that hop's time to Program Catalog.
    rows =
      acl_span source: "enrollment", target: "program_catalog" do
        Enrollment
        |> join(:left, [e], p in "programs", on: type(p.id, :binary_id) == e.program_id)
        |> where([e], e.status == :pending)
        |> select([e, p], {e, p.title})
        |> filter_fun.()
        |> Repo.all()
      end

    case rows do
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
  Returns the provider-scoped PubSub topic for an Enrollment notification.

  Subscribers (e.g. `Provider.OverviewLive`) call this to subscribe to the same
  topic `Notifications` publishes on.
  """
  defdelegate provider_scoped_topic(event_type, provider_id), to: Notifications

  @doc """
  Returns the shared PubSub topic carrying participant-policy changes.

  One topic for every program, so subscribers filter on the program id the
  message carries.
  """
  defdelegate participant_policy_topic, to: Notifications

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
  Returns distinct child IDs with active (pending/confirmed) enrollments in a program.

  Used by the Participation context to build attendance rosters.
  """
  @spec list_enrolled_child_ids(String.t()) :: [String.t()]
  def list_enrolled_child_ids(program_id) when is_binary(program_id) do
    EnrollmentQueries.base()
    |> EnrollmentQueries.by_program(program_id)
    |> EnrollmentQueries.active_only()
    |> select([e], e.child_id)
    |> distinct(true)
    |> Repo.all()
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
    |> fetch_parents()
    |> Enum.map(& &1.identity_id)
  end

  @doc """
  Checks if a parent (identified by identity_id) is actively enrolled in a program.

  Returns true if at least one active enrollment (pending or confirmed) exists.
  """
  @spec enrolled?(String.t(), String.t()) :: boolean()
  def enrolled?(program_id, identity_id) when is_binary(program_id) and is_binary(identity_id) do
    case resolve_parent_id(identity_id) do
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
  # No program means no waivers — they are program-scoped, so there is nothing to gate on.
  defp create_enrollment_with_capacity_check(attrs, nil, identity_id, _waiver_ctx) do
    Outbox.transact(__MODULE__, fn ->
      with {:ok, enrollment} <- create_enrollment_record(attrs) do
        {:ok, enrollment, [enrollment_created_event(enrollment, identity_id)]}
      end
    end)
  end

  defp create_enrollment_with_capacity_check(attrs, program_id, identity_id, waiver_ctx)
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
    # Resolved inside the Multi for the same reason the capacity row is locked: a provider
    # publishing a required waiver between a pre-flight check and the insert would otherwise
    # leave an enrollment with an unsigned required waiver.
    |> Ecto.Multi.run(:check_waivers, fn repo, _changes ->
      Waivers.resolve_acceptances(repo, program_id, waiver_ctx.intent)
    end)
    |> Ecto.Multi.run(:create, fn _repo, _changes -> create_enrollment_record(attrs) end)
    |> Ecto.Multi.run(:accept_waivers, fn repo, %{create: enrollment, check_waivers: versions} ->
      signer = %{enrollment_id: enrollment.id, parent_id: enrollment.parent_id}
      Waivers.record_acceptances(repo, versions, signer, waiver_ctx.audit)
    end)
    # Staged in the same Multi as the capacity lock, so an enrollment and the event
    # announcing it cannot disagree about whether it happened.
    |> Ecto.Multi.run(:stage, fn _repo, %{create: enrollment} ->
      Outbox.stage(__MODULE__, [enrollment_created_event(enrollment, identity_id)])
      {:ok, :staged}
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{create: enrollment}} -> {:ok, enrollment}
      {:error, :lock_and_check, :program_full, _} -> {:error, :program_full}
      {:error, :check_waivers, :waivers_unsigned, _} -> {:error, :waivers_unsigned}
      {:error, :accept_waivers, reason, _} -> {:error, reason}
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
    with {:ok, details} <- fetch_child(child_id),
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
  Lists every invite this provider has sent that nobody has accepted yet, across
  all of their programs, oldest first.

  Oldest-first because the list exists to be followed up on: the invite that has
  gone unanswered longest is the one that needs chasing.

  Returns `[%OutstandingInvite{}]` — see that module for why it mirrors the invite
  schema's field names.
  """
  @spec list_outstanding_invites_for_provider(binary()) :: [OutstandingInvite.t()]
  def list_outstanding_invites_for_provider(provider_id) when is_binary(provider_id) do
    # One query for every program's invites. This replaced a per-program
    # `list_program_invites/1` in a `flat_map`, which N+1'd across the dashboard's
    # whole program list on every Overview mount (#1073).
    invites =
      BulkEnrollmentInvite
      |> where([i], i.provider_id == ^provider_id)
      |> where([i], i.status in ^BulkEnrollmentInvite.outstanding_statuses())
      |> order_by([i], asc: i.inserted_at)
      |> Repo.all()

    # Titles come from ProgramCatalog's facade, not a join on its table:
    # `get_titles/1` is batched and documented for exactly this cross-context need,
    # so ADR 0015's direct-read exception does not apply here. (`list_pending/1`
    # above still joins `programs`; its cycle-breaking rationale predates this
    # facade and is worth revisiting separately.)
    titles =
      acl_span source: "enrollment", target: "program_catalog" do
        invites |> Enum.map(& &1.program_id) |> Enum.uniq() |> ProgramCatalog.get_titles()
      end

    for invite <- invites do
      OutstandingInvite.from_invite(invite, Map.get(titles, invite.program_id))
    end
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

  @doc """
  Marks a claimed invite registered, re-reading it under a row lock so the decision is
  made on the row as it stands now and stays true until this transaction commits.

  `ClaimInvite` checks claimability before it opens its transaction; this is the same
  check made again inside it. Two concurrent claims of one token both pass the first
  check, and the loser must be told the invite is spoken for.

  The lock is what makes that reliable. Without it there are two reads — this one and
  `transition_invite/2`'s own refetch — and Postgres runs at READ COMMITTED, so each
  statement takes a fresh snapshot even inside one transaction. The claimability guard
  would then be checked against a row the changeset is not built from: a claim committing
  between the two reads let the guard pass and the transition still be rejected as
  `:registered -> :registered`. `FOR UPDATE` makes the loser block until the winner
  commits, so it re-reads `:registered` and gets `:already_claimed` before any changeset
  exists. Only meaningful inside a transaction, which is how `ClaimInvite` calls it.

  Returns `{:error, :already_claimed}` for an invite that has moved past `:invite_sent`,
  matching what a sequential second claim gets.
  """
  @spec register_claimed_invite(String.t()) ::
          {:ok, BulkEnrollmentInvite.t()}
          | {:error, :not_found | :already_claimed | :invite_transition_failed}
  def register_claimed_invite(invite_id) when is_binary(invite_id) do
    with {:ok, invite} <- get_invite_for_update(invite_id),
         {:ok, invite} <- BulkEnrollmentInvite.ensure_claimable(invite) do
      invite
      |> transition_invite(%{
        status: :registered,
        registered_at: DateTime.utc_now() |> DateTime.truncate(:second)
      })
      |> case do
        {:ok, invite} ->
          {:ok, invite}

        {:error, :not_found} = error ->
          error

        {:error, %Ecto.Changeset{} = changeset} ->
          classify_transition_failure(changeset, invite_id)
      end
    end
  end

  defp get_invite_for_update(id) do
    BulkEnrollmentInvite
    |> where([i], i.id == ^id)
    |> lock("FOR UPDATE")
    |> Repo.one()
    |> case do
      nil -> {:error, :not_found}
      invite -> {:ok, invite}
    end
  end

  # `transition_invite/2` ends in a bare `Repo.update()`, so its changeset would otherwise
  # arrive at `InviteClaimController` raw — the exact shape that 500s (#1215).
  #
  # A `:status` error means the row moved on after `ensure_claimable/1` saw it — someone
  # else claimed the invite — so it earns the same answer a sequential second claim gets.
  # `:already_claimed` tells the guardian "this invite has already been used" and sends
  # them to log in, which is true and actionable; `:invite_transition_failed` only apologises.
  #
  # Keyed on the field, not the error tag, because the race produces the *untagged* variant:
  # `validate_status_transition` matches `{_current, nil}` first, and `get_change/2` is nil
  # when the cast value equals the stored one, so `:registered -> :registered` yields
  # "status change is required for transitions" with no `validation:` opt at all.
  defp classify_transition_failure(%Ecto.Changeset{errors: errors} = changeset, invite_id) do
    if Enum.any?(errors, fn {field, _error} -> field == :status end) do
      Logger.info("[Enrollment] Invite already claimed by a concurrent request",
        invite_id: invite_id
      )

      {:error, :already_claimed}
    else
      Logger.error("[Enrollment] Invite transition failed unexpectedly",
        invite_id: invite_id,
        errors: inspect(changeset.errors)
      )

      {:error, :invite_transition_failed}
    end
  end

  @doc """
  Fails an invite, recording a reason the owning provider can act on.

  The single writer of the failure cause. Before #1290 four call sites across two
  contexts each rebuilt this — the `:failed` atom, the refetch-by-id shape, the
  "a rejected transition means already-terminal" rule, and their own wording — and two
  of them wrote raw `inspect/1` output into a field rendered verbatim to providers.

  `reason` is only ever used to *classify* the failure (see
  `BulkEnrollmentInvite.classify_failure/2`); callers keep logging it themselves for
  diagnostics, which is where an unmapped term belongs.

  `{:error, :already_terminal}` means something else already settled this invite, and
  callers translate it to `:ignore` rather than retrying.

  Use `fail_invite/3` from anything speaking for a dead Oban job; this arity applies no
  staleness check and is for callers acting on the invite's present, not its past.
  """
  @spec fail_invite(binary(), term()) ::
          {:ok, BulkEnrollmentInvite.t()} | {:error, :not_found | :already_terminal}
  def fail_invite(invite_id, reason) when is_binary(invite_id) do
    with {:ok, invite} <- fetch_invite_to_fail(invite_id), do: apply_failure(invite, reason)
  end

  @doc """
  Same, but refuses to fail an invite the provider resent after `enqueued_at`.

  A compensation speaks for a job that is already dead, so between that job's death and
  the compensation running, the provider may have resent the invite — and
  `@valid_transitions` admits `failed: [:pending]`, so nothing else rejects a second
  failure. The result was a resend reverting to Failed under a reason copied from the
  dead job (#1339).

  `enqueued_at` is the job's `inserted_at`. Equality still compensates: a resend and the
  job it enqueues are written by one transaction, so the invite's own job must not read
  as stale against it. That relies on `EnqueueInviteEmails` stamping `inserted_at`
  itself — the column's `now()` default would report transaction start, which precedes
  the reset in the same transaction.
  """
  @spec fail_invite(binary(), term(), DateTime.t()) ::
          {:ok, BulkEnrollmentInvite.t()} | {:error, :not_found | :already_terminal | :superseded}
  def fail_invite(invite_id, reason, %DateTime{} = enqueued_at) when is_binary(invite_id) do
    with {:ok, invite} <- fetch_invite_to_fail(invite_id),
         :ok <- ensure_not_resent_since(invite, enqueued_at) do
      apply_failure(invite, reason)
    end
  end

  defp fetch_invite_to_fail(invite_id) do
    case Repo.get(BulkEnrollmentInvite, invite_id) do
      nil -> {:error, :not_found}
      invite -> {:ok, invite}
    end
  end

  defp ensure_not_resent_since(%BulkEnrollmentInvite{resent_at: nil}, _enqueued_at), do: :ok

  defp ensure_not_resent_since(%BulkEnrollmentInvite{resent_at: resent_at}, enqueued_at) do
    if DateTime.after?(resent_at, enqueued_at), do: {:error, :superseded}, else: :ok
  end

  defp apply_failure(invite, reason) do
    {failure_code, failure_context} = BulkEnrollmentInvite.classify_failure(invite, reason)

    invite
    |> BulkEnrollmentInvite.transition_changeset(%{
      status: :failed,
      failure_code: failure_code,
      failure_context: failure_context
    })
    |> Repo.update()
    |> case do
      {:ok, failed} -> {:ok, failed}
      # `@valid_transitions` admits `:failed` only from a live status, so a rejection
      # here means something already settled this invite. Collapsed rather than
      # reported field-by-field: no caller can act on the difference.
      {:error, %Ecto.Changeset{}} -> {:error, :already_terminal}
    end
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
        # `resent_at` is the watermark every compensation for this invite is measured
        # against, so it must be stamped here — this is the one place the provider
        # reopens an invite the state machine had settled (#1339).
        invite
        |> Ecto.Changeset.change(%{
          status: :pending,
          invite_token: nil,
          invite_sent_at: nil,
          failure_code: nil,
          failure_context: nil,
          # Legacy: an invite that failed before #1340 carries its reason here, and a
          # resend must clear that too or the reopened invite keeps the old sentence.
          error_details: nil,
          resent_at: DateTime.utc_now()
        })
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
