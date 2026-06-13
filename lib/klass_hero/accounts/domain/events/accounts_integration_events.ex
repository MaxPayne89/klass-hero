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

  - `:staff_user_registered` - Emitted to link a user to their staff membership (critical).
    The Provider context reacts to set `StaffMember.user_id` and accept the invitation —
    no provider profile is created (ADR-0005).
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
  Creates a `user_registered` integration event (critical — Identity depends on this to create profiles).
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
      # base_payload keys win over caller-supplied payload to prevent :user_id overwrite
      Map.merge(payload, base_payload),
      opts
    )
  end

  def user_registered(user_id, _payload, _opts) do
    raise ArgumentError,
          "user_registered/3 requires a non-empty user_id string, got: #{inspect(user_id)}"
  end

  @doc """
  Creates a `user_confirmed` integration event (critical — compensation path ensuring profiles exist before first login).
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
      Map.merge(payload, base_payload),
      opts
    )
  end

  def user_confirmed(user_id, _payload, _opts) do
    raise ArgumentError,
          "user_confirmed/3 requires a non-empty user_id string, got: #{inspect(user_id)}"
  end

  @doc """
  Creates a `user_anonymized` integration event (critical — GDPR cascade must not be lost).
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
      Map.merge(payload, base_payload),
      opts
    )
  end

  def user_anonymized(user_id, _payload, _opts) do
    raise ArgumentError,
          "user_anonymized/3 requires a non-empty user_id string, got: #{inspect(user_id)}"
  end

  @doc """
  Creates a `staff_invitation_sent` integration event (critical — Provider must update staff status).
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
      Map.merge(payload, base_payload),
      opts
    )
  end

  def staff_invitation_sent(staff_member_id, _payload, _opts) do
    raise ArgumentError,
          "staff_invitation_sent/3 requires a non-empty staff_member_id string, got: #{inspect(staff_member_id)}"
  end

  @doc """
  Creates a `staff_invitation_failed` integration event (critical — Provider must update staff status).
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
      Map.merge(payload, base_payload),
      opts
    )
  end

  def staff_invitation_failed(staff_member_id, _payload, _opts) do
    raise ArgumentError,
          "staff_invitation_failed/3 requires a non-empty staff_member_id string, got: #{inspect(staff_member_id)}"
  end

  @doc """
  Creates a `staff_user_registered` integration event (critical — Provider must activate the staff member).
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
      Map.merge(payload, base_payload),
      opts
    )
  end

  def staff_user_registered(user_id, _payload, _opts) do
    raise ArgumentError,
          "staff_user_registered/3 requires a non-empty user_id string, got: #{inspect(user_id)}"
  end
end
