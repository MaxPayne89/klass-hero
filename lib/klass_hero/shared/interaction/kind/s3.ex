defmodule KlassHero.Shared.Interaction.Kind.S3 do
  @moduledoc """
  Interaction policy for object-storage calls (ExAws/S3-compatible adapters).

  Object keys and paths can embed identifiers, so attributes carry the operation
  only — never the key. Allowlist a hashed key via `capture:` if ever needed.
  """

  @behaviour KlassHero.Shared.Interaction.Kind

  alias KlassHero.Shared.Interaction.Kind

  @impl true
  def classify({:ok, _}), do: :ok
  def classify(:ok), do: :ok
  def classify({:error, _}), do: :error
  def classify(_), do: :ok

  @impl true
  def normalize_error({:error, {:http_error, 404, _}}), do: :not_found
  def normalize_error({:error, reason}) when is_atom(reason), do: reason
  def normalize_error(_), do: :storage_error

  @impl true
  def attributes(_result, opts), do: %{"s3.operation" => opts[:operation]}

  @impl true
  def sanitize(input, opts), do: Kind.default_sanitize(input, opts)
end
