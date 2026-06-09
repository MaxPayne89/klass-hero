defmodule KlassHero.Accounts.Domain.Events.AccountsIntegrationEvents do
  @moduledoc """
  Factory module for creating Accounts context integration events.

  Integration events are the public contract between bounded contexts.
  They carry stable, versioned payloads with only primitive types.

  ## Events

  - `:user_registered` - Emitted when a new user registers (critical).
    Downstream contexts (e.g. Identity) react to create profiles.

  - `:user_confirmed` - Emitted when a user confirms their email (critical).
    Downstream contexts use this as a compensation path to ensure profiles exist
    before first login.

  - `:user_anonymized` - Emitted when a user is anonymized for GDPR (critical).
    Downstream contexts (e.g. Identity, Messaging) react to anonymize their data.

  - `:staff_invitation_sent` - Emitted when a staff invitation email was sent (critical).
    The Provider context reacts to update the staff member's invitation status.

  - `:staff_invitation_failed` - Emitted when a staff invitation email failed (critical).
    The Provider context reacts to update the staff member's invitation status.

  - `:staff_user_registered` - Emitted when a staff member completes registration (critical).
    The Provider context reacts to activate the staff member.
  """

  alias KlassHero.Shared.Domain.Events.IntegrationEvent

  @typedoc "Payload for `:user_registered` events."
  @type user_registered_payload :: %{required(:user_id) => String.t(), optional(atom()) => term()}

  @typedoc "Payload for `:user_anonymized` events."
  @type user_anonymized_payload :: %{required(:user_id) => String.t(), optional(atom()) => term()}

  @typedoc "Payload for `:staff_invitation_sent` events."
  @type staff_invitation_sent_payload :: %{
          required(:staff_member_id) => String.t(),
          optional(atom()) => term()
        }

  @typedoc "Payload for `:staff_invitation_failed` events."
  @type staff_invitation_failed_payload :: %{
          required(:staff_member_id) => String.t(),
          optional(atom()) => term()
        }

  @typedoc "Payload for `:staff_user_registered` events."
  @type staff_user_registered_payload :: %{
          required(:user_id) => String.t(),
          required(:staff_member_id) => String.t(),
          required(:provider_id) => String.t(),
          optional(atom()) => term()
        }

  @source_context :accounts
  @entity_type :user
  @staff_entity_type :staff_member

  @doc """
  Creates a `user_registered` integration event.

  Marked `:critical` by default — Identity depends on this to create profiles.

  ## Parameters

  - `user_id` - The ID of the registered user
  - `payload` - Additional event-specific data
  - `opts` - Metadata options (correlation_id, causation_id)

  ## Payload Fields

  Standard payload includes:
  - `user_id` - The user's ID

  ## Raises

  - `ArgumentError` if `user_id` is nil or empty

  ## Examples

      iex> event = AccountsIntegrationEvents.user_registered("user-uuid")
      iex> event.event_type
      :user_registered
      iex> event.source_context
      :accounts
      iex> IntegrationEvent.critical?(event)
      true
  """
  def user_registered(user_id, payload \\ %{}, opts \\ [])

  def user_registered(user_id, payload, opts) when is_binary(user_id) and byte_size(user_id) > 0 do
    base_payload = %{user_id: user_id}
    opts = Keyword.put_new(opts, :criticality, :critical)

    IntegrationEvent.new(
      :user_registered,
      @source_context,
      @entity_type,
      user_id,
      # Trigger: caller may pass a conflicting :user_id in payload
      # Why: base_payload contains the canonical user_id from the function argument
      # Outcome: base_payload keys always win, preventing accidental overwrite
      Map.merge(payload, base_payload),
      opts
    )
  end

  def user_registered(user_id, _payload, _opts) do
    raise ArgumentError,
          "user_registered/3 requires a non-empty user_id string, got: #{inspect(user_id)}"
  end

  @doc """
  Creates a `user_confirmed` integration event.

  Marked `:critical` by default — downstream contexts use this as a compensation
  path to ensure profiles exist before first login.

  ## Parameters

  - `user_id` - The ID of the confirmed user
  - `payload` - Additional event-specific data (intended_roles, tier, etc.)
  - `opts` - Metadata options (correlation_id, causation_id)

  ## Raises

  - `ArgumentError` if `user_id` is nil or empty
  """
  def user_confirmed(user_id, payload \\ %{}, opts \\ [])

  def user_confirmed(user_id, payload, opts) when is_binary(user_id) and byte_size(user_id) > 0 do
    base_payload = %{user_id: user_id}
    opts = Keyword.put_new(opts, :criticality, :critical)

    IntegrationEvent.new(
      :user_confirmed,
      @source_context,
      @entity_type,
      user_id,
      # Trigger: caller may pass a conflicting :user_id in payload
      # Why: base_payload contains the canonical user_id from the function argument
      # Outcome: base_payload keys always win, preventing accidental overwrite
      Map.merge(payload, base_payload),
      opts
    )
  end

  def user_confirmed(user_id, _payload, _opts) do
    raise ArgumentError,
          "user_confirmed/3 requires a non-empty user_id string, got: #{inspect(user_id)}"
  end

  @doc """
  Creates a `user_anonymized` integration event.

  Marked `:critical` by default — GDPR cascade must not be lost.

  ## Parameters

  - `user_id` - The ID of the anonymized user
  - `payload` - Additional event-specific data
  - `opts` - Metadata options (correlation_id, causation_id)

  ## Payload Fields

  Standard payload includes:
  - `user_id` - The user's ID

  ## Raises

  - `ArgumentError` if `user_id` is nil or empty

  ## Examples

      iex> event = AccountsIntegrationEvents.user_anonymized("user-uuid")
      iex> event.event_type
      :user_anonymized
      iex> event.source_context
      :accounts
      iex> IntegrationEvent.critical?(event)
      true
  """
  def user_anonymized(user_id, payload \\ %{}, opts \\ [])

  def user_anonymized(user_id, payload, opts) when is_binary(user_id) and byte_size(user_id) > 0 do
    base_payload = %{user_id: user_id}
    opts = Keyword.put_new(opts, :criticality, :critical)

    IntegrationEvent.new(
      :user_anonymized,
      @source_context,
      @entity_type,
      user_id,
      # Trigger: caller may pass a conflicting :user_id in payload
      # Why: base_payload contains the canonical user_id from the function argument
      # Outcome: base_payload keys always win, preventing accidental overwrite
      Map.merge(payload, base_payload),
      opts
    )
  end

  def user_anonymized(user_id, _payload, _opts) do
    raise ArgumentError,
          "user_anonymized/3 requires a non-empty user_id string, got: #{inspect(user_id)}"
  end

  @doc """
  Creates a `staff_invitation_sent` integration event.

  Marked `:critical` by default — the Provider context must update the staff member's status.

  ## Parameters

  - `staff_member_id` - The ID of the staff member whose invitation was sent
  - `payload` - Additional event-specific data (provider_id, etc.)
  - `opts` - Metadata options (correlation_id, causation_id)

  ## Payload Fields

  Standard payload includes:
  - `staff_member_id` - The staff member's ID

  ## Raises

  - `ArgumentError` if `staff_member_id` is nil or empty
  """
  def staff_invitation_sent(staff_member_id, payload \\ %{}, opts \\ [])

  def staff_invitation_sent(staff_member_id, payload, opts)
      when is_binary(staff_member_id) and byte_size(staff_member_id) > 0 do
    base_payload = %{staff_member_id: staff_member_id}
    opts = Keyword.put_new(opts, :criticality, :critical)

    IntegrationEvent.new(
      :staff_invitation_sent,
      @source_context,
      @staff_entity_type,
      staff_member_id,
      # Trigger: caller may pass a conflicting :staff_member_id in payload
      # Why: base_payload contains the canonical staff_member_id from the function argument
      # Outcome: base_payload keys always win, preventing accidental overwrite
      Map.merge(payload, base_payload),
      opts
    )
  end

  def staff_invitation_sent(staff_member_id, _payload, _opts) do
    raise ArgumentError,
          "staff_invitation_sent/3 requires a non-empty staff_member_id string, got: #{inspect(staff_member_id)}"
  end

  @doc """
  Creates a `staff_invitation_failed` integration event.

  Marked `:critical` by default — the Provider context must update the staff member's status.

  ## Parameters

  - `staff_member_id` - The ID of the staff member whose invitation failed
  - `payload` - Additional event-specific data (provider_id, reason, etc.)
  - `opts` - Metadata options (correlation_id, causation_id)

  ## Payload Fields

  Standard payload includes:
  - `staff_member_id` - The staff member's ID

  ## Raises

  - `ArgumentError` if `staff_member_id` is nil or empty
  """
  def staff_invitation_failed(staff_member_id, payload \\ %{}, opts \\ [])

  def staff_invitation_failed(staff_member_id, payload, opts)
      when is_binary(staff_member_id) and byte_size(staff_member_id) > 0 do
    base_payload = %{staff_member_id: staff_member_id}
    opts = Keyword.put_new(opts, :criticality, :critical)

    IntegrationEvent.new(
      :staff_invitation_failed,
      @source_context,
      @staff_entity_type,
      staff_member_id,
      # Trigger: caller may pass a conflicting :staff_member_id in payload
      # Why: base_payload contains the canonical staff_member_id from the function argument
      # Outcome: base_payload keys always win, preventing accidental overwrite
      Map.merge(payload, base_payload),
      opts
    )
  end

  def staff_invitation_failed(staff_member_id, _payload, _opts) do
    raise ArgumentError,
          "staff_invitation_failed/3 requires a non-empty staff_member_id string, got: #{inspect(staff_member_id)}"
  end

  @doc """
  Creates a `staff_user_registered` integration event.

  Marked `:critical` by default — the Provider context must activate the staff member.

  ## Parameters

  - `user_id` - The ID of the newly registered user (staff member)
  - `payload` - Additional event-specific data (staff_member_id, provider_id, etc.)
  - `opts` - Metadata options (correlation_id, causation_id)

  ## Payload Fields

  Standard payload includes:
  - `user_id` - The user's ID

  ## Raises

  - `ArgumentError` if `user_id` is nil or empty

  ## Examples

      iex> event = AccountsIntegrationEvents.staff_user_registered("user-uuid")
      iex> event.event_type
      :staff_user_registered
      iex> event.source_context
      :accounts
      iex> event.entity_type
      :user
      iex> IntegrationEvent.critical?(event)
      true
  """
  def staff_user_registered(user_id, payload \\ %{}, opts \\ [])

  def staff_user_registered(user_id, payload, opts) when is_binary(user_id) and byte_size(user_id) > 0 do
    base_payload = %{user_id: user_id}
    opts = Keyword.put_new(opts, :criticality, :critical)

    IntegrationEvent.new(
      :staff_user_registered,
      @source_context,
      @entity_type,
      user_id,
      # Trigger: caller may pass a conflicting :user_id in payload
      # Why: base_payload contains the canonical user_id from the function argument
      # Outcome: base_payload keys always win, preventing accidental overwrite
      Map.merge(payload, base_payload),
      opts
    )
  end

  def staff_user_registered(user_id, _payload, _opts) do
    raise ArgumentError,
          "staff_user_registered/3 requires a non-empty user_id string, got: #{inspect(user_id)}"
  end
end
