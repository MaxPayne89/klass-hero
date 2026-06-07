defmodule KlassHero.Shared.SubscriptionTiers do
  @moduledoc """
  Shared vocabulary for parent subscription tier names, defaults, and validation.

  Lives in the Shared kernel so that both Identity (domain model validation)
  and Entitlements (limit lookups) can reference tier names without creating
  a cyclic dependency between contexts.

  Provider tiers were removed (ADR-0004) — only parent tiers remain, and they
  are slated for removal too. Do not build new behaviour on tiers.
  """

  @parent_tiers [:explorer, :active]

  @doc """
  Returns the list of valid parent subscription tier atoms.

  ## Examples

      iex> KlassHero.Shared.SubscriptionTiers.parent_tiers()
      [:explorer, :active]
  """
  @spec parent_tiers() :: [atom()]
  def parent_tiers, do: @parent_tiers

  @doc """
  Checks if the given tier is a valid parent subscription tier.

  ## Examples

      iex> KlassHero.Shared.SubscriptionTiers.valid_parent_tier?(:explorer)
      true

      iex> KlassHero.Shared.SubscriptionTiers.valid_parent_tier?(:invalid)
      false
  """
  @spec valid_parent_tier?(term()) :: boolean()
  def valid_parent_tier?(tier) when is_atom(tier), do: tier in @parent_tiers
  def valid_parent_tier?(_), do: false

  @doc """
  Returns the default subscription tier for parents.

  ## Examples

      iex> KlassHero.Shared.SubscriptionTiers.default_parent_tier()
      :explorer
  """
  @spec default_parent_tier() :: atom()
  def default_parent_tier, do: :explorer
end
