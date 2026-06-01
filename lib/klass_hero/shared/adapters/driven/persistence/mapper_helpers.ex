defmodule KlassHero.Shared.Adapters.Driven.Persistence.MapperHelpers do
  @moduledoc """
  Shared helper functions for persistence mappers across bounded contexts.

  Provides common conversion utilities for collection mapping, tier atoms/strings,
  and optional id handling. Used by mapper and repository modules across all contexts.
  """

  alias KlassHero.Shared.SubscriptionTiers

  @doc """
  Converts a list of persistence schemas to domain entities using the given mapper module.

  The mapper module must implement `to_domain/1`.

  ## Examples

      iex> MapperHelpers.to_domain_list([], MyMapper)
      []

      iex> MapperHelpers.to_domain_list([schema1, schema2], MyMapper)
      [%DomainModel{}, %DomainModel{}]

  """
  @spec to_domain_list([input], module()) :: [output]
        when input: term(), output: term()
  def to_domain_list(schemas, mapper_module) when is_list(schemas) and is_atom(mapper_module) do
    Enum.map(schemas, &mapper_module.to_domain/1)
  end

  # Derive tier list from the single source of truth
  @all_tiers SubscriptionTiers.parent_tiers() ++ SubscriptionTiers.provider_tiers()

  @doc """
  Converts a string tier to an atom, returning the default if nil or unknown.

  Uses String.to_existing_atom/1 to prevent atom table exhaustion from
  untrusted input. Falls back to default if the atom doesn't exist or
  isn't in the allowed tier list.
  """
  @spec string_to_tier(String.t() | nil, atom()) :: atom()
  def string_to_tier(nil, default), do: default

  def string_to_tier(tier, default) when is_binary(tier) do
    atom = String.to_existing_atom(tier)

    if atom in @all_tiers do
      atom
    else
      default
    end
  rescue
    ArgumentError -> default
  end

  @doc """
  Converts an atom tier to a string, returning the default string if nil.
  """
  @spec tier_to_string(atom() | nil, String.t()) :: String.t()
  def tier_to_string(nil, default), do: default
  def tier_to_string(tier, _default) when is_atom(tier), do: Atom.to_string(tier)

  @doc """
  Converts an atom field in an attrs map to its string representation.

  No-op if the key is absent, nil, or already a string.
  """
  @spec normalize_atom_field(map(), atom()) :: map()
  def normalize_atom_field(attrs, key) do
    case Map.get(attrs, key) do
      value when is_atom(value) and not is_nil(value) ->
        Map.put(attrs, key, Atom.to_string(value))

      _ ->
        attrs
    end
  end

  @doc """
  Converts :subscription_tier in an attrs map from atom to string.

  No-op if the key is absent, nil, or already a string.
  Delegates to `normalize_atom_field/2`.
  """
  @spec normalize_subscription_tier(map()) :: map()
  def normalize_subscription_tier(attrs), do: normalize_atom_field(attrs, :subscription_tier)

  @doc """
  Conditionally adds an id to attrs map if the id is not nil.
  """
  @spec maybe_add_id(map(), String.t() | nil) :: map()
  def maybe_add_id(attrs, nil), do: attrs
  def maybe_add_id(attrs, id), do: Map.put(attrs, :id, id)

  @doc """
  Normalizes map keys to atoms. Handles both atom and string keys.

  String keys are converted via `String.to_existing_atom/1` to prevent
  atom table pollution. Unknown string keys (not in the atom table) are
  kept as strings rather than crashing — downstream `Map.fetch` will
  report the missing atom key clearly.
  """
  @spec normalize_keys(map()) :: map()
  def normalize_keys(payload) when is_map(payload) do
    Map.new(payload, fn
      {k, v} when is_atom(k) ->
        {k, v}

      {k, v} when is_binary(k) ->
        try do
          {String.to_existing_atom(k), v}
        rescue
          ArgumentError -> {k, v}
        end
    end)
  end

  @doc "Converts a value to a string, leaving nil untouched."
  @spec maybe_to_string(term()) :: String.t() | nil
  def maybe_to_string(nil), do: nil
  def maybe_to_string(value), do: to_string(value)
end
