defmodule KlassHero.Accounts.Domain.Events.UserEvents do
  @moduledoc """
  Factory module for creating User domain events.

  Provides convenience functions to create standardized DomainEvent structs
  for user-related events in the Accounts context.

  ## Events

  - `:user_registered` - Emitted when a new user completes registration (critical)
  - `:user_confirmed` - Emitted when a user confirms their email (critical)
  - `:user_email_changed` - Emitted when a user changes their email address
  - `:user_anonymized` - Emitted when a user's account is anonymized for GDPR deletion (critical)

  ## Validation

  Event factories perform fail-fast validation on all inputs:

  - **Aggregate validation**: Required fields must be present and non-empty
  - **Parameter validation**: String parameters must be non-empty
  - **Payload validation**: Required payload fields must be present
  - **Type validation**: All inputs must match expected types

  Validation failures raise `ArgumentError` with descriptive messages.

  ## Usage

      alias KlassHero.Accounts.Domain.Events.UserEvents

      # Create a user_registered event (critical by default)
      event = UserEvents.user_registered(user, %{source: :web})

      # Create with additional metadata
      event = UserEvents.user_confirmed(user, %{}, correlation_id: "abc-123")

      # Invalid - raises ArgumentError
      user = %{id: nil, email: "test@example.com", name: "Test"}
      UserEvents.user_registered(user)
      #=> ** (ArgumentError) User.id cannot be nil for user_registered event
  """

  alias KlassHero.Shared.Domain.Events.DomainEvent

  @aggregate_type :user

  @doc """
  Creates a `user_registered` event.

  This event is marked as `:critical` by default since user registration
  is a key business event that should not be lost.

  ## Parameters

  - `user` - The newly registered User struct
  - `payload` - Additional event-specific data (e.g., registration source)
  - `opts` - Metadata options (correlation_id, causation_id, user_id)

  ## Payload Fields

  Standard payload includes:
  - `email` - User's email address
  - `name` - User's display name
  - `intended_roles` - List of role identifiers selected during registration (["parent"], ["provider"], or both)

  Additional payload fields can be passed to include registration context.

  ## Raises

  - `ArgumentError` if `user.id` is nil
  - `ArgumentError` if `user.email` is nil or empty
  - `ArgumentError` if `user.name` is nil or empty
  - `ArgumentError` if `user.intended_roles` is not a list

  ## Examples

      iex> user = %{id: 1, email: "test@example.com", name: "Test User"}
      iex> event = UserEvents.user_registered(user, %{source: :web})
      iex> event.event_type
      :user_registered
      iex> DomainEvent.critical?(event)
      true
  """
  def user_registered(%{id: _, email: _, name: _} = user, payload \\ %{}, opts \\ []) do
    validate_user_for_registration!(user)

    base_payload = %{
      email: user.email,
      name: user.name,
      intended_roles: Enum.map(Map.get(user, :intended_roles) || [], &Atom.to_string/1)
    }

    opts = Keyword.put_new(opts, :criticality, :critical)

    DomainEvent.new(
      :user_registered,
      user.id,
      @aggregate_type,
      Map.merge(base_payload, payload),
      opts
    )
  end

  @doc """
  Creates a `user_confirmed` event.

  Emitted when a user confirms their email address, typically after
  clicking a confirmation link.

  ## Parameters

  - `user` - The confirmed User struct
  - `payload` - Additional event-specific data
  - `opts` - Metadata options (correlation_id, causation_id, user_id)

  ## Payload Fields

  Standard payload includes:
  - `email` - User's confirmed email address
  - `name` - User's display name
  - `confirmed_at` - Timestamp of confirmation
  - `intended_roles` - List of role identifiers selected during registration (["parent"], ["provider"], or both)

  ## Raises

  - `ArgumentError` if `user.id` is nil
  - `ArgumentError` if `user.email` is nil or empty
  - `ArgumentError` if `user.confirmed_at` is nil

  ## Examples

      iex> user = %{id: 1, email: "test@example.com", confirmed_at: ~U[2024-01-01 12:00:00Z]}
      iex> event = UserEvents.user_confirmed(user)
      iex> event.event_type
      :user_confirmed
  """
  def user_confirmed(%{id: _, email: _, confirmed_at: _} = user, payload \\ %{}, opts \\ []) do
    validate_user_for_confirmation!(user)

    opts = Keyword.put_new(opts, :criticality, :critical)

    base_payload = %{
      email: user.email,
      name: Map.get(user, :name),
      confirmed_at: user.confirmed_at,
      intended_roles: Enum.map(Map.get(user, :intended_roles) || [], &Atom.to_string/1)
    }

    DomainEvent.new(
      :user_confirmed,
      user.id,
      @aggregate_type,
      Map.merge(base_payload, payload),
      opts
    )
  end

  @doc """
  Creates a `user_email_changed` event.

  Emitted when a user changes their email address after confirmation.

  ## Parameters

  - `user` - The User struct with the new email
  - `payload` - Must include `previous_email` for audit trail
  - `opts` - Metadata options (correlation_id, causation_id, user_id)

  ## Payload Fields

  Standard payload includes:
  - `new_email` - User's new email address
  - `previous_email` - User's previous email (required in payload param)

  ## Raises

  - `ArgumentError` if `payload` is missing `:previous_email` key
  - `ArgumentError` if `:previous_email` is not a non-empty string
  - `ArgumentError` if `user.id` is nil
  - `ArgumentError` if `user.email` is nil or empty

  ## Examples

      iex> user = %{id: 1, email: "new@example.com"}
      iex> event = UserEvents.user_email_changed(user, %{previous_email: "old@example.com"})
      iex> event.event_type
      :user_email_changed
      iex> event.payload.previous_email
      "old@example.com"
  """
  def user_email_changed(user, payload, opts \\ [])

  def user_email_changed(%{id: _, email: _} = user, %{previous_email: previous_email} = payload, opts)
      when is_binary(previous_email) and byte_size(previous_email) > 0 do
    validate_user_for_email_change!(user)

    base_payload = %{
      new_email: user.email
    }

    DomainEvent.new(
      :user_email_changed,
      user.id,
      @aggregate_type,
      Map.merge(base_payload, payload),
      opts
    )
  end

  def user_email_changed(%{id: _, email: _}, payload, _opts) do
    raise ArgumentError,
          "user_email_changed/3 requires :previous_email in payload, got keys: #{inspect(Map.keys(payload))}"
  end

  # Private validation functions

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

  defp validate_user_for_email_change!(user) do
    validate_user!(user, :user_email_changed, [
      {:id, :required},
      {:email, :non_empty_string}
    ])
  end

  @doc """
  Creates a `user_anonymized` event.

  This event is marked as `:critical` by default since account anonymization
  is a key GDPR compliance event that must not be lost.

  ## Parameters

  - `user` - The User struct AFTER anonymization (with anonymized email)
  - `payload` - Must include `previous_email` for audit trail
  - `opts` - Metadata options (correlation_id, causation_id, user_id)

  ## Payload Fields

  Standard payload includes:
  - `anonymized_email` - User's new anonymized email (deleted_<id>@anonymized.local)
  - `previous_email` - User's previous email (required in payload param for audit)
  - `anonymized_at` - Timestamp of anonymization

  ## Raises

  - `ArgumentError` if `payload` is missing `:previous_email` key
  - `ArgumentError` if `:previous_email` is not a non-empty string
  - `ArgumentError` if `user.id` is nil

  ## Examples

      iex> user = %{id: 1, email: "deleted_1@anonymized.local"}
      iex> event = UserEvents.user_anonymized(user, %{previous_email: "old@example.com"})
      iex> event.event_type
      :user_anonymized
      iex> DomainEvent.critical?(event)
      true
  """
  def user_anonymized(user, payload, opts \\ [])

  def user_anonymized(%{id: _} = user, %{previous_email: previous_email} = payload, opts)
      when is_binary(previous_email) and byte_size(previous_email) > 0 do
    validate_user_for_anonymization!(user)

    base_payload = %{
      anonymized_email: Map.get(user, :email),
      anonymized_at: DateTime.utc_now()
    }

    opts = Keyword.put_new(opts, :criticality, :critical)

    DomainEvent.new(
      :user_anonymized,
      user.id,
      @aggregate_type,
      Map.merge(base_payload, payload),
      opts
    )
  end

  def user_anonymized(%{id: _}, payload, _opts) do
    raise ArgumentError,
          "user_anonymized/3 requires :previous_email in payload, got keys: #{inspect(Map.keys(payload))}"
  end

  defp validate_user_for_anonymization!(user) do
    validate_user!(user, :user_anonymized, [
      {:id, :required}
    ])
  end
end
