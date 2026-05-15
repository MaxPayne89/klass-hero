defmodule KlassHero.Shared.NameUtils do
  @moduledoc """
  String utilities for derived display values like initials.
  """

  @doc """
  Returns up-to-two uppercased initials taken from the first two
  whitespace-separated tokens of `name`. Robust to leading, trailing,
  and consecutive whitespace.

  Returns `"?"` when the name is nil, non-binary, or contains no tokens.
  """
  @spec initials_from_name(String.t() | nil | term()) :: String.t()
  def initials_from_name(nil), do: "?"

  def initials_from_name(name) when is_binary(name) do
    case String.split(name, ~r/\s+/, trim: true) do
      [] ->
        "?"

      tokens ->
        tokens
        |> Enum.take(2)
        |> Enum.map_join("", &(&1 |> String.first() |> String.upcase()))
    end
  end

  def initials_from_name(_), do: "?"
end
