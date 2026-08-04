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
  """

  alias KlassHero.Shared.Domain.Events.Event

  @doc """
  Serializes an event struct into a JSON-safe map.
  """
  @spec serialize(Event.t()) :: map()
  def serialize(%Event{} = event) do
    %{
      "event_id" => event.event_id,
      "event_type" => Atom.to_string(event.event_type),
      "source_context" => Atom.to_string(event.source_context),
      "entity_type" => Atom.to_string(event.entity_type),
      "entity_id" => event.entity_id,
      "occurred_at" => DateTime.to_iso8601(event.occurred_at),
      "payload" => stringify_keys(event.payload),
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
      payload: atomize_keys(data["payload"]),
      metadata: deserialize_metadata(data["metadata"]),
      version: data["version"]
    }
  end

  defp stringify_keys(%_{} = struct), do: struct

  defp stringify_keys(map) when is_map(map) do
    Map.new(map, fn
      {k, v} when is_atom(k) -> {Atom.to_string(k), stringify_keys(v)}
      {k, v} -> {k, stringify_keys(v)}
    end)
  end

  defp stringify_keys(list) when is_list(list), do: Enum.map(list, &stringify_keys/1)

  defp stringify_keys(value), do: value

  defp atomize_keys(%_{} = struct), do: struct

  defp atomize_keys(map) when is_map(map) do
    Map.new(map, fn
      {k, v} when is_binary(k) -> {String.to_existing_atom(k), atomize_keys(v)}
      {k, v} -> {k, atomize_keys(v)}
    end)
  end

  defp atomize_keys(list) when is_list(list), do: Enum.map(list, &atomize_keys/1)

  defp atomize_keys(value), do: value

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
