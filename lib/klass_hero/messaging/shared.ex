defmodule KlassHero.Messaging.Shared do
  @moduledoc """
  Shared utilities for Messaging use cases.

  Hosts cross-cutting helpers (participant verification, entitlement checks)
  used by multiple commands. Staff-addition is owned by
  `KlassHero.Messaging.AddAssignedStaff`.
  """

  alias KlassHero.Accounts.Scope

  require Logger

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

  @doc "Adds `:program_id` to the attrs map only when a program id is present."
  @spec maybe_put_program_id(map(), String.t() | nil) :: map()
  def maybe_put_program_id(attrs, nil), do: attrs
  def maybe_put_program_id(attrs, program_id), do: Map.put(attrs, :program_id, program_id)
end
