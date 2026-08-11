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
  `:correlation_id` and `:causation_id` when present.
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
  Raises if a `:critical` event carries a payload value that cannot survive Oban's
  jsonb column.

  Payloads are serialized to `oban_jobs.args`, so a value that loses its type there
  — an atom, a tuple, a schema struct — reaches consumers as something else, with no
  error at the publish site (#1010). Guarding at construction makes that loud where
  it is caused.

  `Date`, `Time`, `DateTime`, `NaiveDateTime` and `Decimal` are exempt: since #1311
  `CriticalEventSerializer` records them on the way out and rebuilds them on the way
  in, so they arrive as what the producer sent. Nested maps and lists are containers
  — walked recursively, only their leaves are checked.

  ## Why this still only runs for `:critical`

  The original reason for the exemption is stale. It read "non-critical events
  dispatch in-memory only (never serialized)", which ADR-0014 ended: every staged
  event now takes the same Outbox → Oban → `EventDeliveryWorker` path, and
  `criticality` selects nothing. #1311's two bugs both hid in that gap.

  It stays gated anyway, because ungating it today raises on 137 existing tests:
  `:normal` payloads carry atoms as a matter of course (`type: :direct`,
  `message_type: :text`, `status: :pending`), and their consumers already cope with
  the string that arrives — `conversation_summaries.ex` matches
  `message_type in [:system, "system"]` for exactly this reason. Closing that needs
  either atom support in the serializer or an encode-at-the-producer pass across ~9
  producers, and it is tracked separately. #1311 was about type loss the envelope can
  fix without changing what any consumer receives.

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
    if !json_scalar?(value) and !typed_scalar?(value) do
      location = path |> Enum.reverse() |> Enum.join(".")

      raise ArgumentError,
            "Critical event payload value at #{inspect(location)} cannot survive jsonb " <>
              "serialization: #{inspect(value)}. Critical payloads may carry strings, numbers, " <>
              "booleans, nil, and Date/Time/DateTime/NaiveDateTime/Decimal structs (nested in " <>
              "maps/lists). Encode anything else — an atom, a tuple, a schema struct — as a " <>
              "JSON scalar before publishing."
    end
  end

  # CriticalEventSerializer records these on the way out and rebuilds them on the way
  # in, so unlike a bare atom they arrive as what the producer sent (#1311).
  defp typed_scalar?(%Date{}), do: true
  defp typed_scalar?(%Time{}), do: true
  defp typed_scalar?(%DateTime{}), do: true
  defp typed_scalar?(%NaiveDateTime{}), do: true
  defp typed_scalar?(%Decimal{}), do: true
  defp typed_scalar?(_value), do: false

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
