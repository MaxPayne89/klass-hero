defmodule KlassHero.Provider.Staff do
  @moduledoc """
  Staff member commands and queries for the Provider context.

  Covers staff creation (display-only, email-invitation, and founder
  self-staffing), the invitation lifecycle (resend / expire / accept), staff
  reads, the staff-context switcher, and form changesets. Reached through
  `KlassHero.Provider`'s public API.
  """

  use KlassHero.Shared.Tracing

  import Ecto.Query, warn: false

  alias KlassHero.Provider.Events
  alias KlassHero.Provider.Profiles
  alias KlassHero.Provider.ProgramStaffAssignment
  alias KlassHero.Provider.ProviderProfile
  alias KlassHero.Provider.ReadModels.StaffMembership
  alias KlassHero.Provider.StaffMember
  alias KlassHero.Repo
  alias KlassHero.Shared.Adapters.Driven.Persistence.RepositoryHelpers
  alias KlassHero.Shared.CommandResult
  alias KlassHero.Shared.Outbox

  @context KlassHero.Provider

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

  # `active` is deliberately absent: ending an employment link is
  # deactivate_staff_member/1, which clears lead flags, revokes the invitation and
  # stages an event. A profile edit that flipped the same boolean would skip all
  # three (#1237).
  @staff_updatable_fields ~w(first_name last_name role email bio headshot_url tags qualifications
                             pay_rate rate_type rate_amount rate_currency)a

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

  @doc """
  Updates an existing staff member owned by `provider_id`.

  A staff member owned by another provider is indistinguishable from a missing
  one — both return `{:error, :not_found}` (IDOR guard, no existence leak).
  """
  def update_staff_member(provider_id, staff_id, attrs)
      when is_binary(provider_id) and is_binary(staff_id) and is_map(attrs) do
    context_span entity: "staff_member" do
      attrs = Map.take(attrs, @staff_updatable_fields)

      with {:ok, existing} <- get_staff_member(staff_id, provider_id),
           merged = Map.merge(Map.from_struct(existing), attrs),
           {:ok, _validated} <- StaffMember.new(merged),
           {:ok, persisted} <- persist_staff_update(existing, attrs) do
        {:ok, persisted}
      else
        result -> CommandResult.wrap_validation_errors(result)
      end
    end
  end

  @doc """
  Erases a staff member owned by `provider_id` — the narrow hard delete (#1292).

  Removing someone who actually worked here is `offboard_staff_member/1`. This is
  for a row that is provably a data-entry mistake, and it refuses anything else
  with `{:error, :has_history}`. A row qualifies only when it has **no linked
  user**, **no invitation was ever sent**, and **no assignment row ever existed**:

    * an invitation means a real person was told they have a role at this
      business, and
    * an assignment means `staff_assigned_to_program` / `staff_unassigned_from_program`
      events exist naming this `staff_member_id`.

  Deleting under either would leave those pointing at nothing — silently, because
  `program_staff_assignments.staff_member_id` is `on_delete: :delete_all` and a
  cascade runs no changeset and stages no event. That silence *was* #1292.

  The predicate and the delete are one statement, so an invitation sent or an
  assignment created concurrently cannot slip between check and delete. Scoped
  like `get_staff_member/2`, so a foreign row is unreachable rather than fetched
  and then rejected.
  """
  @spec delete_staff_member(String.t(), String.t()) :: :ok | {:error, :not_found | :has_history}
  def delete_staff_member(staff_id, provider_id) when is_binary(staff_id) and is_binary(provider_id) do
    context_span entity: "staff_member" do
      case Repo.delete_all(erasable_scope(staff_id, provider_id)) do
        {1, _} -> :ok
        {0, _} -> classify_refusal(staff_id, provider_id)
      end
    end
  end

  @doc """
  Ids of the provider's staff members that `delete_staff_member/2` would accept.

  Shares the predicate with the delete itself, so the Team tab can only offer the
  action where it would succeed — a UI copy of the rule would drift from it.
  """
  @spec erasable_staff_ids(String.t()) :: MapSet.t(String.t())
  def erasable_staff_ids(provider_id) when is_binary(provider_id) do
    provider_id
    |> erasable_scope()
    |> select([s], s.id)
    |> Repo.all()
    |> MapSet.new()
  end

  defp erasable_scope(staff_id, provider_id) do
    from [staff: s] in erasable_scope(provider_id), where: s.id == ^staff_id
  end

  defp erasable_scope(provider_id) do
    from s in StaffMember,
      as: :staff,
      where: s.provider_id == ^provider_id,
      where: is_nil(s.user_id) and is_nil(s.invitation_status),
      where:
        not exists(
          from a in ProgramStaffAssignment,
            where: a.staff_member_id == parent_as(:staff).id,
            select: 1
        )
  end

  # The delete matched nothing for one of two reasons. Re-reading tells them
  # apart for the caller's error, and goes through the scoped getter so a foreign
  # row still reports as missing rather than as a row that exists but is protected.
  defp classify_refusal(staff_id, provider_id) do
    case get_staff_member(staff_id, provider_id) do
      {:ok, _protected} -> {:error, :has_history}
      {:error, :not_found} -> {:error, :not_found}
    end
  end

  @doc """
  Ends a staff member's employment link — the single definition of deactivation.

  Before this existed, `active` was flipped by a bare cast from four places and
  every consequence had to be remembered at each call site; forgetting one is
  what left a deactivated staff member showing as lead instructor on the public
  program page (#1236). The consequences now live here, in one transaction:

    * the lead-instructor flag on their active assignments is cleared,
    * an outstanding invitation is revoked (it is a live credential), and
    * a `staff_member_deactivated` event is staged, so read tables holding a
      denormalised staff name can clear it — a read filter cannot, because the
      name is a stored column.

  Program Staff Assignments deliberately **survive**: unassigning would strip
  Messaging conversation membership, which reactivation cannot give back.

  Idempotent — an already-inactive member is returned unchanged with nothing
  staged. Takes the struct, so provider-initiated callers scope first through
  `get_staff_member/2`; foreign ≡ missing is that function's guarantee.
  """
  @spec deactivate_staff_member(StaffMember.t()) :: {:ok, StaffMember.t()} | {:error, term()}
  def deactivate_staff_member(%StaffMember{active: false} = staff), do: {:ok, staff}

  def deactivate_staff_member(%StaffMember{} = staff) do
    context_span entity: "staff_member" do
      deactivate_with_event(staff)
    end
  end

  @doc """
  Reinstates a staff member's employment link.

  Deliberately not the mirror image of deactivation: lead-instructor flags stay
  cleared (leading a program is a promotion, not a property of employment) and a
  revoked invitation is not reissued — use `resend_staff_invitation/2`.

  No event is staged, so a read table whose staff name was cleared on
  deactivation stays cleared until the staff member's assignments next change or
  the projection rebuilds. Recomputing "who is currently assigned" incrementally
  would have to re-run the bootstrap's earliest-active-assignment resolution and
  could disagree with it; leaving the field empty is the safe direction.
  """
  @spec reactivate_staff_member(StaffMember.t()) :: {:ok, StaffMember.t()} | {:error, term()}
  def reactivate_staff_member(%StaffMember{active: true} = staff), do: {:ok, staff}

  def reactivate_staff_member(%StaffMember{} = staff) do
    context_span entity: "staff_member" do
      Repo.update(StaffMember.reactivate_changeset(staff))
    end
  end

  defp deactivate_with_event(staff) do
    Outbox.transact(@context, fn ->
      clear_lead_instructor_flags(staff)

      with {:ok, deactivated} <- Repo.update(StaffMember.deactivate_changeset(staff)) do
        {:ok, deactivated, [Events.staff_member_deactivated(deactivated)]}
      end
    end)
  end

  # Scoped to the staff member's own active assignments, so a program whose lead
  # is someone else is untouched. Leaves `unassigned_at` alone — the assignment
  # survives, only the lead responsibility ends.
  defp clear_lead_instructor_flags(%StaffMember{id: staff_id}) do
    from(a in ProgramStaffAssignment,
      where: a.staff_member_id == ^staff_id and a.is_lead_instructor and is_nil(a.unassigned_at)
    )
    |> Repo.update_all(set: [is_lead_instructor: false])
  end

  @doc """
  Resends a staff invitation for a `:failed`/`:expired` member owned by `provider_id`.

  Generates a fresh token, transitions status back to :pending, and re-emits
  :staff_member_invited to restart the invitation saga.

  Returns:
  - `{:ok, StaffMember.t(), raw_token}` on success
  - `{:error, :not_found}` if the staff member does not exist **or is owned by
    another provider** (IDOR guard — the two are indistinguishable)
  - `{:error, :invalid_invitation_transition}` if the current status does not allow resend
  """
  @spec resend_staff_invitation(String.t(), String.t()) ::
          {:ok, StaffMember.t(), String.t()}
          | {:error, :not_found | :invalid_invitation_transition}
  def resend_staff_invitation(provider_id, staff_member_id)
      when is_binary(provider_id) and is_binary(staff_member_id) do
    context_span entity: "staff_member" do
      # Ownership guard (IDOR, see @doc) — mirrors update_staff_member/3 above.
      with {:ok, staff} <- get_staff_member(staff_member_id, provider_id),
           {:ok, _transitioned} <- StaffMember.transition_invitation(staff, :pending),
           {:ok, provider} <- Profiles.get_provider_profile(provider_id),
           {raw_token, token_hash} = StaffMember.generate_invitation_token(),
           {:ok, persisted} <- reissue_invitation(staff, provider, token_hash, raw_token) do
        {:ok, persisted, raw_token}
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

  Stages a `staff_assigned_to_program` per standing assignment (#1312) — see
  `assignment_replay_events/1`. The link and that announcement commit together.
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
  Re-announces every standing assignment of every claimed, active staff member.

  A one-off repair, not a scheduled job. #1312's replay fires on acceptance, so
  it only ever reaches staff who accept after it shipped; anyone already past
  that moment keeps the conversation membership the nil-`staff_user_id` skip
  left them without, and no other trigger exists. That is invisible in the logs —
  the skip is a `Logger.debug` — and permanent, because `conversation_participants`
  has no projection, bootstrap or rebuild.

  Narrower since #1321 than when it was written: the skip used to strand *two*
  things, and the other one — whether Messaging counted the person as staff at
  all — is now derived from `staff_members`, so it repairs itself the moment
  `user_id` is set. Only the participant rows still need re-announcing.

  Safe to re-run: idempotent at every consumer for the same reasons the
  accept-time replay is (see `assignment_replay_events/1`). Returns the number
  of assignments re-announced, which is not the number of staff members — one
  staff member on three programs counts three.

  Unclaimed staff are skipped rather than replayed with a nil `staff_user_id`:
  that is the announcement that failed in the first place, and repeating it
  repairs nothing.
  """
  @spec replay_standing_assignments() :: {:ok, non_neg_integer()}
  def replay_standing_assignments do
    context_span entity: "staff_member" do
      events =
        from(s in StaffMember, where: s.active == true and not is_nil(s.user_id))
        |> Repo.all()
        |> Enum.flat_map(&assignment_replay_events/1)

      Outbox.stage(@context, events)

      {:ok, length(events)}
    end
  end

  @doc """
  Retrieves a staff member owned by `provider_id`; foreign ≡ missing.

  Scoped via `StaffMember.owned_by/2` (see its docs for why). Prefer this over
  `get_staff_member/1` on every provider-initiated path. A malformed `staff_id`
  is `{:error, :not_found}`, not a raise.

  Answers tenancy only, so a **deactivated** member is still returned — which is
  what the employment lifecycle needs (edit, delete, unassign, GDPR erasure all
  target offboarded people). To gate a *new* attachment, use
  `get_active_staff_member/2` instead.
  """
  @spec get_staff_member(String.t(), String.t()) :: {:ok, StaffMember.t()} | {:error, :not_found}
  def get_staff_member(staff_id, provider_id) when is_binary(staff_id) and is_binary(provider_id) do
    provider_id
    |> StaffMember.owned_by()
    |> RepositoryHelpers.get_schema_by_uuid(staff_id)
    |> case do
      {:ok, staff} -> {:ok, StaffMember.load_pay_rate(staff)}
      {:error, :not_found} -> {:error, :not_found}
    end
  end

  @doc """
  Retrieves an **active** staff member owned by `provider_id`; deactivated ≡
  foreign ≡ missing.

  The getter for paths that create a *new* attachment between a staff member and
  a program — `assign_staff_to_program/1`, `set_lead_instructor/3`, and the
  program form's lead pick. Deactivation deliberately leaves existing assignments
  alive (see `deactivate_staff_member/1`) so Messaging membership survives
  reactivation; this blocks new ones without disturbing those.

  Collapsing deactivated into `:not_found` rather than a distinct error is what
  keeps the callers' existing not-found branches correct, and leaks nothing about
  which ids are real. `get_staff_member/2` is the counterpart for lifecycle work.
  """
  @spec get_active_staff_member(String.t(), String.t()) :: {:ok, StaffMember.t()} | {:error, :not_found}
  def get_active_staff_member(staff_id, provider_id) when is_binary(staff_id) and is_binary(provider_id) do
    provider_id
    |> StaffMember.owned_by()
    |> StaffMember.active()
    |> RepositoryHelpers.get_schema_by_uuid(staff_id)
    |> case do
      {:ok, staff} -> {:ok, StaffMember.load_pay_rate(staff)}
      {:error, :not_found} -> {:error, :not_found}
    end
  end

  @doc """
  Retrieves a single staff member by ID, **unscoped**.

  Only for paths with no provider in scope — invitation-token and accept flows,
  and event handlers reacting to a staff id they were handed. Any path that has
  a `provider_id` must use `get_staff_member/2` instead.
  """
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
  User IDs of everyone who has ever held a staff row at the provider, active or not.

  The counterpart to `active_staff_for_provider?/2`: that one answers "may this user
  act now", this one answers "was this user ever one of ours" — the question a reader
  of *past* messages is really asking (#1348). Rows with no `user_id` are unclaimed
  invitations and can never have sent anything.

  Deliberately narrower than `list_staff_members/1`, which returns full structs and
  loads a pay rate per row.
  """
  @spec list_staff_user_ids_for_provider(String.t()) :: [String.t()]
  def list_staff_user_ids_for_provider(provider_id) when is_binary(provider_id) do
    from(s in StaffMember,
      where: s.provider_id == ^provider_id and not is_nil(s.user_id),
      select: s.user_id
    )
    |> Repo.all()
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

  @doc "Returns a changeset for tracking staff member form changes."
  def change_staff_member(%StaffMember{} = staff, attrs \\ %{}) do
    StaffMember.edit_changeset(staff, attrs)
  end

  @doc "Returns an empty changeset for a new staff member form."
  def new_staff_member_changeset(attrs \\ %{}) do
    StaffMember.edit_changeset(%StaffMember{}, attrs)
  end

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
         {:ok, provider} <- Profiles.get_provider_profile(attrs.provider_id),
         {:ok, persisted} <- insert_invited_staff(attrs_with_invitation, provider, raw_token) do
      {:ok, persisted, raw_token}
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
    Outbox.transact(@context, fn ->
      with {:ok, _transitioned} <- StaffMember.transition_invitation(staff, :accepted),
           {:ok, linked} <-
             persist_staff_invitation_fields(staff, %{invitation_status: :accepted, user_id: user_id}),
           {:ok, :selected} <- touch_staff_last_selected(user_id, linked.provider_id) do
        {:ok, linked, assignment_replay_events(linked)}
      end
    end)
  end

  # A program assigned before the invite was claimed emitted its
  # staff_assigned_to_program with a nil staff_user_id, which Messaging skips —
  # leaving the staff member out of that program's conversations for good.
  # Acceptance is when those assignments become addressable, so replay them
  # (#1312). Consumers are idempotent under replay: Messaging upserts on
  # {program_id, staff_user_id}, and ProviderSessionDetails re-resolves from
  # program_staff_assignments rather than trusting the payload.
  #
  # Queried here rather than through Assignments: Staff -> Assignments would
  # close a cycle against the existing Assignments -> Provider -> Staff.
  defp assignment_replay_events(%StaffMember{id: staff_id} = linked) do
    from(a in ProgramStaffAssignment,
      where: a.staff_member_id == ^staff_id and is_nil(a.unassigned_at)
    )
    |> Repo.all()
    |> Enum.map(&Events.staff_assigned_to_program(&1, linked))
  end

  defp insert_invited_staff(attrs, provider, raw_token) do
    Outbox.transact(@context, fn ->
      with {:ok, persisted} <- insert_staff_member(attrs) do
        {:ok, persisted, [staff_invited_event(persisted, provider, raw_token)]}
      end
    end)
  end

  defp reissue_invitation(staff, provider, token_hash, raw_token) do
    Outbox.transact(@context, fn ->
      fields = %{invitation_status: :pending, invitation_token_hash: token_hash}

      with {:ok, persisted} <- persist_staff_invitation_fields(staff, fields) do
        {:ok, persisted, [staff_invited_event(persisted, provider, raw_token)]}
      end
    end)
  end

  # The :staff_member_invited integration event carries the raw token so the Accounts
  # handler can build the invitation URL without token-storage knowledge.
  #
  # The provider is fetched before the write rather than during event construction:
  # the event is staged inside the staff member's own transaction, so anything the
  # event needs has to be in hand before that transaction opens.
  defp staff_invited_event(staff_member, provider, raw_token) do
    Events.staff_member_invited(staff_member.id, %{
      provider_id: staff_member.provider_id,
      email: staff_member.email,
      first_name: staff_member.first_name,
      last_name: staff_member.last_name,
      business_name: provider.business_name,
      raw_token: raw_token
    })
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
