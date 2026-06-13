defmodule KlassHero.Shared.Adapters.Driven.Events.CriticalEventSerializer do
  @moduledoc """
  Serializes and deserializes event structs for Oban job args.

  Handles the round-trip of `DomainEvent` and `IntegrationEvent` structs
  through JSON. Atom fields are converted to strings on serialization and
  restored via `String.to_existing_atom/1` on deserialization (safe because
  all event types and payload keys are domain-defined and already loaded).
  """

  alias KlassHero.Shared.Domain.Events.DomainEvent
  alias KlassHero.Shared.Domain.Events.IntegrationEvent

  @domain_kind "domain"
  @integration_kind "integration"

  @doc """
  Serializes an event struct into a JSON-safe map.
  """
  @spec serialize(DomainEvent.t() | IntegrationEvent.t()) :: map()
  def serialize(%DomainEvent{} = event) do
    %{
      "event_kind" => @domain_kind,
      "event_id" => event.event_id,
      "event_type" => Atom.to_string(event.event_type),
      "aggregate_id" => event.aggregate_id,
      "aggregate_type" => Atom.to_string(event.aggregate_type),
      "occurred_at" => DateTime.to_iso8601(event.occurred_at),
      "payload" => stringify_keys(event.payload),
      "metadata" => serialize_metadata(event.metadata)
    }
  end

  def serialize(%IntegrationEvent{} = event) do
    %{
      "event_kind" => @integration_kind,
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
  @spec deserialize(map()) :: DomainEvent.t() | IntegrationEvent.t()
  def deserialize(%{"event_kind" => @domain_kind} = data) do
    %DomainEvent{
      event_id: data["event_id"],
      event_type: to_existing_atom(data["event_type"]),
      aggregate_id: data["aggregate_id"],
      aggregate_type: to_existing_atom(data["aggregate_type"]),
      occurred_at: parse_datetime!(data["occurred_at"]),
      payload: atomize_keys(data["payload"]),
      metadata: deserialize_metadata(data["metadata"])
    }
  end

  def deserialize(%{"event_kind" => @integration_kind} = data) do
    %IntegrationEvent{
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

  def deserialize(%{"event_kind" => kind}) do
    raise ArgumentError,
          "Unknown event_kind #{inspect(kind)} in critical event job args. " <>
            ~s(Expected "domain" or "integration".)
  end

  def deserialize(data) when is_map(data) do
    raise ArgumentError,
          "Missing event_kind in critical event job args: #{inspect(Map.keys(data))}"
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
