defmodule KlassHero.Shared.Adapters.Driven.Events.EventSerializer do
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

  ## Payload values keep their types, and the sidecar is how

  `jsonb` has no date, time, decimal or atom. A `%Date{}` a producer put in a payload
  would arrive as `"2026-08-12"`, and a consumer written against the `@spec` would
  raise on it — which is what #1311 was, in two contexts at once.

  So `serialize/1` writes a second map beside the payload recording what each typed
  value was, and `deserialize/1` uses it to rebuild them:

      %{
        "payload"       => %{"start_date" => "2026-08-12", "title" => "Chess"},
        "payload_types" => %{"start_date" => "date"}
      }

  A consumer therefore receives what the producer sent and needs to know nothing
  about the wire.

  **What each leaf may be is `PayloadCodec`'s to say, not this module's.** This one
  walks the payload and mirrors the tags into the sidecar; the codec turns one leaf
  into `{scalar, tag}` and back. `EventMetadata.validate_payload!/1` asks that same
  codec at construction, which is what keeps the two ends from drifting — they were
  separate lists until #1317, and each of #1316 and #1317 had to edit both.

  The sidecar mirrors the payload's shape rather than tagging values inline
  (`{"__type__": ...}`) so the payload stays plain JSON in `oban_jobs.args` and
  `undelivered_events.payload` — both get read in SQL and in Honeycomb, where a
  wrapped scalar is materially worse. Branches with nothing typed in them are
  pruned, so an all-scalar payload carries `%{}`.

  **Args written before this existed** carry no `"payload_types"`, so their values
  stay strings — the pre-#1311 behaviour, which is what the jobs already in the queue
  at deploy need.

  ## Metadata is a closed format, and that is what makes a key retirable

  `deserialize_metadata/1` restores only the keys the format defines and drops the
  rest, rather than atomizing whatever arrives. The asymmetry is deliberate: an open
  `String.to_existing_atom/1` makes deleting a metadata key a breaking change, because
  every row an earlier release staged still carries it and no module holds the atom any
  more. #1326 retired `criticality` through this door; whatever is retired next needs
  no shim.

  The reverse direction needs more care than it used to. "Older code ignores the extra
  key" was true only of the pre-#1311 serializer, which never read `payload_types`;
  #1316's does read it, and until #1317 it had no fallback for a tag it did not know.
  So rolling back **past #1317** dead-letters any job staged with an `"atom"` tag,
  because the old code is what lacks the fallback. From #1317 onward `PayloadCodec`
  degrades an unrecognised tag to the raw scalar, so adding a tag later is safe to
  roll back through.
  """

  alias KlassHero.Shared.Domain.Events.Event
  alias KlassHero.Shared.Domain.Events.PayloadCodec

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

  # `not is_struct/1` keeps Date and friends out of the container clause — they are
  # maps, but they are leaves, and PayloadCodec is what knows that.
  defp encode_value(map) when is_map(map) and not is_struct(map) do
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

  defp encode_value(value), do: PayloadCodec.encode(value)

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

  defp decode_value(value, type) when is_binary(type), do: PayloadCodec.decode(value, type)

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

  # Keys restored to the atom the producer used.
  @atom_metadata_keys ~w(correlation_id causation_id)

  # Keys that stay binary strings — W3C Trace Context headers, which the Erlang
  # propagator wants as `{binary(), binary()}` pairs.
  @string_metadata_keys ~w(traceparent tracestate baggage)

  defp deserialize_metadata(metadata) when is_map(metadata) do
    for {key, value} <- metadata, entry = restore_entry(to_string(key), value), into: %{}, do: entry
  end

  defp deserialize_metadata(nil), do: %{}

  defp restore_entry(key, value) when key in @atom_metadata_keys, do: {String.to_existing_atom(key), value}
  defp restore_entry(key, value) when key in @string_metadata_keys, do: {key, value}
  defp restore_entry(_key, _value), do: nil

  defp parse_datetime!(iso_string) when is_binary(iso_string) do
    {:ok, dt, _offset} = DateTime.from_iso8601(iso_string)
    dt
  end

  defp to_existing_atom(string) when is_binary(string), do: String.to_existing_atom(string)
  defp to_existing_atom(atom) when is_atom(atom), do: atom
end
