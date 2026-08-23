defmodule KlassHero.Messaging.Authorization do
  @moduledoc """
  The authorisation gate Messaging write commands pass through.

  Answers the three questions a command asks before it writes: which provider
  is this scope acting as, is this user a participant of this conversation, and
  does this scope's plan permit messaging at all. Staff-addition is owned by
  `KlassHero.Messaging.AddAssignedStaff`.
  """

  use KlassHero.Shared.Tracing

  alias KlassHero.Accounts.Scope

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
