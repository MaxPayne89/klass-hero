defmodule KlassHero.Shared.Domain.Events.EventMetadata do
  @moduledoc """
  Shared metadata accessors and builders for domain and integration events.

  Both `DomainEvent` and `IntegrationEvent` carry a `:metadata` map with
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
  @spec build_metadata(keyword(), [atom()]) :: map()
  def build_metadata(opts, extra_keys \\ []) do
    %{criticality: Keyword.get(opts, :criticality, :normal)}
    |> maybe_add(:correlation_id, opts)
    |> maybe_add(:causation_id, opts)
    |> then(fn base ->
      Enum.reduce(extra_keys, base, fn key, acc -> maybe_add(acc, key, opts) end)
    end)
  end

  defp maybe_add(map, key, opts) do
    case Keyword.get(opts, key) do
      nil -> map
      value -> Map.put(map, key, value)
    end
  end
end
