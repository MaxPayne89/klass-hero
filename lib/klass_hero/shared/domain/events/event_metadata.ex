defmodule KlassHero.Shared.Domain.Events.EventMetadata do
  @moduledoc """
  Shared metadata accessors and builders for domain and integration events.

  Both event structs carry a `:metadata` map with
  optional fields like `:criticality`, `:correlation_id`, and `:causation_id`.
  This module centralises the accessor functions and the metadata construction
  logic so that both event structs stay in sync without duplicating code.
  """

  alias KlassHero.Shared.Domain.Events.PayloadCodec

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
  Raises if an event carries a payload value that cannot survive Oban's jsonb column.

  Payloads are serialized to `oban_jobs.args`, so a value that loses its type there —
  a tuple, a schema struct — reaches consumers as something else, with no error at
  the publish site (#1010). Guarding at construction makes that loud where it is
  caused rather than in a worker two hops away.

  `PayloadCodec` decides what survives; this walks the payload and reports *where*.
  Nested maps and lists are containers — walked recursively, only their leaves are
  checked.

  ## Why this runs for every event

  It used to run for `:critical` events only, on the reasoning that "non-critical
  events dispatch in-memory only (never serialized)". ADR-0014 ended that: every
  staged event now takes the same Outbox → Oban → `EventDeliveryWorker` path, and
  `criticality` selects nothing. Both of #1311's production bugs sat in the gap.

  Ungating it was blocked on atoms, which `:normal` payloads carry as a matter of
  course (`type: :direct`, `message_type: :text`, `status: :pending`). #1317 taught
  the codec to record them, so there is nothing left to exempt.

  Returns `:ok` or raises `ArgumentError`.
  """
  @spec validate_payload!(map()) :: :ok
  def validate_payload!(payload) when is_map(payload) do
    scan_payload(payload, [])
    :ok
  end

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
    if !PayloadCodec.encodable?(value) do
      location = path |> Enum.reverse() |> Enum.join(".")

      raise ArgumentError,
            "Event payload value at #{inspect(location)} cannot survive jsonb " <>
              "serialization: #{inspect(value)}. A payload may carry strings, numbers, " <>
              "booleans, nil, atoms, and Date/Time/DateTime/NaiveDateTime/Decimal structs " <>
              "(nested in maps/lists). Encode anything else — a tuple, a schema struct — as " <>
              "a JSON scalar before publishing."
    end
  end
end
