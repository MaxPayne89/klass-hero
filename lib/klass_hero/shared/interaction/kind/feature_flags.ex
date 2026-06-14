defmodule KlassHero.Shared.Interaction.Kind.FeatureFlags do
  @moduledoc """
  Interaction policy for feature-flag lookups and toggles (FunWithFlags-backed).

  Flag names are low-cardinality and safe; the actor passed to a lookup may be a
  user struct, so inputs are dropped by default.
  """

  @behaviour KlassHero.Shared.Interaction.Kind

  alias KlassHero.Shared.Interaction.Kind

  @impl true
  def classify({:error, _}), do: :error
  def classify(_), do: :ok

  @impl true
  def normalize_error({:error, reason}) when is_atom(reason), do: reason
  def normalize_error(_), do: :feature_flag_error

  @impl true
  def attributes(_result, opts) do
    %{"flag.operation" => opts[:operation], "flag.name" => opts[:flag]}
  end

  @impl true
  def sanitize(input, opts), do: Kind.default_sanitize(input, opts)
end
