defmodule KlassHero.Shared.Interaction.Kind.Db do
  @moduledoc """
  Interaction policy for database calls (Ecto repositories).

  Writes return `{:ok, _} | {:error, changeset | atom}`; reads return bare
  structs, lists, integers or booleans. `classify/1` treats anything that isn't
  an explicit `{:error, _}` as success — read sites that consider `{:error,
  :not_found}` an expected (non-alerting) outcome pass a `success:` override at
  the call site rather than bending this default.
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
  def normalize_error(_), do: :db_error

  @impl true
  def attributes(result, opts) do
    base = %{"db.operation" => opts[:operation], "db.entity" => opts[:entity]}

    case result do
      list when is_list(list) -> Map.put(base, "db.rows", length(list))
      _ -> base
    end
  end

  @impl true
  def sanitize(input, opts), do: Kind.default_sanitize(input, opts)
end
