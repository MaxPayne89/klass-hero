defmodule KlassHero.Shared.Adapters.Driven.Events.CriticalEventSerializer do
  @moduledoc """
  Serializes and deserializes event structs for Oban job args.

  Handles the round-trip of `Event` structs through JSON. Atom
  fields are converted to strings on serialization and restored via
  `String.to_existing_atom/1` on deserialization (safe because all event types
  and payload keys are domain-defined and already loaded).

  ## Payload keys are atomized here, and only here

  `deserialize/1` atomizes payload keys recursively, so a consumer reached through
  `EventDeliveryWorker` always receives an atom-keyed payload and must not
  re-normalize one. A handler that defends against string keys is dead code: an
  unknown key raises in here, before the event ever reaches it.

  Stated because the opposite was assumed once — handlers carried their own
  shallow `normalize_keys/1` long after this became the single normalization
  point, and it read as load-bearing (#1256).

  ## Payload values keep their types, and that is also only here

  `jsonb` has no date, time or decimal. A `%Date{}` a producer put in a payload
  would arrive as `"2026-08-12"`, and a consumer written against the `@spec` would
  raise on it — which is what #1311 was, in two contexts at once.

  So `serialize/1` writes a second map beside the payload recording what each typed
  value was, and `deserialize/1` uses it to rebuild them:

      %{
        "payload"       => %{"start_date" => "2026-08-12", "title" => "Chess"},
        "payload_types" => %{"start_date" => "date"}
      }

  A consumer therefore receives what the producer sent and needs to know nothing
  about the wire. Supported: `Date`, `Time`, `DateTime`, `NaiveDateTime`, `Decimal`.
  Any other struct raises here — `EventMetadata.validate_payload!/1` rejects it at
  construction, so reaching that raise means something bypassed `Event.new/6`.

  The sidecar mirrors the payload's shape rather than tagging values inline
  (`{"__type__": ...}`) so the payload stays plain JSON in `oban_jobs.args` and
  `undelivered_events.payload` — both get read in SQL and in Honeycomb, where a
  wrapped scalar is materially worse. Branches with nothing typed in them are
  pruned, so an all-scalar payload carries `%{}`.

  Two properties worth knowing:

  - **Args written before this existed** carry no `"payload_types"`, so their values
    stay strings — the pre-#1311 behaviour, which is what in-flight jobs need at
    deploy. The reverse holds too: older code ignores the extra key, so a rollback
    is safe.
  - **A `DateTime` comes back in UTC.** `DateTime.from_iso8601/1` returns the instant
    plus a separate offset, and only the instant is kept. Every producer here builds
    UTC, so nothing observes the difference.
  """

  alias KlassHero.Shared.Domain.Events.Event

  @doc """
  Serializes an event struct into a JSON-safe map.
  """
  @spec serialize(Event.t()) :: map()
  def serialize(%Event{} = event) do
    {payload, payload_types} = encode_payload(event.payload)

    %{
      "event_id" => event.event_id,
      "event_type" => Atom.to_string(event.event_type),
      "source_context" => Atom.to_string(event.source_context),
      "entity_type" => Atom.to_string(event.entity_type),
      "entity_id" => event.entity_id,
      "occurred_at" => DateTime.to_iso8601(event.occurred_at),
      "payload" => payload,
      "payload_types" => payload_types || %{},
      "metadata" => serialize_metadata(event.metadata),
      "version" => event.version
    }
  end

  @doc """
  Deserializes a map (from Oban job args) back into an event struct.

  Atom fields are restored via `String.to_existing_atom/1`. Payload keys
  are atomized recursively.
  """
  @spec deserialize(map()) :: Event.t()
  def deserialize(data) when is_map(data) do
    %Event{
      event_id: data["event_id"],
      event_type: to_existing_atom(data["event_type"]),
      source_context: to_existing_atom(data["source_context"]),
      entity_type: to_existing_atom(data["entity_type"]),
      entity_id: data["entity_id"],
      occurred_at: parse_datetime!(data["occurred_at"]),
      payload: decode_payload(data["payload"], data["payload_types"]),
      metadata: deserialize_metadata(data["metadata"]),
      version: data["version"]
    }
  end

  # Each walker returns {encoded_value, types} where types mirrors the value's shape
  # and holds a type name at every typed leaf, or nil where there is nothing to
  # remember. nil is what prunes the sidecar: it propagates up through maps and
  # lists, so an all-scalar payload contributes no sidecar at all.

  defp encode_payload(payload) when is_map(payload), do: encode_value(payload)

  defp encode_value(%Date{} = value), do: {Date.to_iso8601(value), "date"}
  defp encode_value(%Time{} = value), do: {Time.to_iso8601(value), "time"}
  defp encode_value(%DateTime{} = value), do: {DateTime.to_iso8601(value), "datetime"}
  defp encode_value(%NaiveDateTime{} = value), do: {NaiveDateTime.to_iso8601(value), "naive_datetime"}
  defp encode_value(%Decimal{} = value), do: {Decimal.to_string(value), "decimal"}

  defp encode_value(%struct{} = value) do
    raise ArgumentError,
          "Event payload value of type #{inspect(struct)} cannot cross the Oban jsonb " <>
            "boundary: #{inspect(value)}. Supported structs are Date, Time, DateTime, " <>
            "NaiveDateTime and Decimal; encode anything else as a JSON scalar in the " <>
            "producer. Event.new/6 rejects this too, so reaching here means the event " <>
            "was built some other way."
  end

  defp encode_value(map) when is_map(map) do
    {encoded, types} =
      Enum.map_reduce(map, %{}, fn {key, value}, types ->
        string_key = stringify_key(key)
        {encoded_value, value_types} = encode_value(value)

        {{string_key, encoded_value}, put_type(types, string_key, value_types)}
      end)

    {Map.new(encoded), prune(types)}
  end

  defp encode_value(list) when is_list(list) do
    {encoded, types} = list |> Enum.map(&encode_value/1) |> Enum.unzip()

    {encoded, prune(types)}
  end

  defp encode_value(value), do: {value, nil}

  defp stringify_key(key) when is_atom(key), do: Atom.to_string(key)
  defp stringify_key(key), do: key

  defp put_type(types, _key, nil), do: types
  defp put_type(types, key, value_types), do: Map.put(types, key, value_types)

  # An empty container carries no type information, so it collapses to nil and its
  # parent drops the entry entirely.
  defp prune(types) when types == %{}, do: nil
  defp prune(types) when is_list(types), do: if(!Enum.all?(types, &is_nil/1), do: types)
  defp prune(types), do: types

  defp decode_payload(payload, types) when is_map(payload), do: decode_value(payload, types)

  defp decode_value(value, type) when is_binary(type), do: revive(type, value)

  defp decode_value(map, types) when is_map(map) do
    Map.new(map, fn {key, value} ->
      {atomize_key(key), decode_value(value, type_for(types, key))}
    end)
  end

  defp decode_value(list, types) when is_list(list) do
    types = if is_list(types) and length(types) == length(list), do: types, else: List.duplicate(nil, length(list))

    for {value, value_types} <- Enum.zip(list, types), do: decode_value(value, value_types)
  end

  defp decode_value(value, _types), do: value

  defp atomize_key(key) when is_binary(key), do: String.to_existing_atom(key)
  defp atomize_key(key), do: key

  defp type_for(types, key) when is_map(types), do: Map.get(types, key)
  defp type_for(_types, _key), do: nil

  defp revive("date", value), do: Date.from_iso8601!(value)
  defp revive("time", value), do: Time.from_iso8601!(value)
  defp revive("naive_datetime", value), do: NaiveDateTime.from_iso8601!(value)
  defp revive("decimal", value), do: Decimal.new(value)

  defp revive("datetime", value) do
    {:ok, datetime, _utc_offset} = DateTime.from_iso8601(value)
    datetime
  end

  defp serialize_metadata(metadata) when is_map(metadata) do
    Map.new(metadata, fn
      {k, v} when is_atom(k) and is_atom(v) ->
        {Atom.to_string(k), Atom.to_string(v)}

      {k, v} when is_atom(k) ->
        {Atom.to_string(k), v}

      {k, v} ->
        {to_string(k), v}
    end)
  end

  @atom_metadata_values ~w(criticality)

  # Keys that remain as binary strings after deserialization — they are
  # string-keyed by design (W3C Trace Context headers) and must not be atomized.
  @string_passthrough_keys ["traceparent", "tracestate", "baggage"]

  defp deserialize_metadata(metadata) when is_map(metadata) do
    Map.new(metadata, fn
      {k, v} when is_binary(k) and k in @atom_metadata_values ->
        {String.to_existing_atom(k), String.to_existing_atom(v)}

      {k, v} when is_binary(k) and k in @string_passthrough_keys ->
        {k, v}

      {k, v} when is_binary(k) ->
        {String.to_existing_atom(k), v}

      {k, v} when is_atom(k) ->
        {k, v}
    end)
  end

  defp deserialize_metadata(nil), do: %{}

  defp parse_datetime!(iso_string) when is_binary(iso_string) do
    {:ok, dt, _offset} = DateTime.from_iso8601(iso_string)
    dt
  end

  defp to_existing_atom(string) when is_binary(string), do: String.to_existing_atom(string)
  defp to_existing_atom(atom) when is_atom(atom), do: atom
end
