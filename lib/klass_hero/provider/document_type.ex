defmodule KlassHero.Provider.DocumentType do
  @moduledoc """
  Custom Ecto type for a verification document's `document_type`.

  Behaves like `Ecto.Enum` on the **write** side — `cast/1` and `dump/1` accept
  only the canonical values (`valid_values/0`), so unknown values can never be
  persisted or offered in the upload form. It diverges on the **read** side:
  `Ecto.Enum` raises when it loads a value no longer in its list, so a single
  legacy row (from a narrowed enum) 500s every page that reads it (#1026). This
  type instead loads any unrecognized value as the `:unknown` sentinel, so stale
  data degrades gracefully instead of taking a page down.

  `:unknown` is load-only: it is never castable, so it never enters the write path
  or `valid_values/0`.
  """

  use Ecto.Type

  @valid [
    :business_registration,
    :insurance_certificate,
    :id_document,
    :tax_certificate,
    :experience_validation,
    :background_check,
    :video_screening,
    :safeguarding_certificate,
    :other
  ]

  @doc "Canonical document types accepted on write (excludes the `:unknown` load sentinel)."
  @spec valid_values() :: [atom()]
  def valid_values, do: @valid

  @impl true
  def type, do: :string

  @impl true
  def cast(value) when value in @valid, do: {:ok, value}

  def cast(value) when is_binary(value) do
    case Enum.find(@valid, &(Atom.to_string(&1) == value)) do
      nil -> :error
      atom -> {:ok, atom}
    end
  end

  def cast(_), do: :error

  @impl true
  def load(nil), do: {:ok, nil}

  def load(value) when is_binary(value) do
    case cast(value) do
      {:ok, atom} -> {:ok, atom}
      :error -> {:ok, :unknown}
    end
  end

  @impl true
  def dump(value) when value in @valid, do: {:ok, Atom.to_string(value)}
  def dump(value) when is_binary(value), do: cast(value) |> normalize_dump()
  def dump(_), do: :error

  defp normalize_dump({:ok, atom}), do: {:ok, Atom.to_string(atom)}
  defp normalize_dump(:error), do: :error
end
