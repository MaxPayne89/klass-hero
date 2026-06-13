defmodule KlassHero.ProgramCatalog.Domain.Services.ProgramFilter do
  @moduledoc """
  Domain service for filtering programs by search query.

  Implements word-boundary matching: matches programs where any word in the
  title starts with the search query, ignoring special characters and case.

  This is a pure domain service with no repository interaction.
  """

  alias KlassHero.ProgramCatalog.Domain.Models.Program
  alias KlassHero.ProgramCatalog.Domain.ReadModels.ProgramListing

  @max_query_length 100

  @doc """
  Sanitizes a search query by trimming whitespace and limiting length.

  Returns empty string for nil input.

  ## Examples

      iex> ProgramFilter.sanitize_query("  art  ")
      "art"

      iex> ProgramFilter.sanitize_query(nil)
      ""

      iex> ProgramFilter.sanitize_query(String.duplicate("a", 150))
      String.duplicate("a", 100)
  """
  @spec sanitize_query(String.t() | nil) :: String.t()
  def sanitize_query(nil), do: ""

  def sanitize_query(query) when is_binary(query) do
    query
    |> String.trim()
    |> String.slice(0, @max_query_length)
  end

  @doc """
  Filters programs by search query using word-boundary matching.

  Returns all programs if query is empty or whitespace-only.
  Returns programs where any word in the title starts with the normalized query.

  ## Examples

      iex> programs = [
      ...>   %Program{id: "1", title: "After School Soccer"},
      ...>   %Program{id: "2", title: "Summer Dance Camp"}
      ...> ]
      iex> ProgramFilter.execute(programs, "soc")
      [%Program{id: "1", title: "After School Soccer"}]

      iex> ProgramFilter.execute(programs, "")
      [%Program{id: "1", title: "After School Soccer"}, %Program{id: "2", title: "Summer Dance Camp"}]
  """
  @spec execute([Program.t() | ProgramListing.t()], String.t()) :: [
          Program.t() | ProgramListing.t()
        ]
  def execute(programs, query) when is_list(programs) and is_binary(query) do
    normalized_query = normalize(query)

    if String.trim(normalized_query) == "" do
      programs
    else
      Enum.filter(programs, fn program ->
        matches_word_boundary?(program.title, normalized_query)
      end)
    end
  end

  @spec matches_word_boundary?(String.t(), String.t()) :: boolean()
  defp matches_word_boundary?(title, normalized_query) do
    title
    |> title_words()
    |> Enum.any?(&String.starts_with?(&1, normalized_query))
  end

  @spec title_words(String.t()) :: [String.t()]
  defp title_words(title) do
    title
    |> normalize()
    |> String.split(~r/\s+/, trim: true)
  end

  # Strips non-word punctuation (preserves Unicode \w including accented letters), lowercases.
  @spec normalize(String.t()) :: String.t()
  defp normalize(text) do
    text
    |> String.replace(~r/[^\w\s]/u, "")
    |> String.downcase()
  end
end
