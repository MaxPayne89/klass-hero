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

  @doc """
  Splits a single display name into `{first_name, last_name}` on the first
  whitespace run. Robust to leading/trailing/consecutive whitespace; the
  remainder after the first token becomes the last name ("Anna Maria Schmidt"
  → `{"Anna", "Maria Schmidt"}`). A single-token name yields an empty last
  name; nil/non-binary input yields `{"", ""}`.
  """
  @spec split_first_last(String.t() | nil | term()) :: {String.t(), String.t()}
  def split_first_last(name) when is_binary(name) do
    case String.split(name, ~r/\s+/, trim: true) do
      [] -> {"", ""}
      [first] -> {first, ""}
      [first | rest] -> {first, Enum.join(rest, " ")}
    end
  end

  def split_first_last(_), do: {"", ""}
end
