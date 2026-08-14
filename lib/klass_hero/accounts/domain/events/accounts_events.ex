defmodule KlassHero.Accounts.Domain.Events.AccountsEvents do
  @moduledoc """
  Factory for Accounts events. All factories do fail-fast validation and raise
  `ArgumentError` on invalid inputs.

  ## Events

  - `:user_registered` - Emitted when a new user registers.
    Downstream contexts react to create profiles.

  - `:user_confirmed` - Emitted when a user confirms their email.
    Downstream contexts use this as a compensation path to ensure profiles exist
    before first login.

  - `:user_anonymized` - Emitted when a user is anonymized for GDPR.
    Downstream contexts (Family, Messaging) react to anonymize their data.

  - `:staff_invitation_sent` - Emitted when a staff invitation email was sent.
    The Provider context reacts to update the staff member's invitation status.

  - `:staff_invitation_failed` - Emitted when a staff invitation email failed.
    The Provider context reacts to update the staff member's invitation status.

  - `:staff_user_registered` - Emitted to link a user to their staff membership.
    The Provider context reacts to set `StaffMember.user_id` and accept the invitation —
    no provider profile is created (ADR-0005).

  The user events take the user; the staff events take an id, because their
  producers hold one and not the other.
  """

  alias KlassHero.Shared.Domain.Events.Event

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
  Creates a `user_registered` event. Payload includes `email`, `name`, `intended_roles`.
  """
  def user_registered(%{id: _, email: _, name: _} = user, payload \\ %{}, opts \\ []) do
    validate_user_for_registration!(user)

    base_payload = %{
      email: user.email,
      name: user.name,
      intended_roles: Enum.map(Map.get(user, :intended_roles) || [], &Atom.to_string/1)
    }

    build(:user_registered, user.id, base_payload, payload, opts)
  end

  @doc """
  Creates a `user_confirmed` event. Payload includes `email`, `name`, `confirmed_at`, `intended_roles`.
  """
  def user_confirmed(%{id: _, email: _, confirmed_at: _} = user, payload \\ %{}, opts \\ []) do
    validate_user_for_confirmation!(user)

    base_payload = %{
      email: user.email,
      name: Map.get(user, :name),
      # Events serialize to jsonb; ISO8601 string keeps this a scalar
      # so it round-trips with its type intact (see #1010).
      confirmed_at: encode_timestamp(user.confirmed_at),
      intended_roles: Enum.map(Map.get(user, :intended_roles) || [], &Atom.to_string/1)
    }

    build(:user_confirmed, user.id, base_payload, payload, opts)
  end

  @doc """
  Creates a `user_anonymized` event (GDPR cascade must not be lost).
  Requires `previous_email` in payload for audit trail.
  """
  def user_anonymized(user, payload, opts \\ [])

  def user_anonymized(%{id: _} = user, %{previous_email: previous_email} = payload, opts)
      when is_binary(previous_email) and byte_size(previous_email) > 0 do
    validate_user_for_anonymization!(user)

    # Events serialize to jsonb; carry the timestamp as an ISO8601
    # string so it survives the round trip as a scalar (see #1010).
    base_payload = %{
      anonymized_email: Map.get(user, :email),
      anonymized_at: DateTime.to_iso8601(DateTime.utc_now())
    }

    build(:user_anonymized, user.id, base_payload, payload, opts)
  end

  def user_anonymized(%{id: _}, payload, _opts) do
    raise ArgumentError,
          "user_anonymized/3 requires :previous_email in payload, got keys: #{inspect(Map.keys(payload))}"
  end

  @doc """
  Creates a `staff_invitation_sent` event (Provider must update staff status).
  """
  def staff_invitation_sent(staff_member_id, payload \\ %{}, opts \\ [])

  def staff_invitation_sent(staff_member_id, payload, opts)
      when is_binary(staff_member_id) and byte_size(staff_member_id) > 0 do
    staff_event(:staff_invitation_sent, staff_member_id, payload, opts)
  end

  def staff_invitation_sent(staff_member_id, _payload, _opts) do
    raise ArgumentError,
          "staff_invitation_sent/3 requires a non-empty staff_member_id string, got: #{inspect(staff_member_id)}"
  end

  @doc """
  Creates a `staff_invitation_failed` event (Provider must update staff status).
  """
  def staff_invitation_failed(staff_member_id, payload \\ %{}, opts \\ [])

  def staff_invitation_failed(staff_member_id, payload, opts)
      when is_binary(staff_member_id) and byte_size(staff_member_id) > 0 do
    staff_event(:staff_invitation_failed, staff_member_id, payload, opts)
  end

  def staff_invitation_failed(staff_member_id, _payload, _opts) do
    raise ArgumentError,
          "staff_invitation_failed/3 requires a non-empty staff_member_id string, got: #{inspect(staff_member_id)}"
  end

  @doc """
  Creates a `staff_user_registered` event (Provider must activate the staff member).
  """
  def staff_user_registered(user_id, payload \\ %{}, opts \\ [])

  def staff_user_registered(user_id, payload, opts) when is_binary(user_id) and byte_size(user_id) > 0 do
    Event.new(
      :staff_user_registered,
      @source_context,
      @entity_type,
      user_id,
      Map.put(payload, :user_id, user_id),
      opts
    )
  end

  def staff_user_registered(user_id, _payload, _opts) do
    raise ArgumentError,
          "staff_user_registered/3 requires a non-empty user_id string, got: #{inspect(user_id)}"
  end

  # Caller-supplied payload overrides the derived fields, but never the identity:
  # `user_id` is what consumers key on, so it is put last.
  defp build(event_type, user_id, base_payload, payload, opts) do
    Event.new(
      event_type,
      @source_context,
      @entity_type,
      user_id,
      base_payload |> Map.merge(payload) |> Map.put(:user_id, user_id),
      opts
    )
  end

  defp staff_event(event_type, staff_member_id, payload, opts) do
    Event.new(
      event_type,
      @source_context,
      @staff_entity_type,
      staff_member_id,
      Map.put(payload, :staff_member_id, staff_member_id),
      opts
    )
  end

  @typep validation_rule :: :required | :non_empty_string | :non_nil | :list_or_nil

  @spec validate_user!(map(), atom(), [{atom(), validation_rule()}]) :: map()
  defp validate_user!(user, event_name, rules) when is_map(user) do
    Enum.each(rules, fn {field, rule} ->
      value = Map.get(user, field)
      validate_field!(field, value, rule, event_name)
    end)

    user
  end

  defp validate_field!(field, nil, :required, event_name) do
    raise ArgumentError, "User.#{field} cannot be nil for #{event_name} event"
  end

  defp validate_field!(_field, _value, :required, _event_name), do: :ok

  defp validate_field!(field, value, :non_empty_string, event_name) when is_nil(value) or value == "" do
    raise ArgumentError, "User.#{field} cannot be nil or empty for #{event_name} event"
  end

  defp validate_field!(_field, _value, :non_empty_string, _event_name), do: :ok

  defp validate_field!(field, nil, :non_nil, event_name) do
    raise ArgumentError, "User.#{field} cannot be nil for #{event_name} event"
  end

  defp validate_field!(_field, _value, :non_nil, _event_name), do: :ok

  defp validate_field!(field, value, :list_or_nil, event_name) when not is_list(value) and not is_nil(value) do
    raise ArgumentError,
          "User.#{field} must be a list for #{event_name} event, got: #{inspect(value)}"
  end

  defp validate_field!(_field, _value, :list_or_nil, _event_name), do: :ok

  # Encodes a timestamp as an ISO8601 string so it stays a JSON scalar through
  # event serialization (see #1010). Accepts nil defensively — the
  # confirmation validator already rejects a nil `confirmed_at` upstream.
  defp encode_timestamp(%DateTime{} = timestamp), do: DateTime.to_iso8601(timestamp)
  defp encode_timestamp(nil), do: nil

  defp validate_user_for_registration!(user) do
    validate_user!(user, :user_registered, [
      {:id, :required},
      {:email, :non_empty_string},
      {:name, :non_empty_string},
      {:intended_roles, :list_or_nil}
    ])
  end

  defp validate_user_for_confirmation!(user) do
    validate_user!(user, :user_confirmed, [
      {:id, :required},
      {:email, :non_empty_string},
      {:confirmed_at, :non_nil}
    ])
  end

  defp validate_user_for_anonymization!(user) do
    validate_user!(user, :user_anonymized, [
      {:id, :required}
    ])
  end
end
