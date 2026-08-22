defmodule KlassHero.Provider.CompletedVia do
  @moduledoc """
  Custom Ecto type for a `VerificationStep`'s `completed_via`.

  The functional core pattern-matches on `completed_via` **tuples**
  (`{:document, type}` / `{:stripe_identity}` / `{:signed_agreement, kind}`); the
  database stores a single string column. This type is the boundary that encodes
  the tuple to its wire form on write and rebuilds it on read, so the loaded
  struct carries the tuple the aggregate expects — no separate mapper needed.

  Wire forms:

      {:stripe_identity}                    <-> "stripe_identity"
      {:document, "experience_validation"}  <-> "document:experience_validation"
      {:signed_agreement, :community_agreement} <-> "signed_agreement:community_agreement"
  """

  use Ecto.Type

  @impl true
  def type, do: :string

  @impl true
  def cast({:stripe_identity} = value), do: {:ok, value}
  def cast({:document, type} = value) when is_binary(type), do: {:ok, value}
  def cast({:signed_agreement, kind} = value) when is_atom(kind), do: {:ok, value}
  def cast(value) when is_binary(value), do: load(value)
  def cast(_), do: :error

  @impl true
  def load("stripe_identity"), do: {:ok, {:stripe_identity}}
  def load("document:" <> type) when byte_size(type) > 0, do: {:ok, {:document, type}}

  def load("signed_agreement:" <> kind) when byte_size(kind) > 0 do
    {:ok, {:signed_agreement, String.to_existing_atom(kind)}}
  rescue
    ArgumentError -> :error
  end

  def load(_), do: :error

  @impl true
  def dump({:stripe_identity}), do: {:ok, "stripe_identity"}
  def dump({:document, type}) when is_binary(type), do: {:ok, "document:" <> type}

  def dump({:signed_agreement, kind}) when is_atom(kind) and not is_nil(kind),
    do: {:ok, "signed_agreement:" <> Atom.to_string(kind)}

  def dump(_), do: :error
end
