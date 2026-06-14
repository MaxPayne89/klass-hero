defmodule KlassHero.Shared.Interaction.Kind.Email do
  @moduledoc """
  Interaction policy for transactional email delivery (Swoosh-backed notifiers).

  Recipients, subjects and bodies are PII, so inputs are dropped by default and
  attributes carry the operation only.
  """

  @behaviour KlassHero.Shared.Interaction.Kind

  alias KlassHero.Shared.Interaction.Kind

  @impl true
  def classify({:ok, _}), do: :ok
  def classify(:ok), do: :ok
  def classify({:error, _}), do: :error
  def classify(_), do: :ok

  @impl true
  def normalize_error({:error, reason}) when is_atom(reason), do: reason
  def normalize_error(_), do: :delivery_error

  @impl true
  def attributes(_result, opts), do: %{"email.operation" => opts[:operation]}

  @impl true
  def sanitize(input, opts), do: Kind.default_sanitize(input, opts)
end
