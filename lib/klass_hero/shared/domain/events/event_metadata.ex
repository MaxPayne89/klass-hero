defmodule KlassHero.Shared.Domain.Events.EventMetadata do
  @moduledoc """
  Shared metadata accessors and builders for domain and integration events.

  Both event structs carry a `:metadata` map with
  optional fields like `:criticality`, `:correlation_id`, and `:causation_id`.
  This module centralises the accessor functions and the metadata construction
  logic so that both event structs stay in sync without duplicating code.
  """

  @type criticality :: :critical | :normal

  @spec criticality(%{metadata: map()}) :: criticality()
  def criticality(%{metadata: %{criticality: level}}), do: level
  def criticality(%{metadata: _}), do: :normal

  @spec critical?(%{metadata: map()}) :: boolean()
  def critical?(event), do: criticality(event) == :critical

  @spec correlation_id(%{metadata: map()}) :: String.t() | nil
  def correlation_id(%{metadata: %{correlation_id: id}}), do: id
  def correlation_id(%{metadata: _}), do: nil

  @spec causation_id(%{metadata: map()}) :: String.t() | nil
  def causation_id(%{metadata: %{causation_id: id}}), do: id
  def causation_id(%{metadata: _}), do: nil

  @doc """
  Generates a unique event ID (UUID v4).
  """
  @spec generate_event_id() :: String.t()
  def generate_event_id, do: Ecto.UUID.generate()

  @doc """
  Builds a metadata map from keyword options.

  Always includes `:criticality` (defaulting to `:normal`), plus
  `:correlation_id` and `:causation_id` when present. Additional keys
  can be pulled from `opts` via the `extra_keys` list — for example,
  `DomainEvent` passes `[:user_id]` to include a user reference.
  """
  @spec build_metadata(keyword()) :: map()
  def build_metadata(opts) do
    %{criticality: Keyword.get(opts, :criticality, :normal)}
    |> maybe_add(:correlation_id, opts)
    |> maybe_add(:causation_id, opts)
  end

  defp maybe_add(map, key, opts) do
    case Keyword.get(opts, key) do
      nil -> map
      value -> Map.put(map, key, value)
    end
  end

  @doc """
  Raises if a `:critical` event carries a payload value that is not a JSON
  scalar.

  Critical events are serialized to Oban's jsonb `args` column for durable,
  at-least-once delivery. Non-scalar payload *values* — a `%DateTime{}`, an
  atom, a tuple — silently lose their type across the `serialize → jsonb →
  deserialize` round trip (a `DateTime` comes back a string, an atom comes
  back a string) with no error (see issue #1010). Guarding at construction
  makes the failure loud at the publish site instead of latent three systems
  downstream.

  Nested maps and lists are allowed as *containers* — they are walked
  recursively, and only their leaf values must be scalars.

  Non-critical events dispatch in-memory only (never serialized), so they may
  carry any term and are exempt.

  Returns `:ok` or raises `ArgumentError`.
  """
  @spec validate_critical_payload!(criticality(), map()) :: :ok
  def validate_critical_payload!(:critical, payload) when is_map(payload) do
    scan_payload(payload, [])
    :ok
  end

  def validate_critical_payload!(_criticality, _payload), do: :ok

  # Containers recurse; the `not is_struct/1` guard keeps structs (which are
  # maps) from being walked — they fall through to the leaf clause and get
  # rejected there.
  defp scan_payload(map, path) when is_map(map) and not is_struct(map) do
    Enum.each(map, fn {key, value} -> scan_payload(value, [key | path]) end)
  end

  defp scan_payload(list, path) when is_list(list) do
    list
    |> Enum.with_index()
    |> Enum.each(fn {value, index} -> scan_payload(value, [index | path]) end)
  end

  defp scan_payload(value, path) do
    if !json_scalar?(value) do
      location = path |> Enum.reverse() |> Enum.join(".")

      raise ArgumentError,
            "Critical event payload value at #{inspect(location)} is not a JSON scalar: " <>
              "#{inspect(value)}. Critical payloads must carry only strings, numbers, " <>
              "booleans, or nil (nested in maps/lists) so they survive jsonb serialization. " <>
              "Encode DateTimes as ISO8601 strings and atoms as strings before publishing."
    end
  end

  # A JSON scalar is a value that survives a jsonb round trip with its type
  # intact: strings, numbers, booleans, and nil. `nil`/`true`/`false` are
  # atoms but are allowed because they map to JSON null/true/false; every
  # other atom is rejected, since restoring a bare atom value is precisely the
  # type loss #1010 is about (hence the explicit clauses rather than a blanket
  # `not is_atom/1`).
  @spec json_scalar?(term()) :: boolean()
  defp json_scalar?(value) when is_binary(value), do: true
  defp json_scalar?(value) when is_number(value), do: true
  defp json_scalar?(value) when is_boolean(value), do: true
  defp json_scalar?(nil), do: true
  defp json_scalar?(_value), do: false
end
