defmodule KlassHero.Accounts.UserRoles do
  @moduledoc """
  Custom Ecto type for user role arrays. Stores as `text[]` in PostgreSQL,
  loads as atoms in Elixir. Accepts both atoms and strings; deduplicates on cast.

  Uses `embed_as(:dump)` so domain event payloads receive string values for JSON compatibility.
  """

  use Ecto.Type

  alias KlassHero.Accounts.UserRole

  @impl true
  def type, do: {:array, :string}

  @impl true
  def cast(nil), do: {:ok, []}
  def cast([]), do: {:ok, []}

  def cast(roles) when is_list(roles) do
    transform_roles(roles, &normalize_role/1, finalize: &Enum.uniq/1)
  end

  def cast(_), do: :error

  @impl true
  def load(nil), do: {:ok, []}
  def load([]), do: {:ok, []}

  def load(roles) when is_list(roles) do
    transform_roles(roles, fn role_str ->
      case UserRole.from_string(role_str) do
        {:ok, atom_role} -> {:ok, atom_role}
        {:error, _} -> :error
      end
    end)
  end

  def load(_), do: :error

  @impl true
  def dump(nil), do: {:ok, []}
  def dump([]), do: {:ok, []}

  def dump(roles) when is_list(roles) do
    transform_roles(roles, fn role ->
      case UserRole.to_string(role) do
        {:ok, str_role} -> {:ok, str_role}
        {:error, _} -> :error
      end
    end)
  end

  def dump(_), do: :error

  @impl true
  def embed_as(_), do: :dump

  defp transform_roles(roles, transform_fn, opts \\ []) do
    finalize = Keyword.get(opts, :finalize, &Function.identity/1)

    roles
    |> Enum.reduce_while([], fn role, acc ->
      case transform_fn.(role) do
        {:ok, transformed} -> {:cont, [transformed | acc]}
        :error -> {:halt, :error}
      end
    end)
    |> case do
      :error -> :error
      transformed -> {:ok, transformed |> Enum.reverse() |> finalize.()}
    end
  end

  defp normalize_role(role) when is_atom(role) do
    if UserRole.valid_role?(role), do: {:ok, role}, else: :error
  end

  defp normalize_role(role) when is_binary(role) do
    case UserRole.from_string(role) do
      {:ok, atom_role} -> {:ok, atom_role}
      {:error, _} -> :error
    end
  end

  defp normalize_role(_), do: :error
end
