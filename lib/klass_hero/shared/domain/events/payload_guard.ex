defmodule KlassHero.Shared.Domain.Events.PayloadGuard do
  @moduledoc """
  Rejects, at construction, any event payload that cannot survive Oban's jsonb column.

  Pairs with `PayloadCodec`: the codec decides *what* survives, this walks a payload
  and reports *where* something does not. Keeping them side by side is what stopped
  them drifting — they were separate lists until #1317, and each of #1316 and #1317
  had to edit both.

  Lived in `EventMetadata` until #1358 retired the `metadata` field, which left that
  module named after a concept it no longer held.
  """

  alias KlassHero.Shared.Domain.Events.PayloadCodec

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

  It used to run for events marked critical only, on the reasoning that "non-critical
  events dispatch in-memory only (never serialized)". ADR-0014 ended that: every
  staged event takes the same Outbox → Oban → `EventDeliveryWorker` path. Both of
  #1311's production bugs sat in the gap that left, and being this guard's last
  reader was the only thing keeping the criticality field alive — #1326 removed it.

  Ungating it was blocked on atoms, which payloads carry as a matter of course
  (`type: :direct`, `message_type: :text`, `status: :pending`). #1317 taught the
  codec to record them, so there is nothing left to exempt.

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
