defmodule KlassHero.Messaging.Authorization do
  @moduledoc """
  The authorisation gate Messaging commands and reads pass through.

  Answers the three questions a command asks before it writes: which provider is
  this scope acting as, is this user a participant of this conversation, and does
  this scope's plan permit messaging at all.

  Plus the two read gates that are not participant-based: `authorize_admin/1`, for
  platform monitoring, and `authorize_provider_owner/1`, for a business owner reading
  the threads their own staff conduct. Every other read in this context is gated on a
  participant row; those two are gated on `is_admin` and on provider ownership, and
  are deliberately the only such exceptions — see ADR-0021, which requires an
  amendment before a third is added. Staff-addition is owned by
  `KlassHero.Messaging.AddAssignedStaff`.
  """

  use KlassHero.Shared.Tracing

  alias KlassHero.Accounts.Scope
  alias KlassHero.Messaging.Conversation

  require Logger

  @doc """
  Resolves the provider the scope is acting as, and authorises it.

  The `:provider_id` option is a *hint*, not an override: staff scopes carry no
  `scope.provider`, so the acting provider has to come from the caller — but it
  is only accepted once it is bound back to the scope, either as the provider's
  own profile or as an active staff membership.

  Returns `{:error, :not_found}` (not `:unauthorized`) for an unauthorised
  provider so an attacker can't distinguish "not yours" from "doesn't exist".
  """
  @spec resolve_acting_provider(Scope.t(), keyword()) ::
          {:ok, String.t()} | {:error, :missing_provider_id | :not_found}
  def resolve_acting_provider(%Scope{} = scope, opts) do
    provider_id = Keyword.get(opts, :provider_id) || (scope.provider && scope.provider.id)

    authorize_acting_provider(provider_id, scope)
  end

  defp authorize_acting_provider(nil, %Scope{} = scope) do
    Logger.error("Messaging command called without a resolvable provider_id",
      user_id: scope.user.id
    )

    {:error, :missing_provider_id}
  end

  defp authorize_acting_provider(provider_id, %Scope{provider: %{id: provider_id}}), do: {:ok, provider_id}

  # Staff scopes are re-checked against the DB rather than `scope.staff_member`:
  # that field is a mount-time snapshot loaded via get_active_staff_member_by_user/1,
  # which is `limit: 1` and not provider-scoped, so it would authorize a
  # multi-employer staffer against the wrong provider.
  defp authorize_acting_provider(provider_id, %Scope{} = scope) do
    if active_staff_for_provider?(provider_id, scope.user.id) do
      {:ok, provider_id}
    else
      Logger.warning("Scope not authorised to act as provider",
        user_id: scope.user.id,
        provider_id: provider_id
      )

      {:error, :not_found}
    end
  end

  defp active_staff_for_provider?(provider_id, user_id) do
    acl_span source: "messaging", target: "provider" do
      KlassHero.Provider.active_staff_for_provider?(provider_id, user_id)
    end
  end

  @typedoc """
  How a user stands to a provider.

  `:outsider` rather than `:parent` on purpose — not being staff is no evidence of
  being a parent. Parenthood of *this* provider's programmes is a separate fact,
  established by the enrolment check below.
  """
  @type relation :: :owner | :staff | :outsider

  @doc """
  Resolves how `user_id` stands to `provider_id`.

  The one primitive both the compose gate and message attribution are built from.
  `SendMessage` derives a sender's role from this, so permission and attribution
  cannot disagree — they used to be separate computations over different staff
  sets, which is how an unassigned staff member came to send a message that
  rendered as if a parent had sent it (#1348).
  """
  @spec provider_relation(String.t(), String.t()) :: relation()
  def provider_relation(provider_id, user_id) do
    cond do
      provider_owner?(provider_id, user_id) -> :owner
      active_staff_for_provider?(provider_id, user_id) -> :staff
      true -> :outsider
    end
  end

  @doc """
  Is this thread between two of the provider's own people?

  True when *both* principals are the owner or active staff of the conversation's
  provider — the shapes `@compose_rules` calls `:internal`. Derived on read rather
  than stored: the roster changes under a thread that has already been created, and
  a cached flag would be a copy with no source to re-derive from, which is the drift
  shape #1309/#1312/#1320 were all instances of.

  Principals are nullable (a broadcast has none, and the NOT NULL is deferred to
  #1528), so a missing principal answers `false` here rather than reaching
  `provider_relation/2` with a nil user id.
  """
  @spec internal_conversation?(Conversation.t()) :: boolean()
  def internal_conversation?(%Conversation{} = conversation) do
    internal_pair?(
      conversation.provider_id,
      conversation.principal_a_id,
      conversation.principal_b_id
    )
  end

  @doc """
  The same question for two users, before a thread between them exists.

  The compose screen shows the disclosure too, and there is no conversation row to
  read yet — so it asks about the pair it is about to write. Sharing this with
  `internal_conversation?/1` is what stops the notice changing wording the instant
  the first message turns a compose screen into a thread.
  """
  @spec internal_pair?(String.t(), String.t() | nil, String.t() | nil) :: boolean()
  def internal_pair?(_provider_id, a, b) when is_nil(a) or is_nil(b), do: false

  def internal_pair?(provider_id, user_a_id, user_b_id) do
    provider_relation(provider_id, user_a_id) != :outsider and
      provider_relation(provider_id, user_b_id) != :outsider
  end

  defp provider_owner?(provider_id, user_id) do
    owner =
      acl_span source: "messaging", target: "provider" do
        KlassHero.Provider.get_identity_id_for_provider(provider_id)
      end

    match?({:ok, ^user_id}, owner)
  end

  # Who may open a thread with whom, as a table over {initiator, target}.
  #
  # Reading down the rows is the whole permission model, and a pair that is not
  # listed is refused — so a new direction is added here, deliberately, rather
  # than falling out of some scope shape that happens to reach a clause.
  #
  # The provider-side pairs need no extra fact: computing both relations against
  # this provider has already proved the employment.
  @compose_rules %{
    # a parent writes to the business
    {:outsider, :owner} => :entitled,
    # the business writes to a parent
    {:owner, :outsider} => :enrolled,
    # an instructor writes to a parent
    {:staff, :outsider} => :enrolled,
    # the business writes to its team
    {:owner, :staff} => :internal,
    # a team member writes to the business
    {:staff, :owner} => :internal,
    # two team members
    {:staff, :staff} => :internal
  }

  @doc """
  Authorises `scope` opening a thread with `target_user_id` at `provider_id`.

  `program_id` is consumed only by the `:enrolled` rule, which is why a
  provider-staff thread needs none.
  """
  @spec authorize_compose(Scope.t(), String.t(), String.t(), String.t() | nil) ::
          :ok | {:error, :unauthorized}
  # A thread is between two people, and one person is not two. This has to be a
  # clause rather than a missing table row: the relation pairs a self-target
  # produces — {:staff, :staff}, {:owner, :owner} — cannot distinguish "me and my
  # colleague" from "me and me". Left to the table, `{:staff, :staff}` authorises
  # it, `principal_pair/2` collapses to `{id, id}`, and the ordering check rejects
  # it in Postgres as a 500 from a URL anyone can edit by hand.
  def authorize_compose(%Scope{user: %{id: user_id}} = scope, _provider_id, user_id, _program_id) do
    refuse(scope)
  end

  def authorize_compose(%Scope{} = scope, provider_id, target_user_id, program_id) do
    initiator = provider_relation(provider_id, scope.user.id)
    target = provider_relation(provider_id, target_user_id)

    @compose_rules
    |> Map.get({initiator, target})
    |> check_compose_rule(scope, target_user_id, program_id)
  end

  defp check_compose_rule(:internal, _scope, _target_user_id, _program_id), do: :ok

  defp check_compose_rule(:entitled, scope, _target_user_id, _program_id) do
    if KlassHero.Messaging.can_initiate_messaging?(scope), do: :ok, else: refuse(scope)
  end

  defp check_compose_rule(:enrolled, scope, target_user_id, program_id) do
    if is_binary(program_id) and enrolled?(program_id, target_user_id),
      do: :ok,
      else: refuse(scope)
  end

  defp check_compose_rule(nil, scope, _target_user_id, _program_id), do: refuse(scope)

  defp enrolled?(program_id, parent_user_id) do
    acl_span source: "messaging", target: "enrollment" do
      KlassHero.Enrollment.confirmed_enrollment?(program_id, parent_user_id)
    end
  end

  defp refuse(scope) do
    Logger.debug("Compose refused", user_id: scope.user.id)
    {:error, :unauthorized}
  end

  @doc """
  Verifies that a user is a participant in a conversation.

  Returns `:ok` if the user is a participant, or `{:error, :not_participant}` otherwise.
  """
  @spec verify_participant(String.t(), String.t()) :: :ok | {:error, :not_participant}
  def verify_participant(conversation_id, user_id) do
    if KlassHero.Messaging.participant?(conversation_id, user_id) do
      :ok
    else
      Logger.debug("User not participant in conversation",
        conversation_id: conversation_id,
        user_id: user_id
      )

      {:error, :not_participant}
    end
  end

  @doc """
  Authorises a platform admin to read conversations they are not a participant of.

  One clause, not an ordered fall-through like `Participation.SessionAuthorization`:
  admin is not a fallback from some narrower rule here, it *is* the rule. Nobody is
  narrowly authorised to read every conversation on the platform.

  Callers must ask this **before** they look at a conversation id, so that a
  non-admin's refusal cannot depend on whether the conversation exists (ADR-0017's
  enumeration oracle). Past this gate an admin sees everything, so a later
  `:not_found` discloses nothing they were not already entitled to know.

  `is_admin` is derived, never declared: it lives on the user row and is absent from
  `registration_changeset`'s cast list, so no request can grant it to itself.
  """
  @spec authorize_admin(Scope.t()) :: :ok | {:error, :unauthorized}
  def authorize_admin(%Scope{user: %{is_admin: true}}), do: :ok

  def authorize_admin(%Scope{} = scope) do
    Logger.warning("Non-admin scope attempted an admin conversation read",
      user_id: scope.user.id
    )

    {:error, :unauthorized}
  end

  @doc """
  Authorises a provider owner to read conversations they are not a participant of.

  The owner counterpart to `authorize_admin/1`, and one clause for the same reason:
  nobody is *narrowly* authorised to read a whole business's correspondence, so there
  is nothing to fall through from.

  Deliberately accepts no `:provider_id` hint, unlike `resolve_acting_provider/2`.
  That hint exists so a staff scope — which carries no `scope.provider` — can act *as*
  its employer on the write path. Honouring it here would let one staff member read
  their coworkers' private threads with parents, the opposite of what this gate is
  for, so the provider can only come from `scope.provider`.

  Returns the provider id rather than `:ok` because, unlike `is_admin`, this grants no
  blanket visibility. The id *is* the read predicate, and a caller holding it must
  still confirm the conversation carries it — see
  `KlassHero.Messaging.GetStaffConversation`.
  """
  @spec authorize_provider_owner(Scope.t()) :: {:ok, String.t()} | {:error, :unauthorized}
  def authorize_provider_owner(%Scope{provider: %{id: id}}), do: {:ok, id}

  def authorize_provider_owner(%Scope{} = scope) do
    Logger.warning("Non-owner scope attempted a staff-conversation read", user_id: scope.user.id)

    {:error, :unauthorized}
  end

  @doc """
  Checks whether the scope's user is entitled to initiate messaging.

  Returns `:ok` if entitled, or `{:error, :not_entitled}` otherwise.

  Accepts optional `metadata` keyword list merged into the Logger call
  so callers can add context (e.g. `provider_id`).
  """
  @spec check_entitlement(Scope.t(), keyword()) :: :ok | {:error, :not_entitled}
  def check_entitlement(%Scope{} = scope, metadata \\ []) do
    if KlassHero.Messaging.can_initiate_messaging?(scope) do
      :ok
    else
      Logger.debug(
        "Not entitled to initiate messaging",
        Keyword.merge([user_id: scope.user.id], metadata)
      )

      {:error, :not_entitled}
    end
  end

  @doc """
  Conditionally checks entitlement based on opts.

  ## Options
  - `:skip_entitlement_check` - When `true`, bypasses the entitlement check.

  Accepts optional `metadata` keyword list forwarded to `check_entitlement/2`.
  """
  # ReplyPrivatelyToBroadcast skips the check: the provider initiated contact, so the parent may reply.
  @spec maybe_check_entitlement(Scope.t(), keyword(), keyword()) :: :ok | {:error, :not_entitled}
  def maybe_check_entitlement(%Scope{} = scope, opts, metadata \\ []) do
    if Keyword.get(opts, :skip_entitlement_check, false) do
      :ok
    else
      check_entitlement(scope, metadata)
    end
  end
end
