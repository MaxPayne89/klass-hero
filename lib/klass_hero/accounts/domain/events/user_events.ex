defmodule KlassHero.Accounts.Domain.Events.UserEvents do
  @moduledoc """
  Factory for User domain events in the Accounts context. All factories do fail-fast
  validation and raise `ArgumentError` on invalid inputs.
  """

  alias KlassHero.Shared.Domain.Events.DomainEvent

  @aggregate_type :user

  @doc """
  Creates a `user_registered` event (critical). Payload includes `email`, `name`, `intended_roles`.
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
  Creates a `user_confirmed` event (critical). Payload includes `email`, `name`, `confirmed_at`, `intended_roles`.
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
  Creates a `user_email_changed` event. Requires `previous_email` in payload for audit trail.
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
  Creates a `user_anonymized` event (critical — GDPR cascade must not be lost).
  Requires `previous_email` in payload for audit trail.
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
